import Foundation
import Combine
import AppKit

enum AppLanguage: String, CaseIterable, Identifiable {
    case vi, en
    var id: String { rawValue }
    var menuTitle: String { self == .vi ? "Tiếng Việt" : "English" }
}

/// A message is stored as a key plus arguments rather than a finished string, so
/// switching language re-renders whatever the footer is already showing.
struct UserMessage {
    let key: String
    let args: [CVarArg]
}

final class L10n: ObservableObject {
    static let shared = L10n()

    private static let defaultsKey = "janitor.language"

    @Published var language: AppLanguage {
        didSet {
            let defaults = UserDefaults.standard
            defaults.set(language.rawValue, forKey: Self.defaultsKey)
            // AppKit picks up AppleLanguages from this app's own domain when
            // deciding how to localise its standard menus — but only at launch.
            defaults.set([language.rawValue], forKey: "AppleLanguages")
            needsRestart = true
        }
    }

    @Published var needsRestart = false

    private init() {
        if let saved = UserDefaults.standard.string(forKey: Self.defaultsKey),
           let lang = AppLanguage(rawValue: saved) {
            language = lang
        } else {
            language = Locale.current.languageCode == "vi" ? .vi : .en
        }
        // Keep the app-domain override in sync, so AppKit's menus and the
        // in-app strings agree from the next launch onwards.
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
    }

    subscript(_ key: String) -> String {
        guard let pair = Self.strings[key] else { return key }
        return language == .vi ? pair.0 : pair.1
    }

