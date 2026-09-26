import Foundation

/// Which part of the library the sidebar shows (spec §3). Membership is
/// decided from the location data each row already carries; matching is by
/// canonical project root, never by display name.
public enum LibraryScope: Sendable, Hashable {
    case everywhere
    case project(root: URL)
    case cowork

    // MARK: Membership

    public func contains(_ entry: SkillEntry) -> Bool {
        switch self {
        case .everywhere: return true
        case .project(let root):
            return entry.locations.contains { includes(source: $0.skill.source, root: root) }
        case .cowork:
            return entry.locations.contains { if case .account = $0.skill.source { return true }; return false }
        }
    }

    public func contains(_ entry: PluginEntry) -> Bool {
        switch self {
        case .everywhere: return true
        case .project(let root):
            return entry.locations.contains {
                switch $0.plugin.scope {
                case .user: true
                case .project(let r): r.path == root.path
                case .cowork: false
                }
            }
        case .cowork:
            return entry.locations.contains { $0.plugin.scope == .cowork }
        }
    }

    /// Unconnected shared skills (~/.agents/skills) aren't usable in any project.
    public func containsSharedSkill() -> Bool { self == .everywhere }

    private func includes(source: SkillSource, root: URL) -> Bool {
        switch source {
        case .personal, .shared, .plugin, .account: true
        case .project(let r, _): r.path == root.path
        }
    }

    // MARK: Usage

    public func includes(_ event: SkillUsageEvent) -> Bool {
        switch self {
        case .everywhere: true
        case .project(let root): event.projectRoot?.path == root.path
        case .cowork: event.source == .cowork
        }
    }

    // MARK: Presentation and persistence

    public func label(projects: [Project]) -> String {
        switch self {
        case .everywhere: "Everywhere"
        case .cowork: "Cowork"
        case .project(let root):
            projects.first { $0.root.path == root.path }?.displayName ?? root.lastPathComponent
        }
    }

    public var persistenceKey: String {
        switch self {
        case .everywhere: "everywhere"
        case .cowork: "cowork"
        case .project(let root): "project:\(root.path)"
        }
    }

    /// A persisted project that the inventory no longer knows falls back to
    /// `.everywhere` (spec §6).
    public static func from(persistenceKey: String?, projects: [Project]) -> LibraryScope {
        guard let key = persistenceKey else { return .everywhere }
        if key == "cowork" { return .cowork }
        if key.hasPrefix("project:") {
            let path = String(key.dropFirst("project:".count))
            if let project = projects.first(where: { $0.root.path == path }) { return .project(root: project.root) }
        }
        return .everywhere
    }

    /// Rows the scope hides, across plugins, skills, built-in skills and
    /// unconnected shared skills (spec §5 footer note).
    public static func hiddenCount(in library: Library, sharedSkills: [Skill], scope: LibraryScope) -> Int {
        let plugins = library.plugins.filter { !scope.contains($0) }.count
        let skills = (library.skills + library.builtIn).filter { !scope.contains($0) }.count
        let shared = scope.containsSharedSkill() ? 0 : sharedSkills.count
        return plugins + skills + shared
    }

    /// Rows available in a scope — plugins, skills, and built-in skills
    /// (spec §5: the Showing menu's per-project trailing count).
    public static func availableCount(in library: Library, scope: LibraryScope) -> Int {
        let plugins = library.plugins.filter { scope.contains($0) }.count
        let skills = (library.skills + library.builtIn).filter { scope.contains($0) }.count
        return plugins + skills
    }

    /// Items specific to this exact location — never global/account items,
    /// even when they are visible in the scope (spec: per-project menu count).
    public static func specificCount(in library: Library, scope: LibraryScope) -> Int {
        switch scope {
        case .everywhere:
            return availableCount(in: library, scope: scope)
        case .cowork:
            return library.plugins.filter { entry in
                entry.locations.contains { $0.plugin.scope == .cowork }
            }.count
        case .project(let root):
            let skills = library.skills.filter { entry in
                entry.locations.contains {
                    if case .project(let r, _) = $0.skill.source { return r.path == root.path }
                    return false
                }
            }.count
            let plugins = library.plugins.filter { entry in
                entry.locations.contains {
                    if case .project(let r) = $0.plugin.scope { return r.path == root.path }
                    return false
                }
            }.count
            return skills + plugins
        }
    }
}
