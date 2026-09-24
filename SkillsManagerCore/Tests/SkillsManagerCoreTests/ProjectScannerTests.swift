import Foundation
import Testing
@testable import SkillsManagerCore

@Test func findsTopLevelAndNestedSkillFoldersWithinDepth() throws {
    let t = try TempTree(); defer { t.remove() }
    let root = try t.mkdir("proj")
    try t.skill("top", in: "proj/.claude/skills")
    try t.skill("web", in: "proj/apps/web/.claude/skills")
    try t.skill("deep", in: "proj/a/b/c/d/.claude/skills")         // depth 4: found
    try t.skill("toodeep", in: "proj/a/b/c/d/e/.claude/skills")    // depth 5: skipped
    try t.skill("dep", in: "proj/node_modules/pkg/.claude/skills") // skipped folder
    try t.skill("wt", in: "proj/.claude/worktrees/x/.claude/skills") // hidden → skipped

    let dirs = try ProjectScanner.skillDirectories(in: root)
    let subpaths = dirs.map { $0.subpath ?? "<root>" }.sorted()
    #expect(subpaths == ["<root>", "a/b/c/d", "apps/web"])
}

@Test func scanTagsSkillsWithProjectAndSubpath() throws {
    let t = try TempTree(); defer { t.remove() }
    let root = try t.mkdir("proj")
    try t.skill("top", in: "proj/.claude/skills")
    try t.skill("web", in: "proj/apps/web/.claude/skills")
    let project = Project(root: root, displayName: "proj")

    let r = ProjectScanner.scan(project, paths: ClaudePaths(home: t.url("home")))
    let top = try #require(r.skills.first { $0.folderName == "top" })
    #expect(top.source == .project(root: root, subpath: nil))
    let web = try #require(r.skills.first { $0.folderName == "web" })
    #expect(web.source == .project(root: root, subpath: "apps/web"))
    #expect(r.issues.isEmpty)
}

@Test func scanLoadsProjectAndLocalPlugins() throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let t = try TempTree(); defer { t.remove() }
    let root = try t.mkdir("proj")
    try t.write(#"{"enabledPlugins": {"demo-plugin@test-market": true, "off@x": false}}"#,
                to: "proj/.claude/settings.json")
    try t.write(#"{"enabledPlugins": {"disabled-plugin@test-market": true}}"#,
                to: "proj/.claude/settings.local.json")

    let r = ProjectScanner.scan(Project(root: root, displayName: "proj"), paths: ClaudePaths(home: home))
    #expect(r.plugins.map(\.pluginID).sorted() == ["demo-plugin@test-market", "disabled-plugin@test-market"])
    #expect(r.plugins.allSatisfy { $0.scope == .project(root: root) })
}

@Test func unreadableProjectBecomesOneIssue() throws {
    let t = try TempTree(); defer { t.remove() }
    let root = try t.mkdir("locked")
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }

    let r = ProjectScanner.scan(Project(root: root, displayName: "locked"), paths: ClaudePaths(home: t.url("h")))
    #expect(r.issues.count == 1)
    #expect(r.issues[0].detail.contains("System Settings"))
}
