import Foundation

enum ProcRole: String, CaseIterable {
    case headlessRoot
    case headedRoot
    case helper
    case crashpad
    case other

    var isRoot: Bool { self == .headlessRoot || self == .headedRoot }

    func title(_ l: L10n) -> String { l["role_\(rawValue)"] }
}

struct ChromeProc: Identifiable, Hashable {
    let pid: Int32
    let ppid: Int32
    let cpuPercent: Double
    let rssBytes: Int
    let startDate: Date?
    let command: String

    var id: Int32 { pid }

    var role: ProcRole {
        if command.contains("chrome_crashpad_handler") { return .crashpad }
        if debugPort != nil || command.contains("--headless") {
            return command.contains("--type=") ? .helper : .headlessRoot
        }
        if command.contains("--type=") { return .helper }
        if command.contains("/MacOS/Google Chrome") { return .headedRoot }
        return .other
    }

    /// A process the agent sessions left behind: it was launched by a shell that
    /// is gone, so nothing owns it any more and it survives until killed.
    /// Only meaningful for headless instances — a Chrome opened from the Dock is
    /// parented to launchd too, and that says nothing about who owns it.
    var isOrphan: Bool { ppid == 1 && role == .headlessRoot }

    var debugPort: Int? { flagValue("--remote-debugging-port").flatMap(Int.init) }
    var userDataDir: String? { flagValue("--user-data-dir") }
    var typeValue: String? { flagValue("--type") }

    var targetURL: String? {
        for token in command.split(separator: " ") {
            if token.hasPrefix("http://") || token.hasPrefix("https://") { return String(token) }
        }
        return nil
    }

    var age: TimeInterval? {
        startDate.map { Date().timeIntervalSince($0) }
    }

    /// Headless + orphaned + nobody is talking to its debug port.
    var looksAbandoned: Bool {
        role == .headlessRoot && isOrphan
    }

    func label(_ l: L10n) -> String {
        if let url = targetURL { return url }
        if let dir = userDataDir { return (dir as NSString).lastPathComponent }
        if role == .headedRoot { return l["headed_label"] }
        return command
    }

    private func flagValue(_ name: String) -> String? {
        guard let range = command.range(of: name + "=") else { return nil }
        let rest = command[range.upperBound...]
        if let space = rest.firstIndex(where: { $0 == " " || $0 == "\t" }) {
            return String(rest[..<space])
        }
        return String(rest)
    }
}

struct GeneralProc: Hashable {
    let pid: Int32
    let ppid: Int32
    let cpuPercent: Double
    let rssBytes: Int
    let startDate: Date?
    let command: String

    var name: String {
        ((command.split(separator: " ").first).map(String.init) ?? command)
            .split(separator: "/").last.map(String.init) ?? command
    }
}

struct PortListener: Identifiable, Hashable {
    let pid: Int32
    let port: Int
    let addresses: [String]
    let procName: String
    let command: String
    let startDate: Date?
    let rssBytes: Int
    let isChrome: Bool

    var id: String { "\(pid):\(port)" }
    var age: TimeInterval? { startDate.map { Date().timeIntervalSince($0) } }

    /// Bound to a wildcard address, so anything on the network can reach it.
    var isExposed: Bool {
        addresses.contains { $0 == "*" || $0 == "::" || $0.hasSuffix(".0.0.0") || $0.hasPrefix("0.0.0.0") }
    }
}

enum ProcParser {
    /// `ps -axww -o pid=,ppid=,pcpu=,rss=,lstart=`
    static func parseStats(_ output: String) -> [Int32: (ppid: Int32, cpu: Double, rss: Int, start: Date?)] {
        var result: [Int32: (Int32, Double, Int, Date?)] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 9,
                  let pid = Int32(fields[0]), let ppid = Int32(fields[1]),
                  let cpu = Double(fields[2]), let rss = Int(fields[3]) else { continue }
            let dateText = fields[4...].joined(separator: " ")
            result[pid] = (ppid, cpu, rss * 1024, date(dateText))
        }
        return result
    }

    /// `ps -axww -o pid=,command=`
    static func parseCommands(_ output: String) -> [Int32: String] {
        var result: [Int32: String] = [:]
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let space = line.firstIndex(of: " ") else { continue }
            let head = line[line.startIndex..<space]
            guard let pid = Int32(head), pid > 0 else { continue }
            result[pid] = String(line[line.index(after: space)...])
        }
        return result
    }

    /// `lsof -nP -iTCP -sTCP:LISTEN -F pcn` — field mode, because a table layout
    /// shifts columns whenever a command name contains a space.
    static func parseListeners(_ output: String) -> [(pid: Int32, address: String, port: Int)] {
        var pid: Int32 = 0
        var result: [(Int32, String, Int)] = []
        for line in output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": pid = Int32(value) ?? 0
            case "n":
                guard pid != 0, let (address, port) = splitAddressPort(value) else { continue }
                result.append((pid, address, port))
            default: break
            }
        }
        return result
    }

    static func splitAddressPort(_ name: String) -> (String, Int)? {
        var text = name
        if let space = text.firstIndex(of: " ") { text = String(text[..<space]) }
        guard let idx = text.lastIndex(of: ":") else { return nil }
        let host = String(text[..<idx])
        guard let port = Int(text[text.index(after: idx)...]), port > 0 else { return nil }
        return (host.isEmpty ? "*" : host, port)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return f
    }()

    private static func date(_ text: String) -> Date? {
        dateFormatter.date(from: text)
    }
}