    func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: self[key], arguments: args)
    }

    func render(_ message: UserMessage) -> String {
        String(format: self[message.key], arguments: message.args)
    }

    /// Relaunch so AppKit rebuilds its standard menus in the new language.
    func restartApp() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL,
                                           configuration: config) { _, _ in
            NSApplication.shared.terminate(nil)
        }
        needsRestart = false
    }

    /// (vietnamese, english)
    private static let strings: [String: (String, String)] = [
        // Header
        "subtitle": ("Tiến trình Chrome headless do các phiên agent để lại",
                     "Headless instances left behind by agent sessions"),
        "stat_abandoned": ("Bỏ hoang", "Abandoned"),
        "stat_headless": ("Headless", "Headless"),
        "stat_memory": ("Bộ nhớ", "Memory"),
        "filter_placeholder": ("Lọc theo pid, url, tham số…",
                               "Filter by pid, url, flag…"),
        "rescan_help": ("Quét lại ngay", "Rescan now"),

        // List
        "only_abandoned": ("Chỉ hiện bỏ hoang", "Only abandoned"),
        "instances_count": ("%d tiến trình Chrome", "%d instance(s)"),
        "row_pid": ("pid %d", "pid %d"),
        "row_parent": ("cha %d", "parent %d"),
        "row_up": ("chạy %@", "up %@"),
        "row_helpers": ("%d tiến trình con", "%d helper(s)"),
        "row_cdp": ("cdp :%d", "cdp :%d"),
        "empty_none": ("Không có tiến trình Chrome nào đang chạy.",
                       "No Chrome processes running."),
        "empty_filtered": ("Không có mục nào khớp bộ lọc.",
                           "Nothing matches this filter."),

        // Badges
        "badge_headless": ("HEADLESS", "HEADLESS"),
        "badge_orphan": ("BỎ HOANG", "ORPHAN"),
        "badge_browser": ("TRÌNH DUYỆT CỦA BẠN", "YOUR BROWSER"),
        "badge_bundle": ("ĐANG GIỮ APP BUNDLE", "HOLDS APP BUNDLE"),

        // Roles
        "role_headlessRoot": ("Phiên headless", "Headless instance"),
        "role_headedRoot": ("Chrome đang hiển thị", "Visible Chrome"),
        "role_helper": ("Tiến trình con", "Helper"),
        "role_crashpad": ("Trình xử lý lỗi", "Crash handler"),
        "role_other": ("Khác", "Other"),
        "headed_label": ("Google Chrome — cửa sổ đang hiển thị",
                         "Google Chrome — visible windows"),

        // Detail
        "detail_orphaned": ("BỎ HOANG — không còn phiên nào sở hữu",
                            "ORPHANED — no owning session"),
        "detail_callout": ("Khởi động từ một shell đã thoát nên không còn gì quản lý nó. Đã chạy %@ — an toàn để dừng nếu không có phiên nào còn dùng %@.",
                           "Launched by a shell that has since exited, so nothing will close it. Uptime %@ — safe to stop unless a session is still using %@."),
        "callout_port": ("cổng debug :%d", "debug port :%d"),
        "callout_socket": ("socket của nó", "its socket"),
        "lbl_pid": ("PID", "PID"),
        "lbl_parent": ("Tiến trình cha", "Parent"),
        "lbl_started": ("Khởi động lúc", "Started"),
        "lbl_uptime": ("Thời gian chạy", "Uptime"),
        "lbl_cpu": ("CPU", "CPU"),
        "lbl_memory": ("Bộ nhớ", "Memory"),
        "lbl_port": ("Cổng debug", "Debug port"),
        "lbl_profile": ("Hồ sơ", "Profile"),
        "parent_orphan": ("1 (launchd — phiên đã sinh ra nó không còn nữa)",
                          "1 (launchd — the session that spawned it is gone)"),
        "parent_dock": ("1 (launchd — mở từ Dock/Finder, bình thường)",
                        "1 (launchd — opened from Dock/Finder, this is normal)"),
        "section_command": ("Dòng lệnh", "Command line"),
        "section_children": ("Tiến trình con (%d)", "Child processes (%d)"),
        "none": ("không có", "none"),
        "btn_terminate": ("Dừng cả cây", "Terminate tree"),
        "btn_force": ("Buộc dừng cả cây", "Force kill tree"),
        "btn_copy": ("Sao chép lệnh", "Copy command"),
        "empty_state_title": ("Không có gì để dọn", "Nothing to clean up"),
        "empty_state_pick": ("Chọn một tiến trình", "Select an instance"),
        "empty_state_sub": ("Mọi tiến trình Chrome trên máy đều nằm ở danh sách bên trái.",
                            "Every Chrome process on this machine is listed on the left."),

        // Footer
        "footer_hint": ("Cẩn thận khi dừng Chrome đang hiển thị — có thể mất các tab chưa lưu.",
                        "Double-check before stopping a visible Chrome — it can carry unsaved tabs."),
        "btn_release": ("Giải khoá bundle (chỉ headless)", "Release lock (headless only)"),
        "btn_release_help": ("Dừng đúng những tiến trình headless đang giữ /Applications/Google Chrome.app — thủ phạm của lỗi “Google Chrome.app is in use”. Chrome đang hiển thị của bạn không bao giờ bị đụng tới.",
                             "Stop the headless instances holding /Applications/Google Chrome.app — the processes behind Finder's “Google Chrome.app is in use”. Your visible browser is never touched."),
        "btn_clean": ("Dọn hết bỏ hoang", "Clean all abandoned"),
        "scanned_at": ("quét lúc %@", "scanned %@"),
        "auto": ("Tự động", "Auto"),

        // Messages
        "msg_stopping": ("Đang dừng PID %d…", "Stopping PID %d…"),
        "msg_stopping_tree": ("Đang dừng PID %d và %d tiến trình con…",
                              "Stopping PID %d and %d child process(es)…"),
        "msg_stopping_many": ("Đang dừng %d phiên bỏ hoang…",
                              "Stopping %d abandoned instance(s)…"),
        "msg_nothing": ("Không có gì bỏ hoang để dọn.", "Nothing abandoned to clean."),
        "msg_nolock": ("Không tiến trình Chrome nào đang giữ app bundle.",
                       "No Chrome process is holding the app bundle."),
        "msg_onlyvisible": ("Chỉ Chrome đang hiển thị của bạn còn giữ bundle — hãy thoát nó từ thanh menu.",
                            "Only your visible Chrome holds the bundle — quit it from the menu bar."),
        "msg_releasing": ("Đang dừng %d phiên headless đang giữ bundle…",
                          "Stopping %d headless instance(s) holding the bundle…"),

        // Alert
        "alert_title": ("Dọn tất cả phiên bỏ hoang?", "Clean all abandoned instances?"),
        "alert_body": ("%d phiên headless không còn phiên nào sở hữu. Các tiến trình con của chúng cũng sẽ dừng theo.",
                       "These %d headless instance(s) have no owning session left. Their helper processes will be stopped with them."),
        "alert_confirm": ("Dừng %d", "Stop %d"),
        "alert_cancel": ("Huỷ", "Cancel"),

        // Ports tab
        "tab_chrome": ("Chrome", "Chrome"),
        "tab_ports": ("Cổng", "Ports"),
        "ports_subtitle": ("Các cổng TCP do tiến trình ngoài Chrome đang giữ",
                           "TCP ports held by non-Chrome processes"),
        "stat_listening": ("Đang lắng nghe", "Listening"),
        "stat_exposed": ("Mở ra mạng", "Exposed"),
        "ports_filter": ("Lọc theo cổng, tên tiến trình, pid…",
                         "Filter by port, process, pid…"),
        "ports_hide_chrome": ("Ẩn tiến trình Chrome", "Hide Chrome processes"),
        "ports_count": ("%d cổng", "%d port(s)"),
        "badge_exposed": ("MỞ RA MẠNG", "EXPOSED"),
        "badge_local": ("VÒNG NỘI", "LOCALHOST"),
        "badge_chrome": ("CHROME", "CHROME"),
        "lbl_process": ("Tiến trình", "Process"),
        "lbl_port_number": ("Cổng", "Port"),
        "lbl_addresses": ("Địa chỉ", "Addresses"),
        "ports_empty_none": ("Không có tiến trình nào đang lắng nghe cổng TCP.",
                             "Nothing is listening on a TCP port."),
        "ports_empty_filtered": ("Không có cổng nào khớp bộ lọc.",
                                 "No ports match this filter."),
        "ports_detail_title": ("%@ · cổng %d", "%@ · port %d"),
        "ports_pick": ("Chọn một cổng", "Select a port"),
        "btn_stop_port": ("Dừng tiến trình giữ cổng", "Stop process holding port"),
        "port_tree_radius": ("%d tiến trình con sẽ dừng theo.", "%d child process(es) stop with it."),
        "port_tree_none": ("Không có tiến trình con nào khác.", "It has no child processes."),
        "confirm_port_title": ("Dừng tiến trình giữ cổng?", "Stop the process holding this port?"),
        "confirm_port_body": ("%@ (pid %d) đang giữ cổng này. %@",
                              "%@ (pid %d) holds this port. %@"),
        "ports_hint": ("Dừng một tiến trình sẽ giải phóng cổng của nó — kiểm tra xem còn phiên nào đang dùng không.",
                       "Stopping a process frees its port — check nothing is still using it."),
        "exposed_help": ("Tiến trình này bind vào địa chỉ *, nên mọi máy trong cùng mạng có thể kết nối tới cổng này.",
                         "This process binds a wildcard address, so anything on the network can reach this port."),

        // Menu
        "menu_rescan": ("Quét lại ngay", "Rescan now"),
        "menu_clean": ("Dọn hết bỏ hoang", "Clean all abandoned"),
        "menu_language": ("Ngôn ngữ", "Language"),
        "restart_hint": ("Khởi động lại để dịch cả menu hệ thống",
                         "Restart to translate the system menus too"),
        "btn_restart": ("Khởi động lại", "Restart"),

        // Duration units
        "unit_days": (" ngày", "d"),
        "unit_hours": (" giờ", "h"),
        "unit_minutes": (" phút", "m"),
    ]
}
