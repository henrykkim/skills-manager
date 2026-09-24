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
    public let plugin: Plugin        // user-scope copy when there is one
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
        func tag(for skill: Skill) -> LocationTag {
            switch skill.source {
            case .personal, .shared, .plugin: .global
            case .account: .account
            case .project(let root, _): .project(name: names[root.path] ?? root.lastPathComponent)
            }
        }

        var lib = Library()

        // Personal + project skills merge by folder name (= the command).
        let grouped = Dictionary(grouping: personal + project, by: \.folderName)
        for (folder, copies) in grouped {
            let primary = copies.first { $0.source == .personal }
                ?? copies.sorted { tag(for: $0).label.localizedStandardCompare(tag(for: $1).label) == .orderedAscending }[0]
            let hasGlobal = primary.source == .personal
            let primaryData = skillData(primary)
            let locations = copies.map { copy in
                SkillLocation(skill: copy, tag: tag(for: copy),
                              isIgnored: hasGlobal && copy.source != .personal,
                              differsFromPrimary: copy.id != primary.id && skillData(copy) != primaryData)
            }
            // Strict weak ordering: (tag rank, tag label, skill id). The brief's
            // pairwise `LocationTag.sorted([a.tag, b.tag])` comparator collapses to a
            // single element via its de-dup Set when a.tag == b.tag (e.g. two nested
            // project copies sharing a project name), making `.first == a.tag` true
            // for both (a,b) and (b,a) — violating asymmetry and crashing/misordering
            // `sorted`. Compare the rank/label/id tuple directly instead.
            .sorted { a, b in
                (a.tag.rank, a.tag.label, a.skill.id) < (b.tag.rank, b.tag.label, b.skill.id)
            }
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
                case .project(let root): .project(name: names[root.path] ?? root.lastPathComponent)
                }
                return PluginLocation(plugin: p, tag: t)
            }
            let primary = copies.first { $0.scope == .user } ?? copies[0]
            lib.plugins.append(PluginEntry(id: id, plugin: primary, locations: locations))
        }

        let byName: (SkillEntry, SkillEntry) -> Bool = {
            $0.skill.displayName.localizedStandardCompare($1.skill.displayName) == .orderedAscending
        }
        lib.skills.sort { byName($0, $1) || ($0.skill.displayName == $1.skill.displayName && $0.id < $1.id) }
        lib.builtIn.sort(by: byName)
        lib.plugins.sort { $0.plugin.name.localizedStandardCompare($1.plugin.name) == .orderedAscending }
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
