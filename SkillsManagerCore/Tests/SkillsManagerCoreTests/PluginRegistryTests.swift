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
