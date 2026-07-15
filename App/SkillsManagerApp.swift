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
    }
}
