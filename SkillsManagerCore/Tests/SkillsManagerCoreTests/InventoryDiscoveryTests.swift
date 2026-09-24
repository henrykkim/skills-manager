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
    #expect(inv.projectWatchTargets.count == 2)
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
