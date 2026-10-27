import Foundation
import Combine

/// All @Published mutation happens on the main queue; the blocking ps/lsof work
/// runs on a global queue. Plain GCD rather than async/await because this
/// toolchain's Sendable checks reject the weak-self captures the timers need.
final class ProcessStore: ObservableObject {
    @Published private(set) var processes: [ChromeProc] = []
    @Published private(set) var listeners: [PortListener] = []
    @Published private(set) var bundleHolders: Set<Int32> = []
    @Published private(set) var bundlePath: String = ""
    @Published private(set) var lastScan: Date?
    @Published private(set) var isScanning = false
    @Published var autoRefresh = true
    @Published var refreshInterval: Double = 3
    @Published var selection: ChromeProc.ID?
    @Published var portSelection: PortListener.ID?
    @Published var message: UserMessage?

    private var general: [Int32: GeneralProc] = [:]
    private var tickToken = UUID()
    private var scanGeneration = 0

    // MARK: Derived views

    var roots: [ChromeProc] {
        processes.filter { $0.role.isRoot }
            .sorted { ($0.age ?? .greatestFiniteMagnitude) > ($1.age ?? .greatestFiniteMagnitude) }
    }

    var abandoned: [ChromeProc] { roots.filter { $0.looksAbandoned } }

    var totalHeadlessMemory: Int {
        roots.filter { $0.role == .headlessRoot }.reduce(0) { $0 + $1.rssBytes }
    }

    var nonChromeListeners: [PortListener] { listeners.filter { !$0.isChrome } }

    var exposedPorts: [PortListener] { nonChromeListeners.filter { $0.isExposed } }

    func children(of pid: Int32) -> [ChromeProc] {
        processes.filter { $0.ppid == pid }.sorted { $0.pid < $1.pid }
    }

    func subtree(of pid: Int32) -> [ChromeProc] {
        var found: [ChromeProc] = []
        var queue = [pid]
        while let current = queue.popLast() {
            for child in processes where child.ppid == current {
                found.append(child)
                queue.append(child.pid)
            }
        }
        return found
    }

    /// Every descendant of a pid, Chrome or not — used when stopping a port owner.
    func descendants(of pid: Int32) -> [Int32] {
        var found: [Int32] = []
        var queue = [pid]
        while let current = queue.popLast() {
            for (childPid, proc) in general where proc.ppid == current {
                found.append(childPid)
                queue.append(childPid)
            }
        }
        return found
    }

    func proc(_ pid: ChromeProc.ID) -> ChromeProc? {
        processes.first { $0.pid == pid }
    }

    func listener(_ id: PortListener.ID) -> PortListener? {
        listeners.first { $0.id == id }
    }

    // MARK: Scanning

    func start() {
        bundlePath = SystemProbe.bundlePath()
        refresh()
        scheduleTick()
    }

    func scheduleTick() {
        tickToken = UUID()
        guard autoRefresh else { return }
        let token = tickToken
        let delay = refreshInterval
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard self.tickToken == token, self.autoRefresh else { return }
            self.refresh()
            self.scheduleTick()
        }
    }

    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        scanGeneration += 1
        let generation = scanGeneration
        let path = bundlePath
        DispatchQueue.global(qos: .userInitiated).async {
            let result = SystemProbe.scan()
            let holders = path.isEmpty ? Set<Int32>() : SystemProbe.bundleHolders(bundlePath: path)
            DispatchQueue.main.async {
                guard generation == self.scanGeneration else { return }
                self.processes = result.chrome
                self.general = result.general
                self.listeners = result.listeners
                self.bundleHolders = holders
                self.lastScan = Date()
                self.isScanning = false
                if let selected = self.selection, !result.chrome.contains(where: { $0.pid == selected }) {
                    self.selection = nil
                }
                if let selected = self.portSelection, !result.listeners.contains(where: { $0.id == selected }) {
                    self.portSelection = nil
                }
            }
        }
    }

    // MARK: Actions

    /// SIGTERM the whole tree, then SIGKILL whatever is still alive.
    func killTree(_ root: ChromeProc, force: Bool = false, announce: Bool = true) {
        let tree = descendants(of: root.pid)
        if announce {
            message = tree.isEmpty
                ? UserMessage(key: "msg_stopping", args: [root.pid])
                : UserMessage(key: "msg_stopping_tree", args: [root.pid, tree.count])
        }
        terminate(root: root.pid, tree: tree, force: force)
    }

    func killListener(_ listener: PortListener, force: Bool = false) {
        let tree = descendants(of: listener.pid)
        message = tree.isEmpty
            ? UserMessage(key: "msg_stopping", args: [listener.pid])
            : UserMessage(key: "msg_stopping_tree", args: [listener.pid, tree.count])
        terminate(root: listener.pid, tree: tree, force: force)
    }

    private func terminate(root: Int32, tree: [Int32], force: Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            if force {
                tree.forEach { SystemProbe.signal($0, SIGKILL) }
                SystemProbe.signal(root, SIGKILL)
            } else {
                SystemProbe.signal(root, SIGTERM)
                tree.forEach { SystemProbe.signal($0, SIGTERM) }
                SystemProbe.waitForExit(root, seconds: 1.5)
                if SystemProbe.isLive(root) { SystemProbe.signal(root, SIGKILL) }
                tree.filter(SystemProbe.isLive).forEach { SystemProbe.signal($0, SIGKILL) }
            }
            usleep(600_000)
            DispatchQueue.main.async { self.refresh() }
        }
    }

    func killAllAbandoned() {
        let targets = abandoned
        guard !targets.isEmpty else {
            message = UserMessage(key: "msg_nothing", args: [])
            return
        }
        message = UserMessage(key: "msg_stopping_many", args: [targets.count])
        for target in targets { killTree(target, announce: false) }
    }

    /// The exact fix for Finder's "Google Chrome.app is in use" — but it only
    /// ever stops automation instances. Quitting a visible Chrome could throw
    /// away unsaved tabs, so that stays the user's own decision.
    func releaseBundleLock() {
        let blockers = processes.filter {
            bundleHolders.contains($0.pid) && $0.role == .headlessRoot
        }
        let visibleHolders = processes.filter {
            bundleHolders.contains($0.pid) && $0.role == .headedRoot
        }
        if blockers.isEmpty {
            message = visibleHolders.isEmpty
                ? UserMessage(key: "msg_nolock", args: [])
                : UserMessage(key: "msg_onlyvisible", args: [])
            return
        }
        message = UserMessage(key: "msg_releasing", args: [blockers.count])
        for blocker in blockers { killTree(blocker, announce: false) }
    }
}
