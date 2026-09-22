import Foundation
import Testing
@testable import SkillsManagerCore

/// Canned GitHub. Keys: "owner/repo" → repo; tree paths; raw files by path.
struct StubGitHubClient: GitHubClient {
    var repos: [String: GitHubRepo] = [:]
    var trees: [String: [String]] = [:]
    var files: [String: String] = [:]
    var failure: InstallError?

    func repo(owner: String, repo: String) async throws -> GitHubRepo {
        if let failure { throw failure }
        guard let r = repos["\(owner)/\(repo)"] else { throw InstallError.repoNotFound }
        return r
    }
    func treePaths(owner: String, repo: String, branch: String) async throws -> [String] {
        trees["\(owner)/\(repo)"] ?? []
    }
    func raw(owner: String, repo: String, branch: String, path: String) async throws -> String {
        guard let f = files[path] else { throw InstallError.other("missing \(path)") }
        return f
    }
}

private func skillFile(_ name: String, _ desc: String) -> String {
    "---\nname: \(name)\ndescription: \(desc)\n---\n\n# \(name)\n\nBody of \(name).\n"
}

private func stub() -> StubGitHubClient {
    StubGitHubClient(
        repos: ["jakubkrehel/skills": GitHubRepo(description: "Better interfaces", defaultBranch: "main",
                                                htmlURL: URL(string: "https://github.com/jakubkrehel/skills")!,
                                                ownerURL: URL(string: "https://github.com/jakubkrehel"))],
        trees: ["jakubkrehel/skills": ["README.md", "skills/better-ui/SKILL.md", "skills/better-layout/SKILL.md",
                                       "skills/broken/SKILL.md", "skills/better-ui/notes.md"]],
        files: ["skills/better-ui/SKILL.md": skillFile("better-ui", "Polish UI"),
                "skills/better-layout/SKILL.md": skillFile("better-layout", "Layout help"),
                "skills/broken/SKILL.md": "---\nname: broken\n"])
}

@Test func resolvesSkillsRepoWithAllSkillsPreselected() async throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let resolver = InstallResolver(github: stub(), paths: ClaudePaths(home: home))
    let p = try await resolver.resolve(.skillsRepo(owner: "jakubkrehel", repo: "skills", subpath: nil, onlySkills: nil))
    #expect(p.kind == .skillsRepo)
    #expect(p.title == "jakubkrehel/skills")
    #expect(p.summary == "Better interfaces")
    #expect(p.authorName == "jakubkrehel")
    #expect(p.sourceURL == URL(string: "https://github.com/jakubkrehel/skills"))
    #expect(p.skills.map(\.folder) == ["better-layout", "better-ui", "broken"])   // sorted
    let ui = try #require(p.skills.first { $0.folder == "better-ui" })
    #expect(ui.name == "better-ui"); #expect(ui.summary == "Polish UI"); #expect(ui.invocation == "/better-ui")
    #expect(ui.isValid); #expect(ui.isPreselected); #expect(!ui.isInstalled)
    #expect(ui.body.contains("Body of better-ui"))
    let broken = try #require(p.skills.first { $0.folder == "broken" })
    #expect(!broken.isValid); #expect(!broken.isPreselected)
}

@Test func onlySkillsNarrowsPreselection() async throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let resolver = InstallResolver(github: stub(), paths: ClaudePaths(home: home))
    let p = try await resolver.resolve(.skillsRepo(owner: "jakubkrehel", repo: "skills", subpath: nil, onlySkills: ["better-ui"]))
    #expect(p.skills.filter(\.isPreselected).map(\.folder) == ["better-ui"])
}

@Test func subpathNarrowsDiscovery() async throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let resolver = InstallResolver(github: stub(), paths: ClaudePaths(home: home))
    let p = try await resolver.resolve(.skillsRepo(owner: "jakubkrehel", repo: "skills", subpath: "skills/better-layout", onlySkills: ["better-layout"]))
    #expect(p.skills.map(\.folder) == ["better-layout"])
}

