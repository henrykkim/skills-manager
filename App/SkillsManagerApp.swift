import SwiftUI

@main
struct SkillsManagerApp: App {
    @State private var store = InventoryStore()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(store)
                .task { store.start() }
                .frame(minWidth: 760, minHeight: 480)
        }
        // Reload is automatic (FSEvents); ⌘R is a manual fallback.
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Install…") { NotificationCenter.default.post(name: .showInstallSheet, object: nil) }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh") { store.reload() }
                    .keyboardShortcut("r")
                    .disabled(store.isLoading)
            }
        }
    }
}
