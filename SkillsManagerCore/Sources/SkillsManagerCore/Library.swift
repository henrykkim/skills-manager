import Foundation

/// Where an item works, as shown on its tag (spec §4.5).
public enum LocationTag: Sendable, Hashable {
    case global
    case account
    case cowork
    case project(name: String)

    public var label: String {
        switch self {
        case .global: "Global"
        case .account: "Claude account"
        case .cowork: "Cowork"
        case .project(let name): name
        }
    }

    var rank: Int {
        switch self {
        case .global: return 0
        case .account: return 1
        case .cowork: return 2
        case .project: return 3
        }
    }

    public var isProject: Bool {
        if case .project = self { return true }
        return false
    }

    /// Global, Claude account, Cowork, then projects alphabetically; no duplicates.
    public static func sorted(_ tags: [LocationTag]) -> [LocationTag] {
        var seen = Set<LocationTag>()
        return tags.filter { seen.insert($0).inserted }.sorted { a, b in
            a.rank != b.rank ? a.rank < b.rank
                : a.label.localizedStandardCompare(b.label) == .orderedAscending
        }
    }
}

/// Shared ordering for individual locations — used by both the row tags
/// (indirectly, via `LocationTag.sorted`) and the detail page's "Where it
/// works" lines, so the two never disagree: tag rank, then localized label
/// (matching `LocationTag.sorted`, not raw `<`), then a project's root copy
/// before its nested subpath copy, then the location's own id as a final
/// deterministic tie-break. A plain tuple comparison isn't enough here
/// because label ordering must be localized, not lexicographic.
struct LocationOrderKey: Comparable {
    let tag: LocationTag
    let hasSubpath: Bool   // true = nested copy; sorts after the project's root copy
    let id: String

    static func < (a: LocationOrderKey, b: LocationOrderKey) -> Bool {
        if a.tag.rank != b.tag.rank { return a.tag.rank < b.tag.rank }
        let labelOrder = a.tag.label.localizedStandardCompare(b.tag.label)
        if labelOrder != .orderedSame { return labelOrder == .orderedAscending }
        if a.hasSubpath != b.hasSubpath { return !a.hasSubpath }
        return a.id < b.id
    }
}

public struct SkillLocation: Sendable, Hashable, Identifiable {
    public var id: String { skill.id }
    public let skill: Skill
    public let tag: LocationTag
    /// A Global copy exists, so Claude ignores this project copy.
    public let isIgnored: Bool
    /// SKILL.md isn't byte-identical to the copy Claude uses.
    public let differsFromPrimary: Bool
}

public struct SkillEntry: Sendable, Hashable, Identifiable {
    public let id: String            // "skill:<folder>" or "account:<folder>"
    public let skill: Skill          // the copy Claude uses
    public let locations: [SkillLocation]
    public let copiesDiffer: Bool
    public var tags: [LocationTag] { LocationTag.sorted(locations.map(\.tag)) }
}

public struct PluginLocation: Sendable, Hashable, Identifiable {
    public var id: String { "\(plugin.pluginID)|\(tag.label)" }
    public let plugin: Plugin
    public let tag: LocationTag
}

public struct PluginEntry: Sendable, Hashable, Identifiable {
    public let id: String            // pluginID
    public let plugin: Plugin        // user-scope copy when on; else an enabled copy
    public let locations: [PluginLocation]
    public var tags: [LocationTag] { LocationTag.sorted(locations.map(\.tag)) }
}

public struct Library: Sendable {
    public var skills: [SkillEntry] = []
    public var plugins: [PluginEntry] = []
    /// Anthropic's built-in Claude-account skills (collapsed group).
    public var builtIn: [SkillEntry] = []

    public init(skills: [SkillEntry] = [], plugins: [PluginEntry] = [], builtIn: [SkillEntry] = []) {
        self.skills = skills
        self.plugins = plugins
        self.builtIn = builtIn
    }

