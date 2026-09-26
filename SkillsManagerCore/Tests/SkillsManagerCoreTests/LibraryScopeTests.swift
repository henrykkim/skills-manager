import Foundation
import Testing
@testable import SkillsManagerCore

private func skill(_ folder: String, _ source: SkillSource) -> Skill {
    Skill(folderName: folder, displayName: folder, summary: nil, argumentHint: nil,
          userInvocable: true, modelInvocable: true, whenToUse: nil,
          source: source, directory: URL(fileURLWithPath: "/s/\(folder)/\(UUID().uuidString)"), lastModified: nil)
}
private func entry(_ copies: [Skill]) -> SkillEntry {
    SkillEntry(id: "skill:\(copies[0].folderName)", skill: copies[0],
               locations: copies.map { SkillLocation(skill: $0, tag: .global, isIgnored: false, differsFromPrimary: false) },
               copiesDiffer: false)
}
private func plugin(_ id: String, _ scope: PluginScope) -> Plugin {
    Plugin(pluginID: id, name: String(id.split(separator: "@")[0]), marketplace: "m", summary: nil,
           provenance: nil, version: "1", contentDirectory: URL(fileURLWithPath: "/tmp/\(id)"),
           lastUpdated: nil, isEnabled: true, skills: [], commands: [], scope: scope)
}
private func pentry(_ copies: [Plugin]) -> PluginEntry {
    PluginEntry(id: copies[0].pluginID, plugin: copies[0],
                locations: copies.map { PluginLocation(plugin: $0, tag: .global) })
}
private let a = URL(fileURLWithPath: "/Users/x/A", isDirectory: true)
private let b = URL(fileURLWithPath: "/Users/y/A", isDirectory: true)   // same folder name, different root
private let projects = [Project(root: a, displayName: "A"), Project(root: b, displayName: "A")]

@Test func projectScopeKeepsGlobalAccountAndOwnProjectOnly() {
    let scope = LibraryScope.project(root: a)
    #expect(scope.contains(entry([skill("g", .personal)])))
    #expect(scope.contains(entry([skill("acct", .account(userMade: true))])))
    #expect(scope.contains(entry([skill("pa", .project(root: a, subpath: nil))])))
    #expect(!scope.contains(entry([skill("pb", .project(root: b, subpath: nil))])))   // same name, other root
    #expect(scope.contains(entry([skill("ps", .plugin(pluginID: "p@m"))])))
    #expect(scope.contains(pentry([plugin("u@m", .user)])))
    #expect(scope.contains(pentry([plugin("pa@m", .project(root: a))])))
    #expect(!scope.contains(pentry([plugin("pb@m", .project(root: b))])))
    #expect(!scope.contains(pentry([plugin("cw@m", .cowork)])))
    #expect(!scope.containsSharedSkill())
}

@Test func coworkScopeKeepsCoworkPluginsAndAccountSkills() {
    let scope = LibraryScope.cowork
    #expect(scope.contains(pentry([plugin("cw@m", .cowork)])))
    #expect(!scope.contains(pentry([plugin("u@m", .user)])))
    #expect(scope.contains(entry([skill("acct", .account(userMade: false))])))
    #expect(!scope.contains(entry([skill("g", .personal)])))
    #expect(!scope.containsSharedSkill())
}

@Test func everywhereContainsAll() {
    #expect(LibraryScope.everywhere.contains(entry([skill("pb", .project(root: b, subpath: nil))])))
    #expect(LibraryScope.everywhere.contains(pentry([plugin("cw@m", .cowork)])))
    #expect(LibraryScope.everywhere.containsSharedSkill())
}

@Test func eventFilterFollowsScope() {
    let ea = SkillUsageEvent(skillName: "x", timestamp: Date(), projectRoot: a, sessionID: "1", source: .claudeCode, logFile: "/l")
    let eb = SkillUsageEvent(skillName: "x", timestamp: Date(), projectRoot: b, sessionID: "2", source: .claudeCode, logFile: "/l")
    let ec = SkillUsageEvent(skillName: "x", timestamp: Date(), projectRoot: nil, sessionID: "3", source: .cowork, logFile: "/l")
    #expect(LibraryScope.project(root: a).includes(ea) && !LibraryScope.project(root: a).includes(eb) && !LibraryScope.project(root: a).includes(ec))
    #expect(LibraryScope.cowork.includes(ec) && !LibraryScope.cowork.includes(ea))
    #expect([ea, eb, ec].allSatisfy { LibraryScope.everywhere.includes($0) })
}

@Test func labelsAndPersistence() {
    #expect(LibraryScope.everywhere.label(projects: projects) == "Everywhere")
    #expect(LibraryScope.cowork.label(projects: projects) == "Cowork")
    #expect(LibraryScope.project(root: b).label(projects: projects) == "A")
    #expect(LibraryScope.project(root: URL(fileURLWithPath: "/gone", isDirectory: true)).label(projects: projects) == "gone")
    #expect(LibraryScope.project(root: a).persistenceKey == "project:/Users/x/A")
    #expect(LibraryScope.from(persistenceKey: "project:/Users/x/A", projects: projects) == .project(root: a))
    #expect(LibraryScope.from(persistenceKey: "project:/gone", projects: projects) == .everywhere)   // vanished project
    #expect(LibraryScope.from(persistenceKey: "cowork", projects: projects) == .cowork)
    #expect(LibraryScope.from(persistenceKey: nil, projects: projects) == .everywhere)
    #expect(LibraryScope.from(persistenceKey: "garbage", projects: projects) == .everywhere)
}

@Test func hiddenCountSpansAllRowKinds() {
    var lib = Library()
    lib.skills = [entry([skill("g", .personal)]), entry([skill("pb", .project(root: b, subpath: nil))])]
    lib.builtIn = [entry([skill("bi", .account(userMade: false))])]
    lib.plugins = [pentry([plugin("cw@m", .cowork)]), pentry([plugin("u@m", .user)])]
    let shared = [skill("sh", .shared)]
    #expect(LibraryScope.hiddenCount(in: lib, sharedSkills: shared, scope: .project(root: a)) == 3)   // pb, cw, sh
    #expect(LibraryScope.hiddenCount(in: lib, sharedSkills: shared, scope: .everywhere) == 0)
}

@Test func availableCountSpansPluginsSkillsAndBuiltIn() {
    var lib = Library()
    lib.skills = [entry([skill("g", .personal)]), entry([skill("pb", .project(root: b, subpath: nil))])]
    lib.builtIn = [entry([skill("bi", .account(userMade: false))])]
    lib.plugins = [pentry([plugin("cw@m", .cowork)]), pentry([plugin("u@m", .user)])]
    // Everywhere: everything is available — 2 skills + 1 built-in + 2 plugins.
    #expect(LibraryScope.availableCount(in: lib, scope: .everywhere) == 5)
    // Project a: g (personal), bi (account), u@m (user plugin) — not pb (other root) or cw (cowork plugin).
    #expect(LibraryScope.availableCount(in: lib, scope: .project(root: a)) == 3)
    // Cowork: bi (account) and cw@m — not the personal/project skills or the user plugin.
    #expect(LibraryScope.availableCount(in: lib, scope: .cowork) == 2)
}
