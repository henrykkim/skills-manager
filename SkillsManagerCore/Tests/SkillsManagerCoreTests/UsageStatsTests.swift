import Foundation
import Testing
@testable import SkillsManagerCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func day(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }
private func ev(_ name: String, _ ts: Date, root: String? = "/p", source: UsageSource = .claudeCode) -> SkillUsageEvent {
    SkillUsageEvent(skillName: name, timestamp: ts,
                    projectRoot: root.map { URL(fileURLWithPath: $0, isDirectory: true) },
                    sessionID: "s", source: source, logFile: "/l")
}
private func skill(_ folder: String, source: SkillSource = .personal) -> Skill {
    Skill(folderName: folder, displayName: folder.capitalized, summary: nil, argumentHint: nil,
          userInvocable: true, modelInvocable: true, whenToUse: nil, source: source,
          directory: URL(fileURLWithPath: "/skills/\(folder)"), lastModified: nil)
}
private func entry(_ folder: String, source: SkillSource = .personal) -> SkillEntry {
    let s = skill(folder, source: source)
    return SkillEntry(id: "skill:\(folder)", skill: s,
                      locations: [SkillLocation(skill: s, tag: .global, isIgnored: false, differsFromPrimary: false)],
                      copiesDiffer: false)
}

@Test func keysMatchLoggedNames() {
    #expect(UsageKey.key(for: skill("brainstorming", source: .plugin(pluginID: "superpowers@claude-plugins-official"))) == "superpowers:brainstorming")
    #expect(UsageKey.key(for: skill("henry-stylist", source: .account(userMade: true))) == "anthropic-skills:henry-stylist")
    #expect(UsageKey.key(for: skill("apple-design")) == "apple-design")
    #expect(UsageKey.key(for: skill("x", source: .project(root: URL(fileURLWithPath: "/p"), subpath: nil))) == "x")
}

@Test func windowBoundaryIs30Days() {
    let stats = UsageStats(events: [ev("a", day(29)), ev("a", day(31)), ev("a", day(30))], window: .last30Days, now: now)
    let s = stats.summary(forKey: "a")
    #expect(s?.countInWindow == 2)    // 29 and exactly 30 count; 31 does not
    #expect(s?.allTimeCount == 3)
    #expect(s?.lastUsed == day(29))
    #expect(UsageStats(events: [ev("a", day(31))], window: .allTime, now: now).summary(forKey: "a")?.countInWindow == 1)
}

@Test func neverUsedIsNil() {
    #expect(UsageStats(events: [ev("a", day(1))], window: .allTime, now: now).summary(forKey: "zzz") == nil)
}

@Test func byProjectGroupsAndOrdersByCountThenRecency() {
    let events = [ev("a", day(1), root: "/p1"), ev("a", day(2), root: "/p2"), ev("a", day(3), root: "/p2"),
                  ev("a", day(4), root: nil, source: .cowork)]
    let s = UsageStats(events: events, window: .allTime, now: now).summary(forKey: "a")!
    #expect(s.byProject.map { $0.projectRoot?.path } == ["/p2", "/p1", nil])
    #expect(s.byProject.map(\.count) == [2, 1, 1])
    #expect(s.byProject[0].lastUsed == day(2))
}

@Test func sortingPutsNeverUsedLast() {
    let a = entry("a"), b = entry("b"), c = entry("c")
    let stats = UsageStats(events: [ev("a", day(5)), ev("c", day(1)), ev("c", day(2))], window: .allTime, now: now)
    #expect(UsageSort.sorted([a, b, c], by: .lastUsed, stats: stats).map(\.id) == ["skill:c", "skill:a", "skill:b"])
    #expect(UsageSort.sorted([a, b, c], by: .mostUsed, stats: stats).map(\.id) == ["skill:c", "skill:a", "skill:b"])
    #expect(UsageSort.sorted([c, b, a], by: .name, stats: stats).map(\.id) == ["skill:a", "skill:b", "skill:c"])
}

@Test func mostUsedTiesBreakByRecencyThenName() {
    let a = entry("a"), b = entry("b")
    let stats = UsageStats(events: [ev("a", day(5)), ev("b", day(1))], window: .allTime, now: now)
    #expect(UsageSort.sorted([a, b], by: .mostUsed, stats: stats).map(\.id) == ["skill:b", "skill:a"])
}
