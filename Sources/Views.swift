import SwiftUI

// MARK: - Formatting

enum Fmt {
    static func bytes(_ value: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(value))
    }

    static func duration(_ interval: TimeInterval?, _ l: L10n) -> String {
        guard let interval = interval, interval > 0 else { return "—" }
        let seconds = Int(interval)
        let (d, h, m) = (seconds / 86_400, (seconds % 86_400) / 3_600, (seconds % 3_600) / 60)
        if d > 0 { return "\(d)\(l["unit_days"]) \(h)\(l["unit_hours"])" }
        if h > 0 { return "\(h)\(l["unit_hours"]) \(m)\(l["unit_minutes"])" }
        return "\(m)\(l["unit_minutes"])"
    }

    static func started(_ date: Date?, _ l: L10n) -> String {
        guard let date = date else { return l["none"] }
        let f = DateFormatter()
        f.locale = Locale(identifier: l.language == .vi ? "vi_VN" : "en_GB")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    static func clock(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .medium)
    }
}

// MARK: - Badge

struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14))
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(color.opacity(0.4), lineWidth: 0.5))
    }
}

// MARK: - Root tabs

enum JanitorTab: Hashable { case chrome, ports }

// MARK: - Content

struct ContentView: View {
    @ObservedObject var store: ProcessStore
    @ObservedObject var l: L10n
    @State private var tab: JanitorTab = .chrome
    @State private var confirmClearAll = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TabView(selection: $tab) {
                ChromeTab(store: store, l: l, confirmClearAll: $confirmClearAll)
                    .tabItem { Label(l["tab_chrome"], systemImage: "terminal.circle.fill") }
                    .tag(JanitorTab.chrome)
                PortsTab(store: store, l: l)
                    .tabItem { Label(l["tab_ports"], systemImage: "network") }
                    .tag(JanitorTab.ports)
            }
            Divider()
            footer
        }
        .frame(minWidth: 960, minHeight: 560)
        .onAppear { store.start() }
        .onChange(of: store.autoRefresh) { _ in store.scheduleTick() }
        .onChange(of: store.refreshInterval) { _ in store.scheduleTick() }
        .alert(l["alert_title"], isPresented: $confirmClearAll) {
            Button(l["alert_cancel"], role: .cancel) {}
            Button(l.f("alert_confirm", store.abandoned.count), role: .destructive) { store.killAllAbandoned() }
        } message: {
            Text(l.f("alert_body", store.abandoned.count))
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Chrome Janitor").font(.headline)
                Text(l[tab == .ports ? "ports_subtitle" : "subtitle"])
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if tab == .chrome {
                statView(l, l["stat_abandoned"], value: "\(store.abandoned.count)",
                         emphasis: !store.abandoned.isEmpty)
                statView(l, l["stat_headless"], value: "\(store.roots.filter { $0.role == .headlessRoot }.count)",
                         emphasis: false)
                statView(l, l["stat_memory"], value: Fmt.bytes(store.totalHeadlessMemory), emphasis: false)
            } else {
                statView(l, l["stat_listening"], value: "\(store.nonChromeListeners.count)", emphasis: false)
                statView(l, l["stat_exposed"], value: "\(store.exposedPorts.count)",
                         emphasis: !store.exposedPorts.isEmpty)
            }
            Divider().frame(height: 26)
            Picker("", selection: $l.language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.menuTitle).tag(lang)
                }
            }
            .labelsHidden()
            .frame(width: 104)
            .help(l["menu_language"])
            if l.needsRestart {
                Button(l["btn_restart"]) { l.restartApp() }
                    .help(l["restart_hint"])
            }
            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(store.isScanning)
            .help(l["rescan_help"])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(store.message.map { l.render($0) } ?? l[tab == .ports ? "ports_hint" : "footer_hint"])
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()
            if tab == .chrome {
                Button(l["btn_release"], action: store.releaseBundleLock)
                    .disabled(store.bundleHolders.isEmpty)
                    .help(l["btn_release_help"])
                Button(l["btn_clean"]) { confirmClearAll = true }
                    .disabled(store.abandoned.isEmpty)
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
            Text(store.lastScan.map { l.f("scanned_at", Fmt.clock($0)) } ?? "—")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize()
            Toggle(l["auto"], isOn: $store.autoRefresh)
                .toggleStyle(.checkbox)
                .font(.caption)
            Picker("", selection: $store.refreshInterval) {
                Text("1s").tag(1.0)
                Text("3s").tag(3.0)
                Text("10s").tag(10.0)
            }
            .labelsHidden()
            .frame(width: 66)
            .disabled(!store.autoRefresh)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Shared chrome

func statView(_ l: L10n, _ title: String, value: String, emphasis: Bool) -> some View {
    VStack(alignment: .trailing, spacing: 1) {
        Text(value)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundColor(emphasis ? .orange : .primary)
        Text(title)
            .font(.system(size: 9))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
    }
    .frame(minWidth: 52, alignment: .trailing)
}

// MARK: - Chrome tab

struct ChromeTab: View {
    @ObservedObject var store: ProcessStore
    @ObservedObject var l: L10n
    @Binding var confirmClearAll: Bool
    @State private var search = ""
    @State private var onlyAbandoned = false

    private var visibleRoots: [ChromeProc] {
        store.roots.filter { root in
            if onlyAbandoned, !root.looksAbandoned { return false }
            guard !search.isEmpty else { return true }
            let haystack = "\(root.label(l)) \(root.command) \(root.pid)".lowercased()
            return haystack.contains(search.lowercased())
        }
    }

    var body: some View {
        HSplitView {
            list.frame(minWidth: 380)
            detail.frame(minWidth: 320, maxWidth: .infinity)
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Toggle(l["only_abandoned"], isOn: $onlyAbandoned)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Spacer()
                Text(l.f("instances_count", visibleRoots.count))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            HStack {
                TextField(l["filter_placeholder"], text: $search)
                    .textFieldStyle(.roundedBorder)
                Spacer().frame(width: 8)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 7)

            List(selection: $store.selection) {
                ForEach(visibleRoots) { root in
                    RootRow(proc: root,
                            childCount: store.children(of: root.pid).count,
                            holdsBundle: store.bundleHolders.contains(root.pid),
                            l: l)
                        .tag(root.pid)
                        .contextMenu {
                            Button(l["btn_terminate"], action: { store.killTree(root) })
                            Button(l["btn_force"], action: { store.killTree(root, force: true) })
                        }
                }
                if visibleRoots.isEmpty {
                    Text(store.roots.isEmpty ? l["empty_none"] : l["empty_filtered"])
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let root = store.proc(store.selection ?? -1) ?? store.roots.first {
            DetailView(store: store, root: root, l: l)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 38, weight: .light))
                    .foregroundColor(.secondary)
                Text(store.roots.isEmpty ? l["empty_state_title"] : l["empty_state_pick"])
                    .font(.title3)
                Text(l["empty_state_sub"])
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct RootRow: View {
    let proc: ChromeProc
    let childCount: Int
    let holdsBundle: Bool
    /// Observed, not plain: List caches rows by value identity, and the shared
    /// L10n instance never changes identity, so rows would keep stale strings
    /// after a language switch without this.
    @ObservedObject var l: L10n

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundColor(tint)
                .frame(width: 18, height: 18)
                .font(.system(size: 13))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(proc.label(l))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Text(l.f("row_pid", proc.pid))
                    if proc.ppid != 1 { Text(l.f("row_parent", proc.ppid)) }
                    Text(l.f("row_up", Fmt.duration(proc.age, l)))
                    Text(Fmt.bytes(proc.rssBytes))
                    if let port = proc.debugPort { Text(l.f("row_cdp", port)) }
                    if childCount > 0 { Text(l.f("row_helpers", childCount)) }
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    if proc.role == .headlessRoot { Badge(text: l["badge_headless"], color: .blue) }
                    if proc.role == .headedRoot { Badge(text: l["badge_browser"], color: .green) }
                    if proc.isOrphan { Badge(text: l["badge_orphan"], color: .orange) }
                }
                if holdsBundle { Badge(text: l["badge_bundle"], color: .red) }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var tint: Color {
        if proc.looksAbandoned { return .orange }
        return proc.role == .headlessRoot ? .blue : .secondary
    }

    private var symbol: String {
        switch proc.role {
        case .headlessRoot: return "terminal.circle.fill"
        case .headedRoot: return "globe"
        default: return "questionmark.circle"
        }
    }
}

// MARK: - Ports tab

struct PortsTab: View {
    @ObservedObject var store: ProcessStore
    @ObservedObject var l: L10n
    @State private var search = ""
    @State private var hideChrome = true

    private var visible: [PortListener] {
        store.listeners.filter { listener in
            if hideChrome, listener.isChrome { return false }
            guard !search.isEmpty else { return true }
            let haystack = "\(listener.procName) \(listener.port) \(listener.pid) \(listener.addresses.joined(separator: " ")) \(listener.command)".lowercased()
            return haystack.contains(search.lowercased())
        }
    }

    var body: some View {
        HSplitView {
            list.frame(minWidth: 440)
            detail.frame(minWidth: 320, maxWidth: .infinity)
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Toggle(l["ports_hide_chrome"], isOn: $hideChrome)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Spacer()
                Text(l.f("ports_count", visible.count))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            HStack {
                TextField(l["ports_filter"], text: $search)
                    .textFieldStyle(.roundedBorder)
                Spacer().frame(width: 8)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 7)

            List(selection: $store.portSelection) {
                ForEach(visible) { listener in
                    PortRow(listener: listener, l: l)
                        .tag(listener.id)
                        .contextMenu {
                            Button(l["btn_stop_port"], action: { store.killListener(listener) })
                            Button(l["btn_force"], action: { store.killListener(listener, force: true) })
                        }
                }
                if visible.isEmpty {
                    Text(store.listeners.isEmpty ? l["ports_empty_none"] : l["ports_empty_filtered"])
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let listener = store.listener(store.portSelection ?? "") ?? visible.first {
            PortDetailView(store: store, listener: listener, l: l)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "network")
                    .font(.system(size: 38, weight: .light))
                    .foregroundColor(.secondary)
                Text(l["ports_subtitle"]).font(.title3)
                Text(l["ports_hint"]).font(.caption).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct PortRow: View {
    let listener: PortListener
    @ObservedObject var l: L10n

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: listener.isExposed ? "exclamationmark.triangle.fill" : "network")
                .foregroundColor(listener.isExposed ? .red : .accentColor)
                .font(.system(size: 13))
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: ":\(listener.port)  \(listener.procName)")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    Text(l.f("row_pid", listener.pid))
                    Text(listener.addresses.joined(separator: ", "))
                    Text(l.f("row_up", Fmt.duration(listener.age, l)))
                    Text(Fmt.bytes(listener.rssBytes))
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                if listener.isChrome { Badge(text: l["badge_chrome"], color: .blue) }
                Badge(text: listener.isExposed ? l["badge_exposed"] : l["badge_local"],
                      color: listener.isExposed ? .red : .green)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct PortDetailView: View {
    @ObservedObject var store: ProcessStore
    let listener: PortListener
    @ObservedObject var l: L10n

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(l.f("ports_detail_title", listener.procName, listener.port))
                        .font(.system(size: 14, weight: .semibold))
                        .textSelection(.enabled)
                    HStack(spacing: 5) {
                        Badge(text: "PID \(listener.pid)", color: .gray)
                        if listener.isChrome { Badge(text: l["badge_chrome"], color: .blue) }
                        Badge(text: listener.isExposed ? l["badge_exposed"] : l["badge_local"],
                              color: listener.isExposed ? .red : .green)
                    }
                }

                if listener.isExposed {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                        Text(l["exposed_help"]).font(.caption)
                    }
                    .padding(10)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(8)
                }

                grid

                VStack(alignment: .leading, spacing: 6) {
                    Text(l["section_command"]).font(.system(size: 9)).foregroundColor(.secondary).textCase(.uppercase)
                    Text(listener.command)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(6)
                }

                HStack(spacing: 10) {
                    Button(l["btn_stop_port"]) { store.killListener(listener) }
                    Button(l["btn_force"], role: .destructive) { store.killListener(listener, force: true) }
                    Button(l["btn_copy"]) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(listener.command, forType: .string)
                    }
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var grid: some View {
        let rows: [(String, String)] = [
            (l["lbl_process"], listener.procName),
            (l["lbl_pid"], String(listener.pid)),
            (l["lbl_port_number"], String(listener.port)),
            (l["lbl_addresses"], listener.addresses.joined(separator: ",  ")),
            (l["lbl_started"], Fmt.started(listener.startDate, l)),
            (l["lbl_uptime"], Fmt.duration(listener.age, l)),
            (l["lbl_memory"], Fmt.bytes(listener.rssBytes)),
        ]
        return VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 10) {
                    Text(row.0)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 96, alignment: .leading)
                    Text(row.1)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Chrome detail

struct DetailView: View {
    @ObservedObject var store: ProcessStore
    let root: ChromeProc
    @ObservedObject var l: L10n

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(root.label(l))
                        .font(.system(size: 14, weight: .semibold))
                        .textSelection(.enabled)
                    HStack(spacing: 5) {
                        Badge(text: root.role.title(l).uppercased(),
                              color: root.role == .headlessRoot ? .blue : .gray)
                        if root.isOrphan { Badge(text: l["detail_orphaned"], color: .orange) }
                        if store.bundleHolders.contains(root.pid) {
                            Badge(text: l["badge_bundle"], color: .red)
                        }
                    }
                }

                if root.looksAbandoned {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Text(l.f("detail_callout",
                                 Fmt.duration(root.age, l),
                                 root.debugPort.map { l.f("callout_port", $0) } ?? l["callout_socket"]))
                            .font(.caption)
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(8)
                }

                grid

                VStack(alignment: .leading, spacing: 6) {
                    Text(l["section_command"]).font(.system(size: 9)).foregroundColor(.secondary).textCase(.uppercase)
                    Text(root.command)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(6)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(l.f("section_children", store.children(of: root.pid).count))
                        .font(.system(size: 9)).foregroundColor(.secondary).textCase(.uppercase)
                    if store.children(of: root.pid).isEmpty {
                        Text(l["none"]).font(.caption).foregroundColor(.secondary)
                    }
                    ForEach(store.subtree(of: root.pid)) { child in
                        HStack(spacing: 8) {
                            Text(String(child.pid)).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                                .frame(width: 44, alignment: .leading)
                            Text(child.typeValue ?? child.role.title(l)).font(.caption)
                            Spacer()
                            Text(Fmt.bytes(child.rssBytes)).font(.caption).foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(4)
                    }
                }

                HStack(spacing: 10) {
                    Button(l["btn_terminate"]) { store.killTree(root) }
                        .keyboardShortcut("k", modifiers: .command)
                    Button(l["btn_force"], role: .destructive) { store.killTree(root, force: true) }
                    Button(l["btn_copy"]) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(root.command, forType: .string)
                    }
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var parentText: String {
        guard root.ppid == 1 else { return String(root.ppid) }
        return root.role == .headlessRoot ? l["parent_orphan"] : l["parent_dock"]
    }

    private var grid: some View {
        let rows: [(String, String)] = [
            (l["lbl_pid"], String(root.pid)),
            (l["lbl_parent"], parentText),
            (l["lbl_started"], Fmt.started(root.startDate, l)),
            (l["lbl_uptime"], Fmt.duration(root.age, l)),
            (l["lbl_cpu"], String(format: "%.1f%%", root.cpuPercent)),
            (l["lbl_memory"], Fmt.bytes(root.rssBytes)),
            (l["lbl_port"], root.debugPort.map { ":\($0)" } ?? l["none"]),
            (l["lbl_profile"], root.userDataDir.map { ($0 as NSString).lastPathComponent } ?? l["none"]),
        ]
        return VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 10) {
                    Text(row.0)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 96, alignment: .leading)
                    Text(row.1)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                }
            }
        }
    }
}
