import Foundation

public enum UsageWindow: String, CaseIterable, Sendable, Hashable {
    case last30Days, allTime

    public var label: String {
        switch self {
        case .last30Days: "Last 30 days"
        case .allTime: "All time"
        }
    }

    func cutoff(now: Date) -> Date? {
        switch self {
        case .last30Days: now.addingTimeInterval(-30 * 86_400)
        case .allTime: nil
        }
    }
}

/// One project's share of a skill's usage. `projectRoot == nil` is Cowork.
public struct ProjectUsage: Sendable, Hashable {
    public let projectRoot: URL?
    public let count: Int
    public let lastUsed: Date
}

public struct UsageSummary: Sendable, Hashable {
    public let lastUsed: Date
    public let firstUsed: Date
    public let countInWindow: Int
    public let allTimeCount: Int
    /// Most used first, then most recent, then path; Cowork (nil root) sorts by the same rule.
    public let byProject: [ProjectUsage]
}

/// The name a skill appears under in session logs: the typed command minus
/// its slash. Same source of truth as the cheat sheet (spec §6).
public enum UsageKey {
    public static func key(for skill: Skill) -> String {
        String(Invocation.string(for: skill).dropFirst())
    }
}

/// Aggregations over the event list, computed on read (spec §5).
public struct UsageStats: Sendable {
    public let window: UsageWindow
    /// Computed once at init — the key set is small, so every `summary(forKey:)`
    /// call is a plain dictionary lookup rather than re-aggregating events.
    private let summaries: [String: UsageSummary]

    public init(events: [SkillUsageEvent], window: UsageWindow, now: Date = Date()) {
        self.window = window
        let cutoff = window.cutoff(now: now)
        let byKey = Dictionary(grouping: events, by: \.skillName)
        summaries = byKey.compactMapValues { events in
            Self.summary(for: events, cutoff: cutoff)
        }
    }

    public var isEmpty: Bool { summaries.isEmpty }

    public func summary(for skill: Skill) -> UsageSummary? { summary(forKey: UsageKey.key(for: skill)) }

    public func summary(forKey key: String) -> UsageSummary? { summaries[key] }

    public func summary(forPlugin plugin: Plugin) -> UsageSummary? {
        let skillSummaries = plugin.skills.compactMap { summary(for: $0) }
        guard !skillSummaries.isEmpty else { return nil }
        let lastUsed = skillSummaries.map(\.lastUsed).max()!
        let firstUsed = skillSummaries.map(\.firstUsed).min()!
        let countInWindow = skillSummaries.reduce(0) { $0 + $1.countInWindow }
        let allTimeCount = skillSummaries.reduce(0) { $0 + $1.allTimeCount }
        var merged: [String: ProjectUsage] = [:]
        for s in skillSummaries {
            for p in s.byProject {
                let key = p.projectRoot?.path ?? ""
                if let existing = merged[key] {
                    merged[key] = ProjectUsage(projectRoot: existing.projectRoot,
                                                count: existing.count + p.count,
                                                lastUsed: max(existing.lastUsed, p.lastUsed))
                } else {
                    merged[key] = p
                }
            }
        }
        let byProject = merged.values.sorted { a, b in
            if a.count != b.count { return a.count > b.count }
            if a.lastUsed != b.lastUsed { return a.lastUsed > b.lastUsed }
            return (a.projectRoot?.path ?? "") < (b.projectRoot?.path ?? "")
        }
        return UsageSummary(lastUsed: lastUsed, firstUsed: firstUsed, countInWindow: countInWindow,
                             allTimeCount: allTimeCount, byProject: byProject)
    }

    private static func summary(for events: [SkillUsageEvent], cutoff: Date?) -> UsageSummary? {
        guard let last = events.map(\.timestamp).max(),
              let first = events.map(\.timestamp).min() else { return nil }
        let inWindow = cutoff.map { c in events.filter { $0.timestamp >= c }.count } ?? events.count
        let projects = Dictionary(grouping: events, by: { $0.projectRoot?.path }).map { path, evs in
            ProjectUsage(projectRoot: path.map { URL(fileURLWithPath: $0, isDirectory: true) },
                         count: evs.count, lastUsed: evs.map(\.timestamp).max()!)
        }.sorted { a, b in
            if a.count != b.count { return a.count > b.count }
            if a.lastUsed != b.lastUsed { return a.lastUsed > b.lastUsed }
            return (a.projectRoot?.path ?? "") < (b.projectRoot?.path ?? "")
        }
        return UsageSummary(lastUsed: last, firstUsed: first, countInWindow: inWindow, allTimeCount: events.count, byProject: projects)
    }
}

public enum UsageSort: String, CaseIterable, Sendable, Hashable {
    case name, lastUsed, mostUsed

    public var label: String {
        switch self {
        case .name: "Name"
        case .lastUsed: "Last used"
        case .mostUsed: "Most used"
        }
    }

    /// `.name` keeps the library's own order. Otherwise used entries come first
    /// by the chosen measure; never-used entries keep name order after them (spec §7).
    /// Shared by `sorted(_:by:stats:)` and `sortedPlugins(_:by:stats:)`.
    private static func order<T>(_ entries: [T], by sort: UsageSort,
                                  name: @escaping (T) -> String, id: @escaping (T) -> String,
                                  summary: (T) -> UsageSummary?) -> [T] {
        let byName: (T, T) -> Bool = {
            let c = name($0).localizedStandardCompare(name($1))
            return c != .orderedSame ? c == .orderedAscending : id($0) < id($1)
        }
        if sort == .name { return entries.sorted(by: byName) }
        let summaries = Dictionary(entries.map { (id($0), summary($0)) }, uniquingKeysWith: { first, _ in first })
        return entries.sorted { a, b in
            switch (summaries[id(a)]!, summaries[id(b)]!) {
            case (nil, nil): return byName(a, b)
            case (nil, _): return false
            case (_, nil): return true
            case (let sa?, let sb?):
                if sort == .mostUsed, sa.countInWindow != sb.countInWindow { return sa.countInWindow > sb.countInWindow }
                if sa.lastUsed != sb.lastUsed { return sa.lastUsed > sb.lastUsed }
                return byName(a, b)
            }
        }
    }

    public static func sorted(_ entries: [SkillEntry], by sort: UsageSort, stats: UsageStats) -> [SkillEntry] {
        order(entries, by: sort, name: { $0.skill.displayName }, id: \.id, summary: { stats.summary(for: $0.skill) })
    }

    /// Same semantics as `sorted(_:by:stats:)`, for plugins.
    public static func sortedPlugins(_ entries: [PluginEntry], by sort: UsageSort, stats: UsageStats) -> [PluginEntry] {
        order(entries, by: sort, name: { $0.plugin.name }, id: \.id, summary: { stats.summary(forPlugin: $0.plugin) })
    }
}
