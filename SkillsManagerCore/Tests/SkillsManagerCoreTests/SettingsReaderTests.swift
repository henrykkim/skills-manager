import Foundation
import Testing
@testable import SkillsManagerCore

@Test func readsEnabledPluginsMap() throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let paths = ClaudePaths(home: home)

    let map = SettingsReader.enabledPlugins(settingsFile: paths.settingsFile)
    #expect(map["demo-plugin@test-market"] == true)
    #expect(map["disabled-plugin@test-market"] == false)
    #expect(map.count == 2)
}

@Test func missingSettingsFileYieldsEmptyMap() {
    let map = SettingsReader.enabledPlugins(
        settingsFile: URL(fileURLWithPath: "/definitely/not/real.json"))
    #expect(map.isEmpty)
}
