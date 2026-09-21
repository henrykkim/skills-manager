import Foundation
import Testing
@testable import SkillsManagerCore

@Test func pathsDeriveFromInjectedHome() {
    let home = URL(fileURLWithPath: "/fake/home", isDirectory: true)
    let paths = ClaudePaths(home: home)
    #expect(paths.claudeDir.path == "/fake/home/.claude")
    #expect(paths.personalSkillsDir.path == "/fake/home/.claude/skills")
    #expect(paths.settingsFile.path == "/fake/home/.claude/settings.json")
    #expect(paths.pluginsDir.path == "/fake/home/.claude/plugins")
    #expect(paths.installedPluginsFile.path == "/fake/home/.claude/plugins/installed_plugins.json")
    #expect(paths.knownMarketplacesFile.path == "/fake/home/.claude/plugins/known_marketplaces.json")
    #expect(paths.pluginsCacheDir.path == "/fake/home/.claude/plugins/cache")
    #expect(paths.agentsDir.path == "/fake/home/.agents")
    #expect(paths.sharedSkillsDir.path == "/fake/home/.agents/skills")
}

@Test func defaultInitUsesRealHome() {
    let paths = ClaudePaths()
    #expect(paths.home.path.hasPrefix("/"))
    #expect(paths.claudeDir.lastPathComponent == ".claude")
}
