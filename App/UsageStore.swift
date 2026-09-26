import Foundation
import Observation
import SkillsManagerCore

/// Owns the usage feature's one file and its on/off switch (spec §8).
/// Everything shown in the UI comes from `stats`.
@MainActor
@Observable
final class UsageStore {
    private(set) var stats = UsageStats(events: [], window: .last30Days)
    /// When the most recent scan completed. Nil before the first scan.
    private(set) var lastScanned: Date?
    /// Whether a scan is currently running, off the main thread.
    private(set) var isScanning = false
    var eventCount: Int { data.events.count }
    var sessionCount: Int { Set(data.events.map(\.sessionID)).count }
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
        isScanning = true
        let paths = self.paths
        let url = Self.storeURL
        Task.detached(priority: .utility) {
            let previous = UsageStoreFile.load(at: url)
            let next = UsageScanner.scan(claudeCodeLogs: paths.claudeCodeLogsDir,
                                         coworkSessions: paths.coworkSessionsDir, previous: previous)
            if next != previous { try? UsageStoreFile.save(next, to: url) }
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard generation == self.refreshGeneration else {
                    // Superseded by a later refresh (or by clear()). If
                    // tracking is now off, the save above may have recreated
                    // the file after clear() deleted it — remove it again. If
                    // tracking is still on, a newer refresh owns the file.
                    if !self.isEnabled { UsageStoreFile.delete(at: url) }
                    return
                }
                defer { self.isScanning = false }
                guard self.isEnabled else {
                    // Tracking was turned off while this scan's save was in
                    // flight: the save above may have recreated the file
                    // after clear() deleted it, so remove it again now that
                    // we're back on the main actor.
                    UsageStoreFile.delete(at: url)
                    return
                }
                self.data = next
                self.lastScanned = Date()
                self.rebuildStats()
            }
        }
    }

    private func clear() {
        refreshGeneration += 1
        isScanning = false
        UsageStoreFile.delete(at: Self.storeURL)
        data = UsageStoreData()
        lastScanned = nil
        rebuildStats()
    }

    private func rebuildStats() {
        stats = UsageStats(events: data.events, window: window)
    }
}
