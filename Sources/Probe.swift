import Foundation

struct ScanResult {
    let chrome: [ChromeProc]
    let general: [Int32: GeneralProc]
    let listeners: [PortListener]
}

enum SystemProbe {
    static func run(_ launchPath: String, _ arguments: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func scan() -> ScanResult {
        let stats = ProcParser.parseStats(run("/bin/ps", ["-axww", "-o", "pid=,ppid=,pcpu=,rss=,lstart="]))
        let commands = ProcParser.parseCommands(run("/bin/ps", ["-axww", "-o", "pid=,command="]))

        var general: [Int32: GeneralProc] = [:]
        for (pid, command) in commands {
            let s = stats[pid]
            general[pid] = GeneralProc(pid: pid,
                                       ppid: s?.ppid ?? 0,
                                       cpuPercent: s?.cpu ?? 0,
                                       rssBytes: s?.rss ?? 0,
                                       startDate: s?.start,
                                       command: command)
        }

        let chrome = general.values.compactMap { p -> ChromeProc? in
            // Only the real Chrome bundle. Qoder's Electron ships a process also
            // named chrome_crashpad_handler, and it must never look like a target.
            guard p.command.contains("/Google Chrome.app/") else { return nil }
            return ChromeProc(pid: p.pid, ppid: p.ppid, cpuPercent: p.cpuPercent,
                              rssBytes: p.rssBytes, startDate: p.startDate, command: p.command)
        }

        return ScanResult(chrome: chrome, general: general,
                          listeners: aggregateListeners(general))
    }

    private static func aggregateListeners(_ general: [Int32: GeneralProc]) -> [PortListener] {
        let raw = ProcParser.parseListeners(
            run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"]))
        var grouped: [Int32: [Int: Set<String>]] = [:]   // pid -> port -> addresses
        for entry in raw {
            var ports = grouped[entry.pid] ?? [:]
            var addresses = ports[entry.port] ?? []
            addresses.insert(entry.address)
            ports[entry.port] = addresses
            grouped[entry.pid] = ports
        }
        var result: [PortListener] = []
        for (pid, ports) in grouped {
            guard let p = general[pid] else { continue }
            for (port, addresses) in ports {
                result.append(PortListener(pid: pid,
                                           port: port,
                                           addresses: addresses.sorted(),
                                           procName: p.name,
                                           command: p.command,
                                           startDate: p.startDate,
                                           rssBytes: p.rssBytes,
                                           isChrome: p.command.contains("/Google Chrome.app/")))
            }
        }
        return result.sorted { $0.port != $1.port ? $0.port < $1.port : $0.pid < $1.pid }
    }

    /// PIDs with a file handle inside the app bundle — these are what make Finder
    /// refuse a copy with "the item is in use".
    static func bundleHolders(bundlePath: String) -> Set<Int32> {
        let out = run("/usr/sbin/lsof", ["-F", "p", "+D", bundlePath])
        var pids = Set<Int32>()
        for line in out.split(separator: "\n") {
            guard line.hasPrefix("p") else { continue }
            if let pid = Int32(line.dropFirst()) { pids.insert(pid) }
        }
        return pids
    }

    static func bundlePath() -> String {
        let candidate = "/Applications/Google Chrome.app"
        return FileManager.default.fileExists(atPath: candidate) ? candidate : ""
    }

    @discardableResult
    static func signal(_ pid: Int32, _ sig: Int32) -> Bool {
        kill(pid, sig) == 0
    }

    static func isLive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }

    static func waitForExit(_ pid: Int32, seconds: Double) {
        let deadline = Date().addingTimeInterval(seconds)
        while isLive(pid) && Date() < deadline {
            usleep(100_000)
        }
    }
}
