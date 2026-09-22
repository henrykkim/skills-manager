import Foundation
import Testing
@testable import SkillsManagerCore

@Test func loadsRecordsFromV2Registry() throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let paths = ClaudePaths(home: home)

    let records = try PluginRegistry.loadRecords(installedPluginsFile: paths.installedPluginsFile)
    #expect(records.count == 2)
    let demo = try #require(records.first { $0.pluginID == "demo-plugin@test-market" })
    #expect(demo.name == "demo-plugin")
    #expect(demo.marketplace == "test-market")
    #expect(demo.version == "1.2.0")
    #expect(demo.lastUpdated != nil)
}

@Test func loadsPluginsWithSkillsCommandsAndEnabledState() throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let paths = ClaudePaths(home: home)
    let enabled = SettingsReader.enabledPlugins(settingsFile: paths.settingsFile)

    let result = PluginRegistry.loadPlugins(paths: paths, enabledPlugins: enabled)
    #expect(result.plugins.count == 2)

    let demo = try #require(result.plugins.first { $0.pluginID == "demo-plugin@test-market" })
    #expect(demo.isEnabled == true)
    #expect(demo.summary == "Demo plugin for tests")            // from .claude-plugin/plugin.json
    #expect(demo.provenance == "GitHub: test-org/test-market")  // from known_marketplaces.json
    #expect(demo.skills.count == 1)
    #expect(demo.skills[0].folderName == "bundled-skill")
    #expect(demo.skills[0].modelInvocable == false) // disable-model-invocation: true
    #expect(demo.skills[0].source == .plugin(pluginID: "demo-plugin@test-market"))
    #expect(demo.commands.count == 1)
    #expect(demo.commands[0].name == "do-thing")
    #expect(demo.commands[0].invocation == "/demo-plugin:do-thing")
    #expect(demo.commands[0].summary?.contains("demo thing") == true)
    #expect(demo.commands[0].argumentHint == "<target>")

    let disabled = try #require(result.plugins.first { $0.pluginID == "disabled-plugin@test-market" })
    #expect(disabled.isEnabled == false)
    #expect(disabled.skills.count == 1)
}

@Test func cacheDirectoryWinsOverDeadInstallPath() throws {
    // Fixture installPath is /nonexistent/... — content must load from plugins/cache/.
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let paths = ClaudePaths(home: home)
    let result = PluginRegistry.loadPlugins(paths: paths, enabledPlugins: [:])
    let demo = try #require(result.plugins.first { $0.pluginID == "demo-plugin@test-market" })
    #expect(demo.contentDirectory.path.contains("plugins/cache/test-market/demo-plugin/1.2.0"))
}

@Test func missingRegistryFileYieldsEmptyResult() {
    let paths = ClaudePaths(home: URL(fileURLWithPath: "/definitely/not/real"))
    let result = PluginRegistry.loadPlugins(paths: paths, enabledPlugins: [:])
    #expect(result.plugins.isEmpty)
    #expect(result.issues.isEmpty)
}

@Test func pluginReadsAuthorAndLinksFromManifestAndMarketplace() throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let result = PluginRegistry.loadPlugins(paths: ClaudePaths(home: home), enabledPlugins: [:])

    let demo = try #require(result.plugins.first { $0.pluginID == "demo-plugin@test-market" })
    #expect(demo.authorName == "Test Author")
    #expect(demo.authorURL == URL(string: "https://example.com/author"))
    #expect(demo.homepageURL == URL(string: "https://example.com/demo"))          // homepage wins over repository
    #expect(demo.marketplaceURL == URL(string: "https://github.com/test-org/test-market"))
    #expect(demo.installedAt != nil)
    #expect(demo.lastUpdated! > demo.installedAt!)

    let disabled = try #require(result.plugins.first { $0.pluginID == "disabled-plugin@test-market" })
    #expect(disabled.authorName == nil)
    #expect(disabled.authorURL == nil)
    #expect(disabled.homepageURL == nil)
    #expect(disabled.marketplaceURL == URL(string: "https://github.com/test-org/test-market"))
}

@Test func repositoryIsUsedWhenHomepageMissing() throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    // Overwrite the disabled plugin's manifest with repository only.
    let manifest = home.appending(
        path: ".claude/plugins/cache/test-market/disabled-plugin/0.1.0/.claude-plugin/plugin.json")
    try #"{ "name": "disabled-plugin", "repository": "https://github.com/test-org/disabled.git" }"#
        .write(to: manifest, atomically: true, encoding: .utf8)

    let result = PluginRegistry.loadPlugins(paths: ClaudePaths(home: home), enabledPlugins: [:])
    let disabled = try #require(result.plugins.first { $0.pluginID == "disabled-plugin@test-market" })
    #expect(disabled.homepageURL == URL(string: "https://github.com/test-org/disabled"))
}

@Test func marketplaceUrlDerivesFromGitUrlForm() throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let paths = ClaudePaths(home: home)
    try #"{ "test-market": { "source": { "source": "git", "url": "https://github.com/test-org/test-market.git" } } }"#
        .write(to: paths.knownMarketplacesFile, atomically: true, encoding: .utf8)

    let result = PluginRegistry.loadPlugins(paths: paths, enabledPlugins: [:])
    let demo = try #require(result.plugins.first { $0.pluginID == "demo-plugin@test-market" })
    #expect(demo.marketplaceURL == URL(string: "https://github.com/test-org/test-market"))
    #expect(demo.provenance == "Git: https://github.com/test-org/test-market.git") // sidebar text unchanged
}