@Test func alreadyInstalledSkillIsFlaggedAndNotPreselected() async throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    var s = stub()
    s.trees["jakubkrehel/skills"]?.append("skills/shared-skill/SKILL.md")   // exists in fixture ~/.agents/skills
    s.files["skills/shared-skill/SKILL.md"] = skillFile("shared-skill", "dup")
    let p = try await InstallResolver(github: s, paths: ClaudePaths(home: home))
        .resolve(.skillsRepo(owner: "jakubkrehel", repo: "skills", subpath: nil, onlySkills: nil))
    let dup = try #require(p.skills.first { $0.folder == "shared-skill" })
    #expect(dup.isInstalled); #expect(!dup.isPreselected)
}

@Test func repoNotFoundAndNoSkillsAndRateLimit() async throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let paths = ClaudePaths(home: home)
    await #expect(throws: InstallError.repoNotFound) {
        try await InstallResolver(github: StubGitHubClient(), paths: paths)
            .resolve(.skillsRepo(owner: "nobody", repo: "nothing", subpath: nil, onlySkills: nil))
    }
    var empty = stub(); empty.trees["jakubkrehel/skills"] = ["README.md"]
    await #expect(throws: InstallError.noSkills) {
        try await InstallResolver(github: empty, paths: paths)
            .resolve(.skillsRepo(owner: "jakubkrehel", repo: "skills", subpath: nil, onlySkills: nil))
    }
    var limited = stub(); limited.failure = .rateLimited
    await #expect(throws: InstallError.rateLimited) {
        try await InstallResolver(github: limited, paths: paths)
            .resolve(.skillsRepo(owner: "jakubkrehel", repo: "skills", subpath: nil, onlySkills: nil))
    }
}

@Test func resolvesPluginInKnownMarketplaceAndAlreadyInstalled() async throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    // Fixture registry knows demo-plugin@test-market; write a marketplace.json so details resolve.
    let mdir = home.appending(path: ".claude/plugins/marketplaces/test-market/.claude-plugin")
    try FileManager.default.createDirectory(at: mdir, withIntermediateDirectories: true)
    try #"{ "name": "test-market", "plugins": [ { "name": "other-plugin", "description": "Another one", "homepage": "https://example.com/other" } ] }"#
        .write(to: mdir.appending(path: "marketplace.json"), atomically: true, encoding: .utf8)
    let resolver = InstallResolver(github: StubGitHubClient(), paths: ClaudePaths(home: home))

    let fresh = try await resolver.resolve(.plugin(name: "other-plugin", marketplace: "test-market", marketplaceSource: nil))
    #expect(fresh.kind == .plugin); #expect(fresh.title == "other-plugin")
    #expect(fresh.summary == "Another one"); #expect(fresh.sourceURL == URL(string: "https://example.com/other"))
    #expect(!fresh.isPluginInstalled); #expect(fresh.marketplaceNote == nil); #expect(fresh.skills.isEmpty)

    let dup = try await resolver.resolve(.plugin(name: "demo-plugin", marketplace: "test-market", marketplaceSource: nil))
    #expect(dup.isPluginInstalled)
}

@Test func resolvesPluginInUnknownMarketplaceWithNote() async throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let p = try await InstallResolver(github: StubGitHubClient(), paths: ClaudePaths(home: home))
        .resolve(.plugin(name: "interfaces", marketplace: "interfaces", marketplaceSource: "jakubkrehel/skills"))
    #expect(p.title == "interfaces")
    #expect(p.marketplaceNote == "Will add marketplace interfaces from jakubkrehel/skills first.")
    #expect(p.summary == nil)
}

@Test func unrecognizedIntentThrows() async throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    await #expect(throws: InstallError.other(Diagnosis.generic)) {
        try await InstallResolver(github: StubGitHubClient(), paths: ClaudePaths(home: home))
            .resolve(.unrecognized(diagnosis: Diagnosis.generic))
    }
}
