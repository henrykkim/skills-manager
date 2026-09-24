import Foundation
import Testing
@testable import SkillsManagerCore

@Test func coworkPluginsLoadFromEachAccountStore() throws {
    let t = try TempTree(); defer { t.remove() }
    let store = "cowork/acct/org/cowork_plugins"
    try t.write(#"""
    {"version": 2, "plugins": {"helper@kw": [{"scope": "user", "version": "0.2.2"}]}}
    """#, to: "\(store)/installed_plugins.json")
    try t.write(#"{"name": "helper", "description": "Cowork helper"}"#,
                to: "\(store)/cache/kw/helper/0.2.2/.claude-plugin/plugin.json")
    try t.skill("assist", in: "\(store)/cache/kw/helper/0.2.2/skills")
    try t.write(#"{"enabledPlugins": {"helper@kw": false}}"#, to: "cowork/acct/org/cowork_settings.json")

    let r = CoworkPlugins.load(sessionsDir: t.url("cowork"))
    #expect(r.issues.isEmpty)
    let p = try #require(r.plugins.first)
    #expect(p.pluginID == "helper@kw")
    #expect(p.scope == .cowork)
    #expect(p.isEnabled == false)
    #expect(p.skills.map(\.folderName) == ["assist"])
}

@Test func accountSkillsSplitByCreatorAndKeepDisabled() throws {
    let t = try TempTree(); defer { t.remove() }
    let base = "acct/one/two"
    try t.write(#"""
    {"lastUpdated": 1790273572879, "skills": [
      {"skillId": "skill_1", "name": "my-voice", "creatorType": "user", "enabled": true},
      {"skillId": "skill_2", "name": "my-old", "creatorType": "user", "enabled": false},
      {"skillId": "pdf", "name": "pdf", "creatorType": "anthropic", "enabled": true},
      {"skillId": "gone", "name": "gone", "creatorType": "user", "enabled": true}
    ]}
    """#, to: "\(base)/manifest.json")
    for n in ["my-voice", "my-old", "pdf"] { try t.skill(n, in: "\(base)/skills") }

    let r = AccountSkills.load(dir: t.url("acct"))
    let byName = Dictionary(uniqueKeysWithValues: r.skills.map { ($0.folderName, $0) })
    #expect(byName["my-voice"]?.source == .account(userMade: true))
    #expect(byName["my-old"]?.isEnabled == false)
    #expect(byName["pdf"]?.source == .account(userMade: false))
    #expect(byName["gone"] == nil)                       // listed but no files: skipped quietly
    #expect(abs((r.lastSynced?.timeIntervalSince1970 ?? 0) - 1790273572.879) < 0.001)
    #expect(r.issues.isEmpty)
}

@Test func brokenAccountManifestIsOneIssue() throws {
    let t = try TempTree(); defer { t.remove() }
    try t.write("{nope", to: "acct/a/b/manifest.json")
    let r = AccountSkills.load(dir: t.url("acct"))
    #expect(r.skills.isEmpty)
    #expect(r.issues.map(\.detail) == ["Couldn't read your Claude account's skill list. Claude account skills may be missing."])
    #expect(AccountSkills.load(dir: t.url("missing")).issues.isEmpty)
}
