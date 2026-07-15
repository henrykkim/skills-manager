import Foundation
import Observation
import SkillsManagerCore

@MainActor
@Observable
final class InventoryStore {
    private(set) var inventory = Inventory()
    private(set) var isLoading = false
    private let paths = ClaudePaths()
    private var watcher: FileWatcher?
    private var loadGeneration = 0

    /// Idempotent: first call loads and starts watching; later calls are no-ops.
    func start() {
        guard watcher == nil else { return }
        reload()
        // Watch the home root; react only to the §6.2 paths (skills, plugins,
        // settings.json, ~/.agents) — not ~/.claude/projects/history churn.
        watcher = FileWatcher(
            root: paths.home,
            targets: [paths.personalSkillsDir, paths.pluginsDir, paths.settingsFile, paths.agentsDir]
        ) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
    }

    /// Generation counter (not an isLoading guard): a change landing mid-load
    /// starts a fresh scan, and a stale scan can never overwrite a newer one.
    func reload() {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        let paths = self.paths
        Task.detached(priority: .userInitiated) {
            let loaded = Inventory.load(paths: paths)
            await MainActor.run { [weak self] in
                guard let self, generation == self.loadGeneration else { return }
                self.inventory = loaded
                self.isLoading = false
            }
        }
    }
}
