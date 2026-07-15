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

@Test func mixedTypedEntriesKeepValidOnes() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("settings-reader-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let file = dir.appendingPathComponent("settings.json")
    let json = #"{"enabledPlugins": {"good@m": true, "bad@m": "yes", "off@m": false}}"#
    try Data(json.utf8).write(to: file)

    let map = SettingsReader.enabledPlugins(settingsFile: file)
    #expect(map == ["good@m": true, "off@m": false])
}
