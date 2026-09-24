import Foundation
import Testing
@testable import SkillsManagerCore

/// A home with a terminal project, a Cowork folder, a Claude-account manifest,
/// and an added note folder.
private func makeHome() throws -> (TempTree, ClaudePaths) {
    let t = try TempTree()
    let home = try t.mkdir("home")
    let proj = try t.mkdir("home/Code/Portfolio")
    try t.skill("brand-voice", in: "home/Code/Portfolio/.claude/skills")
    try t.skill("shared-name", in: "home/Code/Portfolio/.claude/skills")
    try t.skill("shared-name", in: "home/.claude/skills")
    try t.write(#"{"projects": {"\#(proj.path)": {}}}"#, to: "home/.claude.json")
    let cw = try t.mkdir("home/Docs/CoworkThing")
    try t.skill("cw-skill", in: "home/Docs/CoworkThing/.claude/skills")
    let support = "home/Library/Application Support/Claude"
    try t.write(#"{"userSelectedFolders": ["\#(cw.path)"], "emailAddress": "a@b.c"}"#,
                to: "\(support)/local-agent-mode-sessions/a/b/local_1.json")
    try t.write(#"{"lastUpdated": 1000, "skills": [{"name": "voice", "creatorType": "user", "enabled": true}]}"#,
                to: "\(support)/local-agent-mode-sessions/skills-plugin/a/b/manifest.json")
    try t.skill("voice", in: "\(support)/local-agent-mode-sessions/skills-plugin/a/b/skills")
    try t.write("# Brief", to: "home/brain/skills/morning-brief.md")
    return (t, ClaudePaths(home: home))
}

@Test func loadsEverySourceIntoTheLibrary() throws {
    let (t, paths) = try makeHome(); defer { t.remove() }
    let inv = Inventory.load(paths: paths, addedFolders: [t.url("home/brain/skills")])

    #expect(inv.projects.map(\.displayName) == ["CoworkThing", "Portfolio"])
    #expect(Set(inv.projectSkills.map(\.folderName)) == ["brand-voice", "shared-name", "cw-skill"])
    #expect(inv.accountSkills.map(\.folderName) == ["voice"])
    #expect(inv.notes.map(\.name) == ["skills"])
    #expect(inv.issues.isEmpty)

    let tagsByID = Dictionary(uniqueKeysWithValues: inv.library.skills.map { ($0.id, $0.tags) })
    #expect(tagsByID["skill:brand-voice"] == [.project(name: "Portfolio")])
    #expect(tagsByID["skill:shared-name"] == [.global, .project(name: "Portfolio")])
    #expect(tagsByID["account:voice"] == [.account])
    // Skills folder + both settings files per project — not the whole .claude
    // folder, whose worktrees/ churn on every build.
    #expect(inv.projectWatchTargets.count == 6)
    #expect(Set(inv.projectWatchTargets.map(\.lastPathComponent)) == ["skills", "settings.json", "settings.local.json"])
}

@Test func addedProjectFolderJoinsProjects() throws {
    let (t, paths) = try makeHome(); defer { t.remove() }
    try t.skill("extra", in: "elsewhere/NeverOpened/.claude/skills")
    let inv = Inventory.load(paths: paths, addedFolders: [t.url("elsewhere/NeverOpened")])
    #expect(inv.projects.contains { $0.displayName == "NeverOpened" })
    #expect(inv.library.skills.contains { $0.id == "skill:extra" })
}

@Test func addedFolderThatNoLongerFitsIsReported() throws {
    let (t, paths) = try makeHome(); defer { t.remove() }
    try t.mkdir("home/emptied")
    let inv = Inventory.load(paths: paths, addedFolders: [t.url("home/emptied")])
    #expect(inv.issues.map(\.detail) == ["This added folder no longer has Claude skills or markdown files."])
}

@Test func oneBrokenSourceLeavesTheRestLoaded() throws {
    let (t, paths) = try makeHome(); defer { t.remove() }
    try t.write("{broken", to: "home/.claude.json")
    let inv = Inventory.load(paths: paths)
    #expect(inv.projects.map(\.displayName) == ["CoworkThing"])        // Cowork still found
    #expect(inv.accountSkills.count == 1)
    #expect(inv.issues.count == 1)
}

@Test func projectsCanBeSkippedUntilTheUserAgrees() throws {
    let (t, paths) = try makeHome(); defer { t.remove() }
    let inv = Inventory.load(paths: paths, includeProjects: false)
    #expect(inv.projects.isEmpty && inv.projectSkills.isEmpty)
    #expect(inv.accountSkills.count == 1)    // account skills live in the app's own folder: no prompt
}

@Test func addedProjectFolderStillLoadsWhileProjectsAreSkipped() throws {
    let (t, paths) = try makeHome(); defer { t.remove() }
    try t.skill("extra", in: "elsewhere/NeverOpened/.claude/skills")
    let inv = Inventory.load(
        paths: paths,
        addedFolders: [t.url("elsewhere/NeverOpened"), t.url("home/brain/skills")],
        includeProjects: false)

    // The added folder was already granted access, so it loads regardless of the flag.
    #expect(inv.projects.map(\.displayName) == ["NeverOpened"])
    #expect(inv.projectSkills.map(\.folderName) == ["extra"])
    #expect(inv.notes.map(\.name) == ["skills"])
    // Terminal/Cowork projects (which would need a fresh prompt) do not appear.
    #expect(!inv.projects.contains { $0.displayName == "Portfolio" || $0.displayName == "CoworkThing" })
    #expect(inv.issues.isEmpty)
}

@Test func projectInsideAnotherProjectIsScannedOnce() throws {
    let t = try TempTree(); defer { t.remove() }
    let home = try t.mkdir("home")
    let outer = try t.mkdir("home/Claude")
    let inner = try t.mkdir("home/Claude/Portfolio")
    try t.skill("pf", in: "home/Claude/Portfolio/.claude/skills")
    try t.write(#"{"projects": {"\#(outer.path)": {}, "\#(inner.path)": {}}}"#, to: "home/.claude.json")

    let inv = Inventory.load(paths: ClaudePaths(home: home))
    #expect(inv.projects.map(\.displayName) == ["Claude", "Portfolio"])
    let entry = try #require(inv.library.skills.first { $0.id == "skill:pf" })
    #expect(entry.locations.count == 1)
    #expect(entry.tags == [.project(name: "Portfolio")])
    guard case .project(let root, let subpath) = entry.skill.source else {
        Issue.record("expected a project skill"); return
    }
    #expect(root.path == inner.path && subpath == nil)
    #expect(entry.locations[0].isIgnored == false)
}
