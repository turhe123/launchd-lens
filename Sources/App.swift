import AppKit
import SwiftUI

/// App entry point: one main window, a Settings window and the job menu commands.
@main
struct LaunchdLensApp: App {
    @StateObject private var store = JobStore()

    var body: some Scene {
        Window("LaunchdLens", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 860, minHeight: 580)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Job…") { store.showTemplates = true }.keyboardShortcut("n")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { store.save() }
                    .keyboardShortcut("s")
                    .disabled(store.draft == nil || store.readOnly)
            }
            CommandMenu("Job") {
                Button("Run Now") { Task { await store.runNow() } }.keyboardShortcut("r")
                Button("Load") { Task { await store.load() } }
                Button("Unload") { Task { await store.unload() } }
                Divider()
                Button("Reload List") { Task { await store.reloadList() } }.keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandGroup(after: .help) {
                Button("Support / Donate ❤️") { openDonation() }
            }
        }
        Settings { SettingsView() }
    }
}

/// Opens the project's donation page in the default browser.
func openDonation() {
    NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
}
