import Foundation
import Testing

@Test func fixtureHomeMaterializesDotfoldersManifestsAndSymlinks() throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let fm = FileManager.default
    #expect(fm.fileExists(atPath: home.appending(path: ".claude/skills/good-skill/SKILL.md").path))
    #expect(fm.fileExists(atPath: home.appending(path: ".claude/plugins/installed_plugins.json").path))
    #expect(fm.fileExists(atPath: home.appending(path: ".claude/plugins/known_marketplaces.json").path))
    #expect(fm.fileExists(atPath: home.appending(path: ".agents/skills/shared-skill/SKILL.md").path))
    #expect(fm.fileExists(atPath: home.appending(path: ".agents/skills/shared-only-skill/SKILL.md").path))
    // Written by the helper (hidden files don't survive SPM resource bundling):
    #expect(fm.fileExists(atPath: home.appending(
        path: ".claude/plugins/cache/test-market/demo-plugin/1.2.0/.claude-plugin/plugin.json").path))
    #expect(fm.fileExists(atPath: home.appending(
        path: ".claude/plugins/cache/test-market/disabled-plugin/0.1.0/.claude-plugin/plugin.json").path))
    // The same personal→shared symlink real installers (npx skills) create:
    let link = home.appending(path: ".claude/skills/shared-skill")
    let destination = try fm.destinationOfSymbolicLink(atPath: link.path)
    #expect(destination.hasSuffix(".agents/skills/shared-skill"))
}
