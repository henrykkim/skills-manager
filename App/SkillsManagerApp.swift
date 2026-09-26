import Sparkle
import SwiftUI

@main
struct SkillsManagerApp: App {
    @State private var store = InventoryStore()
    @State private var usage = UsageStore()
    /// Sparkle's standard updater: checks on its own schedule (release builds
    /// only — see SU_AUTOMATIC_CHECKS) and always asks before installing.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(store)
                .environment(usage)
                .task {
                    store.onReload = { usage.refresh() }
                    store.start()
                }
                .frame(minWidth: 760, minHeight: 480)
        }
        // Reload is automatic (FSEvents); ⌘R is a manual fallback.
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            CommandGroup(replacing: .newItem) {
                Button("Install…") { NotificationCenter.default.post(name: .showInstallSheet, object: nil) }
                    .keyboardShortcut("n")
                Button("Add Folder…") { NotificationCenter.default.post(name: .showAddFolder, object: nil) }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh") { store.reload() }
                    .keyboardShortcut("r")
                    .disabled(store.isLoading)
            }
        }
    }
}
