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

    /// `.name` keeps the library's own order. Otherwise used skills come first
    /// by the chosen measure; never-used skills keep name order after them (spec §7).
    public static func sorted(_ entries: [SkillEntry], by sort: UsageSort, stats: UsageStats) -> [SkillEntry] {
        let byName: (SkillEntry, SkillEntry) -> Bool = {
            let c = $0.skill.displayName.localizedStandardCompare($1.skill.displayName)
            return c != .orderedSame ? c == .orderedAscending : $0.id < $1.id
        }
        if sort == .name { return entries.sorted(by: byName) }
        let summaries = Dictionary(entries.map { ($0.id, stats.summary(for: $0.skill)) }, uniquingKeysWith: { first, _ in first })
        return entries.sorted { a, b in
            switch (summaries[a.id]!, summaries[b.id]!) {
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
}
