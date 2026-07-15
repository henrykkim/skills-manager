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
