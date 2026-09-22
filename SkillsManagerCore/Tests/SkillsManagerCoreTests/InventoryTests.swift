import Foundation
import Testing
@testable import SkillsManagerCore

@Test func loadsFullInventoryFromFixtureHome() throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let paths = ClaudePaths(home: home)

    let inventory = Inventory.load(paths: paths)

    #expect(inventory.personalSkills.count == 4) // includes the symlinked shared-skill
    #expect(inventory.sharedSkills.count == 1)   // only the unconnected one remains
    #expect(inventory.sharedSkills[0].folderName == "shared-only-skill")
    #expect(inventory.plugins.count == 2)
    #expect(inventory.issues.count == 2) // broken-skill + empty-folder
    #expect(inventory.plugins.first { $0.pluginID == "disabled-plugin@test-market" }?.isEnabled == false)
}

@Test func connectedSharedSkillsAreNotListedTwice() throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let inventory = Inventory.load(paths: ClaudePaths(home: home))
    // shared-skill is symlinked into ~/.claude/skills: one entry, listed as personal
    // (where Claude Code sees it) — never a confusing duplicate (spec §6.5).
    #expect(inventory.personalSkills.contains { $0.folderName == "shared-skill" })
    #expect(!inventory.sharedSkills.contains { $0.folderName == "shared-skill" })
}

@Test func emptyHomeLoadsEmptyInventory() {
    let paths = ClaudePaths(home: URL(fileURLWithPath: "/definitely/not/real"))
    let inventory = Inventory.load(paths: paths)
    #expect(inventory.personalSkills.isEmpty)
    #expect(inventory.sharedSkills.isEmpty)
    #expect(inventory.plugins.isEmpty)
    #expect(inventory.issues.isEmpty)
}

@Test func sharedSkillCarriesLockProvenance() throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let inventory = Inventory.load(paths: ClaudePaths(home: home))

    // shared-skill is symlinked into ~/.claude/skills, so it is listed as personal —
    // and must still pick up its lock record by folder name.
    let connected = try #require(inventory.personalSkills.first { $0.folderName == "shared-skill" })
    #expect(connected.sourceLabel == "test-org/shared-skill")
    #expect(connected.sourceURL == URL(string: "https://github.com/test-org/shared-skill"))
    #expect(connected.installedAt != nil)
    #expect(connected.updatedAt != nil)

    // shared-only-skill has no lock record: fields stay nil, skill still listed.
    let unrecorded = try #require(inventory.sharedSkills.first { $0.folderName == "shared-only-skill" })
    #expect(unrecorded.sourceURL == nil)
    #expect(unrecorded.updatedAt == nil)
}

@Test func personalSkillWithCollidingNameDoesNotBorrowLockProvenance() throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    // A user-authored personal skill whose folder name matches a lock entry.
    let dir = home.appending(path: ".claude/skills/shared-only-skill")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try "---\nname: mine\ndescription: Written by hand\n---\n"
        .write(to: dir.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
    let lockFile = home.appending(path: ".agents/.skill-lock.json")
    try #"{ "version": 1, "skills": { "shared-only-skill": { "source": "someone/else", "sourceUrl": "https://github.com/someone/else.git", "installedAt": "2026-01-01T00:00:00Z" } } }"#
        .write(to: lockFile, atomically: true, encoding: .utf8)

    let inventory = Inventory.load(paths: ClaudePaths(home: home))
    let mine = try #require(inventory.personalSkills.first { $0.folderName == "shared-only-skill" })
    #expect(mine.sourceURL == nil)
    #expect(mine.installedAt == nil)
    // The real shared copy still gets its provenance.
    let shared = try #require(inventory.sharedSkills.first { $0.folderName == "shared-only-skill" })
    #expect(shared.sourceURL == URL(string: "https://github.com/someone/else"))
}

@Test func plainPersonalSkillHasNoLockProvenance() throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let inventory = Inventory.load(paths: ClaudePaths(home: home))
    let good = try #require(inventory.personalSkills.first { $0.folderName == "good-skill" })
    #expect(good.sourceURL == nil)
    #expect(good.sourceLabel == nil)
    #expect(good.installedAt == nil)
}
