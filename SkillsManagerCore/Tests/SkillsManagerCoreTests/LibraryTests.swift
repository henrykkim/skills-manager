import Foundation
import Testing
@testable import SkillsManagerCore

private func skill(_ folder: String, _ source: SkillSource, dir: URL) -> Skill {
    Skill(folderName: folder, displayName: folder, summary: nil, argumentHint: nil,
          userInvocable: true, modelInvocable: true, whenToUse: nil,
          source: source, directory: dir, lastModified: nil)
}

private func plugin(_ id: String, _ scope: PluginScope) -> Plugin {
    Plugin(pluginID: id, name: String(id.split(separator: "@")[0]), marketplace: "m", summary: nil,
           provenance: nil, version: "1", contentDirectory: URL(fileURLWithPath: "/tmp/\(id)"),
           lastUpdated: nil, isEnabled: true, skills: [], commands: [], scope: scope)
}

@Test func mergesSameFolderNameAcrossGlobalAndProjects() throws {
    let t = try TempTree(); defer { t.remove() }
    let portfolio = try t.mkdir("Portfolio"), ring = try t.mkdir("Ring")
    let g = try t.skill("review", in: "home/.claude/skills", body: "same")
    let p1 = try t.skill("review", in: "Portfolio/.claude/skills", body: "same")
    let p2 = try t.skill("review", in: "Ring/.claude/skills", body: "different")
    let projects = [Project(root: portfolio, displayName: "Portfolio"), Project(root: ring, displayName: "Ring")]

    let lib = Library.build(
        personal: [skill("review", .personal, dir: g)],
        project: [skill("review", .project(root: ring, subpath: nil), dir: p2),
                  skill("review", .project(root: portfolio, subpath: nil), dir: p1)],
        account: [], plugins: [], projects: projects)

    #expect(lib.skills.count == 1)
    let e = lib.skills[0]
    #expect(e.skill.source == .personal)                       // Global copy wins
    #expect(e.tags == [.global, .project(name: "Portfolio"), .project(name: "Ring")])
    #expect(e.copiesDiffer)
    let ringLoc = try #require(e.locations.first { $0.tag == .project(name: "Ring") })
    #expect(ringLoc.isIgnored && ringLoc.differsFromPrimary)
    let pfLoc = try #require(e.locations.first { $0.tag == .project(name: "Portfolio") })
    #expect(pfLoc.isIgnored && !pfLoc.differsFromPrimary)
}

@Test func projectOnlySkillIsNotIgnored() throws {
    let t = try TempTree(); defer { t.remove() }
    let root = try t.mkdir("P")
    let d = try t.skill("solo", in: "P/.claude/skills")
    let lib = Library.build(personal: [], project: [skill("solo", .project(root: root, subpath: nil), dir: d)],
                            account: [], plugins: [], projects: [Project(root: root, displayName: "P")])
    #expect(lib.skills[0].locations[0].isIgnored == false)
    #expect(lib.skills[0].copiesDiffer == false)
}

@Test func accountSkillsStaySeparateAndBuiltInsGoAside() {
    let d = URL(fileURLWithPath: "/tmp/x")
    let lib = Library.build(
        personal: [skill("pdf", .personal, dir: d)], project: [],
        account: [skill("pdf", .account(userMade: false), dir: d), skill("voice", .account(userMade: true), dir: d)],
        plugins: [], projects: [])
    #expect(lib.skills.map(\.id) == ["skill:pdf", "account:voice"])   // sorted by name
    #expect(lib.builtIn.map(\.id) == ["account:pdf"])
    #expect(lib.skills.first { $0.id == "account:voice" }?.tags == [.account])
}

@Test func pluginsMergeByIDWithScopeTags() {
    let root = URL(fileURLWithPath: "/w/Ring", isDirectory: true)
    let lib = Library.build(personal: [], project: [], account: [],
        plugins: [plugin("figma@m", .project(root: root)), plugin("figma@m", .user), plugin("helper@kw", .cowork)],
        projects: [Project(root: root, displayName: "Ring")])
    let figma = lib.plugins.first { $0.id == "figma@m" }
    #expect(figma?.tags == [.global, .project(name: "Ring")])
    #expect(figma?.plugin.scope == .user)
    #expect(lib.plugins.first { $0.id == "helper@kw" }?.tags == [.cowork])
}

@Test func tagOverflowKeepsNonProjectTagsAndTwoProjects() {
    let tags: [LocationTag] = [.global, .project(name: "A"), .project(name: "B"), .project(name: "C"), .project(name: "D")]
    let s = TagLayout.split(tags)
    #expect(s.shown == [.global, .project(name: "A"), .project(name: "B")])
    #expect(s.overflow == [.project(name: "C"), .project(name: "D")])
    #expect(TagLayout.split([.project(name: "A")]).overflow.isEmpty)
}

@Test func whereItWorksLinesExplainPrecedenceAndNesting() throws {
    let t = try TempTree(); defer { t.remove() }
    let home = try t.mkdir("home"), pf = try t.mkdir("Portfolio")
    let g = try t.skill("review", in: "home/.claude/skills")
    let p = try t.skill("review", in: "Portfolio/.claude/skills")
    let n = try t.skill("review", in: "Portfolio/website/.claude/skills")
    let lib = Library.build(
        personal: [skill("review", .personal, dir: g)],
        project: [skill("review", .project(root: pf, subpath: nil), dir: p),
                  skill("review", .project(root: pf, subpath: "website"), dir: n)],
        account: [], plugins: [], projects: [Project(root: pf, displayName: "Portfolio")])

    let lines = WhereItWorks.lines(for: lib.skills[0], lastSynced: nil, home: home)
    #expect(lines.map(\.label) == ["Global", "Portfolio", "Portfolio › website"])
    #expect(lines[0].detail == "~/.claude/skills/review")
    #expect(lines[1].detail == "Ignored — Claude uses the Global copy")
    #expect(lines[2].detail == "Ignored — Claude uses the Global copy")
}
