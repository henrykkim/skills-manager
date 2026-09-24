import Foundation
import Testing
@testable import SkillsManagerCore

@Test func terminalFoldersAreProjectKeys() throws {
    let t = try TempTree(); defer { t.remove() }
    let file = try t.write(#"{"numStartups": 3, "projects": {"/a": {"allowedTools": []}, "/b": {}}}"#, to: ".claude.json")
    #expect(try ProjectSources.terminalFolders(claudeJSON: file).sorted() == ["/a", "/b"])
    // Missing file is normal.
    #expect(try ProjectSources.terminalFolders(claudeJSON: t.url("nope.json")) == [])
    // Broken file throws so discover() can report it.
    let bad = try t.write("{not json", to: "bad.json")
    #expect(throws: (any Error).self) { try ProjectSources.terminalFolders(claudeJSON: bad) }
}

@Test func codeTabFoldersReadOnlyPathFields() throws {
    let t = try TempTree(); defer { t.remove() }
    // Private fields present with odd types — must not break decoding or be read.
    try t.write(#"{"cwd": "/w1", "originCwd": "/o1", "title": {"x": 1}, "promptAppendSnapshot": [1,2]}"#,
                to: "sessions/acct/org/local_1.json")
    try t.write(#"{"cwd": "/w2"}"#, to: "sessions/acct/org/local_2.json")
    try t.write(#"{"cwd": "/ignored"}"#, to: "sessions/acct/org/other.json")          // wrong name
    try t.write(#"{"cwd": "/too-deep"}"#, to: "sessions/acct/org/sub/local_3.json")   // wrong depth
    let folders = try ProjectSources.codeTabFolders(sessionsDir: t.url("sessions"))
    #expect(Set(folders) == ["/w1", "/o1", "/w2"])
}

@Test func coworkFoldersReadUserSelectedFoldersAndSkipAccountSkills() throws {
    let t = try TempTree(); defer { t.remove() }
    try t.write(#"{"userSelectedFolders": ["/c1", "/c2"], "emailAddress": "a@b.c", "systemPrompt": "secret"}"#,
                to: "cowork/acct/org/local_9.json")
    try t.write(#"{"userSelectedFolders": ["/nope"]}"#, to: "cowork/skills-plugin/acct/local_1.json")
    let folders = try ProjectSources.coworkFolders(sessionsDir: t.url("cowork"))
    #expect(folders == ["/c1", "/c2"])
}

@Test func sessionReadersThrowOnlyWhenEveryFileIsUnreadable() throws {
    let t = try TempTree(); defer { t.remove() }
    try t.write("garbage", to: "s/a/b/local_1.json")
    #expect(throws: (any Error).self) { try ProjectSources.codeTabFolders(sessionsDir: t.url("s")) }
    try t.write(#"{"cwd": "/ok"}"#, to: "s/a/b/local_2.json")
    #expect(try ProjectSources.codeTabFolders(sessionsDir: t.url("s")) == ["/ok"])
    #expect(try ProjectSources.codeTabFolders(sessionsDir: t.url("missing")) == [])
}

@Test func normalizeDropsMissingFoldsWorktreesSkipsHomeAndDedupes() throws {
    let t = try TempTree(); defer { t.remove() }
    let home = try t.mkdir("home")
    let portfolio = try t.mkdir("home/Claude/Portfolio")
    try t.mkdir("home/Claude/Portfolio/.claude/worktrees/feature-x")
    try t.mkdir("home/Work/Portfolio")
    try t.mkdir("home/Ring")

    let projects = ProjectSources.normalize([
        portfolio.path,
        portfolio.path + "/.claude/worktrees/feature-x",   // folds into Portfolio
        t.url("home/Claude/Deleted").path,                 // missing → dropped
        home.path,                                         // home → dropped
        t.url("home/Work/Portfolio").path,                 // same name, different parent
        t.url("home/Ring").path,
        t.url("home/Ring").path,                           // duplicate
    ], home: home)

    #expect(projects.map(\.displayName) == ["Portfolio (Claude)", "Portfolio (Work)", "Ring"])
    #expect(projects[0].root.path == Canonical.path(portfolio.path))
}

@Test func discoverReportsABrokenSourceAndKeepsTheOthers() throws {
    let t = try TempTree(); defer { t.remove() }
    let home = try t.mkdir("home")
    let paths = ClaudePaths(home: home)
    try t.write("{broken", to: "home/.claude.json")
    let cowork = try t.mkdir("home/Cowork Folder")
    try t.write(#"{"userSelectedFolders": ["\#(cowork.path)"]}"#,
                to: "home/Library/Application Support/Claude/local-agent-mode-sessions/a/b/local_1.json")
    let added = try t.mkdir("home/Added")

    let d = ProjectSources.discover(paths: paths, addedProjects: [added])
    #expect(d.projects.map(\.displayName) == ["Added", "Cowork Folder"])
    #expect(d.issues.count == 1)
    #expect(d.issues[0].detail == "Couldn't read Claude Code's project list. Some projects may be missing.")
}
