import Foundation
import Testing
@testable import SkillsManagerCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}()

private func date(_ s: String) -> Date { ISODate.parse(s)! }

private func finding(_ owner: String, _ repo: String, _ skills: [(String, String?)]) -> SourceFinding {
    SourceFinding(owner: owner, repo: repo, skills: skills.map {
        NewSkill(folder: $0.0, name: $0.0, summary: $0.1, path: "skills/\($0.0)/SKILL.md")
    })
}

@Test func dailyDueAcrossMidnightNotWithinSameDay() {
    let night = date("2026-10-25T03:30:00Z")    // Oct 24, 23:30 New York
    let later = date("2026-10-25T03:59:00Z")    // still Oct 24 in New York
    let morning = date("2026-10-25T05:01:00Z")  // Oct 25, 01:01 New York
    #expect(SourceUpdatesRules.isDailyDue(lastCompleted: nil, now: night, calendar: cal))
    #expect(!SourceUpdatesRules.isDailyDue(lastCompleted: night, now: later, calendar: cal))
    #expect(SourceUpdatesRules.isDailyDue(lastCompleted: night, now: morning, calendar: cal))
}

@Test func manualCooldownIsTenMinutesFromStart() {
    let t0 = date("2026-10-25T12:00:00Z")
    #expect(SourceUpdatesRules.manualCooldown == 600)
    #expect(SourceUpdatesRules.isManualAllowed(lastStarted: nil, now: t0))
    #expect(!SourceUpdatesRules.isManualAllowed(lastStarted: t0, now: t0.addingTimeInterval(599)))
    #expect(SourceUpdatesRules.isManualAllowed(lastStarted: t0, now: t0.addingTimeInterval(600)))
}

@Test func incompleteRunDoesNotAdvanceLastCompleted() {
    let t0 = date("2026-10-25T12:00:00Z")
    let previous = date("2026-10-24T12:00:00Z")
    #expect(SourceUpdatesRules.nextLastCompleted(previous: nil, result: SourceCheckResult(findings: [], completed: false), now: t0) == nil)
    #expect(SourceUpdatesRules.nextLastCompleted(previous: previous, result: SourceCheckResult(findings: [], completed: false), now: t0) == previous)
    #expect(SourceUpdatesRules.nextLastCompleted(previous: nil, result: SourceCheckResult(findings: [], completed: true), now: t0) == t0)
}

@Test func unannouncedAndNotificationCopy() {
    let f = [finding("jakubkrehel", "skills", [("teardown", "Take it apart")]),
             finding("emil", "skills", [("a", nil), ("b", "B"), ("c", nil), ("d", nil)])]
    let keys = SourceUpdatesRules.unannouncedKeys(findings: f, notified: ["emil/skills#a"])
    #expect(keys == ["jakubkrehel/skills#teardown", "emil/skills#b", "emil/skills#c", "emil/skills#d"])

    let many = SourceUpdatesRules.notificationText(findings: f, unannounced: keys)
    #expect(many?.title == "4 new skills from your sources")
    #expect(many?.body == "teardown, b, c and 1 more")

    let one = SourceUpdatesRules.notificationText(findings: f, unannounced: ["jakubkrehel/skills#teardown"])
    #expect(one?.title == "New skill from jakubkrehel")
    #expect(one?.body == "teardown — Take it apart")

    let bare = SourceUpdatesRules.notificationText(findings: f, unannounced: ["emil/skills#a"])
    #expect(bare?.body == "a")

    #expect(SourceUpdatesRules.notificationText(findings: f, unannounced: []) == nil)
}

@Test func dismissalHidesUntilSomethingNew() {
    let f = [finding("o", "r", [("x", nil)])]
    #expect(SourceUpdatesRules.isVisible(findings: f, dismissedUntilNew: false))
    #expect(!SourceUpdatesRules.isVisible(findings: f, dismissedUntilNew: true))
    #expect(!SourceUpdatesRules.isVisible(findings: [], dismissedUntilNew: false))
    #expect(SourceUpdatesRules.dismissedAfterCheck(previouslyDismissed: true, unannounced: []))
    #expect(!SourceUpdatesRules.dismissedAfterCheck(previouslyDismissed: true, unannounced: ["o/r#y"]))
    #expect(!SourceUpdatesRules.dismissedAfterCheck(previouslyDismissed: false, unannounced: []))
}
