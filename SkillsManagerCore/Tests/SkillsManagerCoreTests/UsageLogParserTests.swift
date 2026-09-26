import Foundation
import Testing
@testable import SkillsManagerCore

private let skillLine = #"""
{"type":"assistant","timestamp":"2026-08-04T03:16:57.855Z","cwd":"/Users/x/proj","sessionId":"d95d","version":"2.1.219","message":{"role":"assistant","content":[{"type":"text","text":"hi"},{"type":"tool_use","id":"toolu_1","name":"Skill","input":{"skill":"superpowers:brainstorming","args":"secret args"}}]}}
"""#

@Test func parsesSkillInvocation() {
    let events = UsageLogParser.events(inLine: Data(skillLine.utf8), source: .claudeCode, logFile: "/l/a.jsonl")
    #expect(events.count == 1)
    let e = events[0]
    #expect(e.skillName == "superpowers:brainstorming")
    #expect(e.timestamp == ISODate.parse("2026-08-04T03:16:57.855Z"))
    #expect(e.projectRoot?.path == "/Users/x/proj")
    #expect(e.sessionID == "d95d")
    #expect(e.source == .claudeCode)
    #expect(e.logFile == "/l/a.jsonl")
}

@Test func ignoresOtherToolsAndUserLines() {
    let bash = #"{"type":"assistant","timestamp":"2026-08-04T03:16:57Z","cwd":"/p","sessionId":"s","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}"#
    let user = #"{"type":"user","timestamp":"2026-08-04T03:16:57Z","cwd":"/p","sessionId":"s","message":{"role":"user","content":"plain string content"}}"#
    let read = #"{"type":"assistant","timestamp":"2026-08-04T03:16:57Z","cwd":"/p","sessionId":"s","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/x/SKILL.md"}}]}}"#
    for line in [bash, user, read] {
        #expect(UsageLogParser.events(inLine: Data(line.utf8), source: .claudeCode, logFile: "/l").isEmpty)
    }
}

@Test func malformedOrIncompleteLinesYieldNothing() {
    let broken = "{not json"
    let noTimestamp = #"{"type":"assistant","cwd":"/p","sessionId":"s","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"x"}}]}}"#
    let noSkill = #"{"type":"assistant","timestamp":"2026-08-04T03:16:57Z","cwd":"/p","sessionId":"s","message":{"content":[{"type":"tool_use","name":"Skill","input":{}}]}}"#
    for line in [broken, noTimestamp, noSkill, ""] {
        #expect(UsageLogParser.events(inLine: Data(line.utf8), source: .claudeCode, logFile: "/l").isEmpty)
    }
}

@Test func coworkLinesDropSandboxProject() {
    let line = #"{"type":"assistant","timestamp":"2026-08-04T03:16:57Z","cwd":"/sessions/loving-feynman","sessionId":"s","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"x"}}]}}"#
    let events = UsageLogParser.events(inLine: Data(line.utf8), source: .cowork, logFile: "/l")
    #expect(events.count == 1)
    #expect(events[0].projectRoot == nil)
    #expect(events[0].source == .cowork)
}

@Test func twoSkillBlocksInOneLineGiveTwoEvents() {
    let line = #"{"type":"assistant","timestamp":"2026-08-04T03:16:57Z","cwd":"/p","sessionId":"s","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"a"}},{"type":"tool_use","name":"Skill","input":{"skill":"b"}}]}}"#
    #expect(UsageLogParser.events(inLine: Data(line.utf8), source: .claudeCode, logFile: "/l").map(\.skillName) == ["a", "b"])
}