    public static func build(personal: [Skill], project: [Skill], account: [Skill],
                             plugins: [Plugin], projects: [Project]) -> Library {
        let names = Dictionary(projects.map { ($0.root.path, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        func projectName(for root: URL) -> String { names[root.path] ?? root.lastPathComponent }
        func tag(for skill: Skill) -> LocationTag {
            switch skill.source {
            case .personal, .shared, .plugin: .global
            case .account: .account
            case .project(let root, _): .project(name: projectName(for: root))
            }
        }
        func hasSubpath(_ skill: Skill) -> Bool {
            if case .project(_, let subpath) = skill.source { return subpath != nil }
            return false
        }
        func orderKey(_ skill: Skill) -> LocationOrderKey {
            LocationOrderKey(tag: tag(for: skill), hasSubpath: hasSubpath(skill), id: skill.id)
        }

        var lib = Library()

        // Personal + project skills merge by folder name (= the command).
        let grouped = Dictionary(grouping: personal + project, by: \.folderName)
        for (folder, copies) in grouped {
            // No Global copy: the first location in the shared order becomes primary
            // (deterministic — e.g. a project's root copy beats its nested copy).
            let primary = copies.first { $0.source == .personal }
                ?? copies.min { orderKey($0) < orderKey($1) }!
            let hasGlobal = primary.source == .personal
            let primaryData = skillData(primary)
            let locations = copies.map { copy in
                SkillLocation(skill: copy, tag: tag(for: copy),
                              isIgnored: hasGlobal && copy.source != .personal,
                              differsFromPrimary: copy.id != primary.id && skillData(copy) != primaryData)
            }
            .sorted { orderKey($0.skill) < orderKey($1.skill) }
            lib.skills.append(SkillEntry(id: "skill:\(folder)", skill: primary, locations: locations,
                                         copiesDiffer: locations.contains(where: \.differsFromPrimary)))
        }

        // Claude-account skills are namespaced commands: never merged.
        for skill in account {
            let entry = SkillEntry(id: "account:\(skill.folderName)", skill: skill,
                                   locations: [SkillLocation(skill: skill, tag: .account, isIgnored: false,
                                                             differsFromPrimary: false)],
                                   copiesDiffer: false)
            if case .account(userMade: true) = skill.source { lib.skills.append(entry) } else { lib.builtIn.append(entry) }
        }

        // Plugins merge by ID.
        for (id, copies) in Dictionary(grouping: plugins, by: \.pluginID) {
            let locations = copies.map { p -> PluginLocation in
                let t: LocationTag = switch p.scope {
                case .user: .global
                case .cowork: .cowork
                case .project(let root): .project(name: projectName(for: root))
                }
                return PluginLocation(plugin: p, tag: t)
            }
            // The row reads the primary's on/off state: prefer the user copy when
            // it's on, then any copy that's on, then the user copy, then the first.
            let user = copies.first { $0.scope == .user }
            let primary = (user?.isEnabled == true ? user : nil)
                ?? copies.first(where: \.isEnabled) ?? user ?? copies[0]
            lib.plugins.append(PluginEntry(id: id, plugin: primary, locations: locations))
        }

        let byName: (SkillEntry, SkillEntry) -> Bool = {
            $0.skill.displayName.localizedStandardCompare($1.skill.displayName) == .orderedAscending
        }
        lib.skills.sort { byName($0, $1) || ($0.skill.displayName == $1.skill.displayName && $0.id < $1.id) }
        lib.builtIn.sort(by: byName)
        // Dictionary(grouping:) iteration order is randomized per launch, so break
        // ties on id after name to keep this deterministic.
        lib.plugins.sort { a, b in
            let byName = a.plugin.name.localizedStandardCompare(b.plugin.name)
            return byName != .orderedSame ? byName == .orderedAscending : a.id < b.id
        }
        return lib
    }

    private static func skillData(_ skill: Skill) -> Data? {
        try? Data(contentsOf: skill.directory.appending(path: "SKILL.md"))
    }
}

public enum TagLayout {
    /// Every non-project tag, then at most `maxProjects` project tags; the rest overflow into "+N".
    public static func split(_ tags: [LocationTag], maxProjects: Int = 2) -> (shown: [LocationTag], overflow: [LocationTag]) {
        let sorted = LocationTag.sorted(tags)
        let fixed = sorted.filter { !$0.isProject }
        let projects = sorted.filter(\.isProject)
        return (fixed + projects.prefix(maxProjects), Array(projects.dropFirst(maxProjects)))
    }
}
