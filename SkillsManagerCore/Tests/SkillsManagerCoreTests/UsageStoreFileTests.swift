import Foundation
import Testing
@testable import SkillsManagerCore

@Test func storeRoundTripsEventsAndCursors() throws {
    let t = try TempTree(); defer { t.remove() }
    let file = t.url("usage-events.json")
    let event = SkillUsageEvent(skillName: "superpowers:brainstorming",
                                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                                projectRoot: URL(fileURLWithPath: "/Users/x/proj", isDirectory: true),
                                sessionID: "s1", source: .claudeCode, logFile: "/logs/a.jsonl")
    let data = UsageStoreData(events: [event],
                              cursors: ["/logs/a.jsonl": UsageFileCursor(byteOffset: 120, fileSize: 120)])
    try UsageStoreFile.save(data, to: file)
    let loaded = UsageStoreFile.load(at: file)
    #expect(loaded == data)
}

@Test func missingStoreIsEmpty() throws {
    let t = try TempTree(); defer { t.remove() }
    #expect(UsageStoreFile.load(at: t.url("nope.json")) == UsageStoreData())
}

@Test func corruptStoreIsDiscarded() throws {
    let t = try TempTree(); defer { t.remove() }
    let file = try t.write("{not json", to: "usage-events.json")
    #expect(UsageStoreFile.load(at: file) == UsageStoreData())
}

@Test func deleteRemovesFile() throws {
    let t = try TempTree(); defer { t.remove() }
    let file = try t.write("{}", to: "usage-events.json")
    UsageStoreFile.delete(at: file)
    #expect(!FileManager.default.fileExists(atPath: file.path))
    UsageStoreFile.delete(at: file)   // second delete is a no-op
}
