import SwiftUI

@main
struct ChromeJanitorApp: App {
    @StateObject private var store = ProcessStore()
    @ObservedObject private var l = L10n.shared

    var body: some Scene {
        WindowGroup("Chrome Janitor") {
            ContentView(store: store, l: l)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Button(l["menu_rescan"]) { store.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                Button(l["menu_clean"]) { store.killAllAbandoned() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
    }
}
