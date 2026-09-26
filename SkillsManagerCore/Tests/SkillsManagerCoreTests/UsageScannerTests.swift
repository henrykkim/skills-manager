import Foundation
import Testing
@testable import SkillsManagerCore

private func skillLine(_ name: String, at ts: String = "2026-08-04T03:16:57Z", cwd: String = "/p") -> String {
    #"{"type":"assistant","timestamp":"\#(ts)","cwd":"\#(cwd)","sessionId":"s","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"\#(name)"}}]}}"#
}

@Test func scansClaudeCodeAndCoworkRoots() throws {
    let t = try TempTree(); defer { t.remove() }
    try t.write(skillLine("a") + "\n", to: "logs/-Users-x-p/s1.jsonl")
    try t.write(skillLine("b") + "\n", to: "cowork/acct/org/local_1/.claude/projects/-sessions-x/s2.jsonl")
    try t.write(skillLine("ignored") + "\n", to: "cowork/skills-plugin/acct/org/manifest.jsonl")   // not under .claude/projects
    let store = UsageScanner.scan(claudeCodeLogs: t.url("logs"), coworkSessions: t.url("cowork"), previous: UsageStoreData())
    let byName = Dictionary(grouping: store.events, by: \.skillName)
    #expect(byName["a"]?.first?.source == .claudeCode)
    #expect(byName["b"]?.first?.source == .cowork)
    #expect(byName["ignored"] == nil)
    #expect(store.cursors.count == 2)
}

@Test func missingRootsAreEmpty() throws {
    let t = try TempTree(); defer { t.remove() }
    let store = UsageScanner.scan(claudeCodeLogs: t.url("none"), coworkSessions: t.url("none2"), previous: UsageStoreData())
    #expect(store == UsageStoreData())
}

@Test func secondScanReadsOnlyNewBytes() throws {
    let t = try TempTree(); defer { t.remove() }
    let file = try t.write(skillLine("a") + "\n", to: "logs/x/s1.jsonl")
    let first = UsageScanner.scan(claudeCodeLogs: t.url("logs"), coworkSessions: t.url("none"), previous: UsageStoreData())
    #expect(first.events.count == 1)
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data((skillLine("b") + "\n").utf8))
    try handle.close()
    let second = UsageScanner.scan(claudeCodeLogs: t.url("logs"), coworkSessions: t.url("none"), previous: first)
    #expect(second.events.map(\.skillName) == ["a", "b"])
    // Unchanged file: third scan adds nothing.
    let third = UsageScanner.scan(claudeCodeLogs: t.url("logs"), coworkSessions: t.url("none"), previous: second)
    #expect(third == second)
}

@Test func malformedLineIsSkippedAndCursorAdvances() throws {
    let t = try TempTree(); defer { t.remove() }
    let text = "{broken\n" + skillLine("a") + "\n"
    try t.write(text, to: "logs/x/s1.jsonl")
    let store = UsageScanner.scan(claudeCodeLogs: t.url("logs"), coworkSessions: t.url("none"), previous: UsageStoreData())
    #expect(store.events.map(\.skillName) == ["a"])
    #expect(store.cursors.values.first?.byteOffset == text.utf8.count)
}

@Test func shrunkFileIsRescannedWithoutDuplicates() throws {
    let t = try TempTree(); defer { t.remove() }
    let file = try t.write(skillLine("a") + "\n" + skillLine("b") + "\n", to: "logs/x/s1.jsonl")
    let first = UsageScanner.scan(claudeCodeLogs: t.url("logs"), coworkSessions: t.url("none"), previous: UsageStoreData())
    #expect(first.events.count == 2)
    try (skillLine("c") + "\n").write(to: file, atomically: true, encoding: .utf8)
    let second = UsageScanner.scan(claudeCodeLogs: t.url("logs"), coworkSessions: t.url("none"), previous: first)
    #expect(second.events.map(\.skillName) == ["c"])
}

@Test func partialTrailingLineWaitsForNextScan() throws {
    let t = try TempTree(); defer { t.remove() }
    let full = skillLine("a") + "\n"
    let partial = String(skillLine("b").prefix(40))
    let file = try t.write(full + partial, to: "logs/x/s1.jsonl")
    let first = UsageScanner.scan(claudeCodeLogs: t.url("logs"), coworkSessions: t.url("none"), previous: UsageStoreData())
    #expect(first.events.map(\.skillName) == ["a"])
    #expect(first.cursors.values.first?.byteOffset == full.utf8.count)
    let rest = String(skillLine("b").dropFirst(40)) + "\n"
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(rest.utf8))
    try handle.close()
    let second = UsageScanner.scan(claudeCodeLogs: t.url("logs"), coworkSessions: t.url("none"), previous: first)
    #expect(second.events.map(\.skillName) == ["a", "b"])
}
