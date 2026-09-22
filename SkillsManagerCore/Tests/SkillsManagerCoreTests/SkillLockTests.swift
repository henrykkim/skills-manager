import Foundation
import Testing
@testable import SkillsManagerCore

private func writeTemp(_ contents: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "skill-lock-\(UUID().uuidString).json")
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}

@Test func parsesObservedLockSchema() throws {
    let file = try writeTemp(#"""
    { "version": 1,
      "skills": {
        "make-interfaces-feel-better": {
          "source": "jakubkrehel/make-interfaces-feel-better",
          "sourceType": "github",
          "sourceUrl": "https://github.com/jakubkrehel/make-interfaces-feel-better.git",
          "skillPath": "skills/make-interfaces-feel-better/SKILL.md",
          "skillFolderHash": "320672d0",
          "installedAt": "2026-05-16T20:41:54.277Z",
          "updatedAt": "2026-06-22T18:32:26.017Z"
        }
      },
      "dismissed": [], "lastSelectedAgents": [] }
    """#)
    defer { try? FileManager.default.removeItem(at: file) }

    let lock = SkillLock.load(file: file)
    let entry = try #require(lock["make-interfaces-feel-better"])
    #expect(entry.sourceLabel == "jakubkrehel/make-interfaces-feel-better")
    #expect(entry.sourceURL == URL(string: "https://github.com/jakubkrehel/make-interfaces-feel-better"))
    #expect(entry.installedAt != nil)
    #expect(entry.updatedAt != nil)
    #expect(entry.updatedAt! > entry.installedAt!)
    #expect(lock["not-there"] == nil)
}

@Test func missingLockFileIsEmpty() {
    let lock = SkillLock.load(file: URL(fileURLWithPath: "/definitely/not/real/.skill-lock.json"))
    #expect(lock["anything"] == nil)
}

@Test func malformedLockFileIsEmpty() throws {
    let file = try writeTemp("{ this is not json")
    defer { try? FileManager.default.removeItem(at: file) }
    #expect(SkillLock.load(file: file)["anything"] == nil)
}

@Test func lockEntryWithoutUrlStillCarriesDates() throws {
    let file = try writeTemp(#"{ "version": 1, "skills": { "local-only": { "installedAt": "2026-01-01T00:00:00Z" } } }"#)
    defer { try? FileManager.default.removeItem(at: file) }
    let entry = try #require(SkillLock.load(file: file)["local-only"])
    #expect(entry.sourceURL == nil)
    #expect(entry.sourceLabel == nil)
    #expect(entry.installedAt != nil)
}

@Test func agentsLockFilePath() {
    let paths = ClaudePaths(home: URL(fileURLWithPath: "/tmp/fakehome"))
    #expect(paths.agentsLockFile.path == "/tmp/fakehome/.agents/.skill-lock.json")
}
