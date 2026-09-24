import Foundation
import Testing
@testable import SkillsManagerCore

@Test func canonicalResolvesPrivatePrefix() {
    // /tmp is a symlink to /private/tmp on macOS.
    #expect(Canonical.path("/tmp") == "/private/tmp")
    // Nonexistent tail canonicalizes its existing ancestor.
    #expect(Canonical.path("/tmp/does-not-exist-xyz") == "/private/tmp/does-not-exist-xyz")
}

@Test func newPathsHangOffHome() {
    let paths = ClaudePaths(home: URL(fileURLWithPath: "/Users/test", isDirectory: true))
    #expect(paths.claudeJSON.path == "/Users/test/.claude.json")
    #expect(paths.codeSessionsDir.path == "/Users/test/Library/Application Support/Claude/claude-code-sessions")
    #expect(paths.coworkSessionsDir.path == "/Users/test/Library/Application Support/Claude/local-agent-mode-sessions")
    #expect(paths.accountSkillsDir.path == "/Users/test/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin")
    #expect(paths.userPluginStore.installedPluginsFile == paths.installedPluginsFile)
    #expect(paths.userPluginStore.cacheDir == paths.pluginsCacheDir)
}

@Test func scanOneReturnsSkillIssueOrNotASkill() throws {
    let t = try TempTree(); defer { t.remove() }
    let good = try t.skill("alpha", in: "skills")
    try t.write("no frontmatter", to: "skills/broken/SKILL.md")
    try t.mkdir("skills/empty")

    guard case .skill(let s) = SkillScanner.scanOne(folder: good, source: .account(userMade: true), isEnabled: false)
    else { Issue.record("expected skill"); return }
    #expect(s.folderName == "alpha")
    #expect(s.isEnabled == false)
    #expect(s.source == .account(userMade: true))

    guard case .issue = SkillScanner.scanOne(folder: t.url("skills/broken"), source: .personal) else {
        Issue.record("expected issue"); return
    }
    // A folder without SKILL.md is reported by scan() as an issue; scanOne says notASkill
    // so callers decide.
    guard case .notASkill = SkillScanner.scanOne(folder: t.url("skills/empty"), source: .personal) else {
        Issue.record("expected notASkill"); return
    }
}

@Test func loadPluginsFromStoreWithScopeAndOnlyFilter() throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let paths = ClaudePaths(home: home)
    let root = URL(fileURLWithPath: "/proj", isDirectory: true)

    let result = PluginRegistry.loadPlugins(
        store: paths.userPluginStore,
        enabledPlugins: ["demo-plugin@test-market": true, "ghost@nowhere": true],
        scope: .project(root: root),
        only: ["demo-plugin@test-market", "ghost@nowhere"])

    #expect(result.plugins.map(\.pluginID) == ["demo-plugin@test-market"])
    #expect(result.plugins[0].scope == .project(root: root))
    // Turned on for the project but not installed: reported, never silently dropped.
    #expect(result.issues.contains { $0.detail.contains("ghost@nowhere") })
}

@Test func invocationForNewSources() {
    func make(_ source: SkillSource) -> Skill {
        Skill(folderName: "thing", displayName: "thing", summary: nil, argumentHint: nil,
              userInvocable: true, modelInvocable: true, whenToUse: nil,
              source: source, directory: URL(fileURLWithPath: "/tmp/thing"), lastModified: nil)
    }
    #expect(Invocation.string(for: make(.project(root: URL(fileURLWithPath: "/p"), subpath: nil))) == "/thing")
    #expect(Invocation.string(for: make(.account(userMade: true))) == "/anthropic-skills:thing")
}

@Test func disabledAccountSkillSaysWhereToTurnItOn() {
    let s = Skill(folderName: "x", displayName: "x", summary: nil, argumentHint: nil,
                  userInvocable: true, modelInvocable: true, whenToUse: nil,
                  source: .account(userMade: true), directory: URL(fileURLWithPath: "/tmp/x"),
                  lastModified: nil, isEnabled: false)
    #expect(Invocation.availabilityLabel(for: s).contains("Claude → Settings → Skills"))
}
