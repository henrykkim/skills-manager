import Foundation
import Observation
import os
import SkillsManagerCore

@MainActor
@Observable
final class InventoryStore {
    private(set) var inventory = Inventory()
    private(set) var isLoading = false
    private(set) var addedFolders: [URL]
    private(set) var needsProjectAccessNote: Bool
    /// Bundled `Recommendations.json` (spec §4). Empty in the general build.
    let recommendations: RecommendationsCatalog
    /// True until the Recommended sheet is dismissed once (spec §5).
    private(set) var needsRecommendations: Bool
    private let paths = ClaudePaths()
    private let defaults = UserDefaults.standard
    private var watcher: FileWatcher?
    private var sourcesWatcher: FileWatcher?
    private var loadGeneration = 0

    /// Set by the app so usage rescans ride along with every inventory reload.
    var onReload: (@MainActor () -> Void)?
    /// Set by the app; called only for user-initiated Refresh (menu, ⌘R), never for watcher reloads.
    var onManualRefresh: (@MainActor () -> Void)?

    private(set) var scope: LibraryScope = .everywhere
    /// Set by the app so usage stats follow the scope.
    var onScopeChange: (@MainActor (LibraryScope) -> Void)?

    private static let addedFoldersKey = "addedFolders"
    private static let projectAccessKey = "projectAccessAcknowledged"
    private static let scopeKey = "libraryScope"
    private static let recommendationsDismissedKey = "recommendationsDismissed"

    init() {
        addedFolders = (UserDefaults.standard.stringArray(forKey: Self.addedFoldersKey) ?? [])
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        needsProjectAccessNote = !UserDefaults.standard.bool(forKey: Self.projectAccessKey)
        let catalogData = Bundle.main.url(forResource: "Recommendations", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
        recommendations = RecommendationsCatalog.load(catalogData)
        if recommendations.isEmpty, let catalogData, !catalogData.isEmpty {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "SkillsManager", category: "recommendations")
                .error("Recommendations.json could not be decoded; treating the catalog as empty.")
        }
        needsRecommendations = !recommendations.isEmpty
            && !UserDefaults.standard.bool(forKey: Self.recommendationsDismissedKey)
    }

    /// Idempotent: first call loads and starts watching; later calls are no-ops.
    func start() {
        guard watcher == nil else { return }
        // Skills, plugins, settings, ~/.agents, Claude-account skills, and (after
        // each load) every project's skills folder and settings files. 1 s debounce.
        watcher = FileWatcher(root: paths.home, targets: baseTargets) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        // Claude's session and project lists change on every message while
        // Claude is in use — a long debounce keeps rescans rare (spec §6.1).
        sourcesWatcher = FileWatcher(
            root: paths.home,
            targets: [paths.claudeJSON, paths.codeSessionsDir, paths.coworkSessionsDir, paths.claudeCodeLogsDir],
            delay: 10
        ) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        // Watchers exist before the first reload so its setTargets call (with
        // the freshly-discovered projects' watch targets) isn't dropped.
        reload()
    }

    private var baseTargets: [URL] {
        [paths.personalSkillsDir, paths.pluginsDir, paths.settingsFile, paths.agentsDir, paths.accountSkillsDir]
            + addedFolders
    }

    /// Generation counter (not an isLoading guard): a change landing mid-load
    /// starts a fresh scan, and a stale scan can never overwrite a newer one.
    func reload() {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        let paths = self.paths
        let added = addedFolders
        let includeProjects = !needsProjectAccessNote
        Task.detached(priority: .userInitiated) {
            let loaded = Inventory.load(paths: paths, addedFolders: added, includeProjects: includeProjects)
            await MainActor.run { [weak self] in
                guard let self, generation == self.loadGeneration else { return }
                self.inventory = loaded
                self.isLoading = false
                self.watcher?.setTargets(self.baseTargets + loaded.projectWatchTargets)
                self.validateScope(against: loaded.projects)
                self.onReload?()
            }
        }
    }

    /// User-initiated Refresh: a normal reload, plus the manual-only hook.
    func refresh() {
        reload()
        onManualRefresh?()
    }

    func acknowledgeProjectAccess() {
        defaults.set(true, forKey: Self.projectAccessKey)
        needsProjectAccessNote = false
        reload()
    }

    /// Any dismissal (Not now, Done, closing the sheet) is permanent; the
    /// sheet stays reachable from File → Recommended….
    func dismissRecommendations() {
        defaults.set(true, forKey: Self.recommendationsDismissedKey)
        needsRecommendations = false
    }

    /// Adds a project or notes folder. Returns `.neither` (and adds nothing)
    /// for a folder with no Claude skills or markdown files.
    @discardableResult
    func addFolder(_ url: URL) -> FolderKind {
        let kind = NoteFolders.classify(url)
        guard kind != .neither else { return kind }
        let canonical = Canonical.url(url)
        guard !addedFolders.contains(where: { $0.path == canonical.path }) else { return kind }
        addedFolders.append(canonical)
        saveAddedFolders()
        reload()
        return kind
    }

    /// Forgets the folder. Never touches the disk.
    func removeFolder(_ url: URL) {
        let canonical = Canonical.url(url)
        addedFolders.removeAll { $0.path == canonical.path }
        saveAddedFolders()
        if case .project(let root) = scope, root.path == canonical.path { setScope(.everywhere) }
        reload()
    }

    func setScope(_ new: LibraryScope) {
        guard new != scope else { return }
        scope = new
        defaults.set(new.persistenceKey, forKey: Self.scopeKey)
        onScopeChange?(new)
    }

    /// After each load: a persisted or current project scope that the inventory
    /// no longer knows falls back to Everywhere, silently (spec §6).
    private func validateScope(against projects: [Project]) {
        // Deliberately does not rewrite UserDefaults when falling back (e.g. a
        // scoped project is momentarily missing from `projects`): keeping the
        // originally requested key lets the scope restore itself if that
        // project reappears in a later scan.
        let wanted = defaults.string(forKey: Self.scopeKey) ?? scope.persistenceKey
        let resolved = LibraryScope.from(persistenceKey: wanted, projects: projects)
        if resolved != scope {
            scope = resolved
            onScopeChange?(resolved)
        }
    }

    private func saveAddedFolders() {
        defaults.set(addedFolders.map(\.path), forKey: Self.addedFoldersKey)
    }
}
