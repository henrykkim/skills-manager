import Foundation
import Observation
import SkillsManagerCore

/// Owns the usage feature's one file and its on/off switch (spec §8).
/// Everything shown in the UI comes from `stats`.
@MainActor
@Observable
final class UsageStore {
    private(set) var stats = UsageStats(events: [], window: .last30Days)
    var window: UsageWindow {
        didSet { defaults.set(window.rawValue, forKey: Self.windowKey); rebuildStats() }
    }
    var sort: UsageSort {
        didSet { defaults.set(sort.rawValue, forKey: Self.sortKey) }
    }
    /// On by default. Off deletes the store and hides every usage surface.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled { refresh() } else { clear() }
        }
    }

    private var data = UsageStoreData()
    private let paths: ClaudePaths
    private let defaults = UserDefaults.standard
    private var refreshGeneration = 0

    private static let enabledKey = "usageTrackingEnabled"
    private static let windowKey = "usageWindow"
    private static let sortKey = "usageSort"

    static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Skills Manager/usage-events.json")
    }

    init(paths: ClaudePaths = ClaudePaths()) {
        self.paths = paths
        let d = UserDefaults.standard
        isEnabled = d.object(forKey: Self.enabledKey) == nil ? true : d.bool(forKey: Self.enabledKey)
        window = UsageWindow(rawValue: d.string(forKey: Self.windowKey) ?? "") ?? .last30Days
        sort = UsageSort(rawValue: d.string(forKey: Self.sortKey) ?? "") ?? .name
    }

    /// Incremental scan off the main thread; a stale scan never overwrites a newer one.
    func refresh() {
        guard isEnabled else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        let paths = self.paths
        let url = Self.storeURL
        Task.detached(priority: .utility) {
            let previous = UsageStoreFile.load(at: url)
            let next = UsageScanner.scan(claudeCodeLogs: paths.claudeCodeLogsDir,
                                         coworkSessions: paths.coworkSessionsDir, previous: previous)
            if next != previous { try? UsageStoreFile.save(next, to: url) }
            await MainActor.run { [weak self] in
                guard let self, generation == self.refreshGeneration, self.isEnabled else { return }
                self.data = next
                self.rebuildStats()
            }
        }
    }

    private func clear() {
        refreshGeneration += 1
        UsageStoreFile.delete(at: Self.storeURL)
        data = UsageStoreData()
        rebuildStats()
    }

    private func rebuildStats() {
        stats = UsageStats(events: data.events, window: window)
    }
}
