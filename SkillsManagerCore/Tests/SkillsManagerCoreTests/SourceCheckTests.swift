import Foundation
import Testing
@testable import SkillsManagerCore

private func lock(_ pairs: [(folder: String, source: String)]) -> SkillLock {
    SkillLock(entries: Dictionary(uniqueKeysWithValues: pairs.map {
        ($0.folder, SkillLockEntry(sourceLabel: $0.source, sourceURL: nil, installedAt: nil, updatedAt: nil)) }))
}

@Test func reportsOnlyUninstalledSkillsWithFrontmatter() async {
    var gh = StubGitHubClient()
    gh.trees["jakubkrehel/skills"] = ["README.md", "skills/better-ui/SKILL.md", "skills/teardown/SKILL.md", "skills/teardown/ref.md"]
    gh.files["skills/teardown/SKILL.md"] = skillFile("Teardown", "Take an interface apart")
    let result = await SourceCheck(github: gh).run(
        lock: lock([("better-ui", "jakubkrehel/skills")]), installedFolders: ["better-ui"])
    #expect(result.completed)
    #expect(result.findings.count == 1)
    let f = result.findings[0]
    #expect(f.id == "jakubkrehel/skills")
    #expect(f.skills == [NewSkill(folder: "teardown", name: "Teardown", summary: "Take an interface apart", path: "skills/teardown/SKILL.md")])
    #expect(f.key(f.skills[0]) == "jakubkrehel/skills#teardown")
    #expect(f.skillURL(f.skills[0]) == URL(string: "https://github.com/jakubkrehel/skills/tree/HEAD/skills/teardown"))
}

@Test func folderOnDiskIsNotNewEvenWhenNotInLock() async {
    var gh = StubGitHubClient()
    gh.trees["o/r"] = ["skills/a/SKILL.md", "skills/b/SKILL.md"]
    gh.files["skills/b/SKILL.md"] = skillFile("b", "B")
    let result = await SourceCheck(github: gh).run(lock: lock([("a", "o/r")]), installedFolders: ["a", "b"])
    #expect(result.findings.isEmpty)
    #expect(result.completed)
}

@Test func reposWithNothingNewProduceNoFinding() async {
    var gh = StubGitHubClient()
    gh.trees["o/r"] = ["skills/a/SKILL.md"]
    let result = await SourceCheck(github: gh).run(lock: lock([("a", "o/r")]), installedFolders: ["a"])
    #expect(result == SourceCheckResult(findings: [], completed: true))
}

@Test func rootSkillRepoUsesRepoNameAsFolder() async {
    var gh = StubGitHubClient()
    gh.trees["o/single"] = ["SKILL.md"]
    let result = await SourceCheck(github: gh).run(lock: lock([("single", "o/single")]), installedFolders: ["single"])
    #expect(result.findings.isEmpty)
}

@Test func malformedFrontmatterStillReportedWithFolderName() async {
    var gh = StubGitHubClient()
    gh.trees["o/r"] = ["skills/a/SKILL.md", "skills/broken/SKILL.md"]
    gh.files["skills/broken/SKILL.md"] = "---\nname: broken\n"
    let result = await SourceCheck(github: gh).run(lock: lock([("a", "o/r")]), installedFolders: ["a"])
    #expect(result.findings[0].skills == [NewSkill(folder: "broken", name: "broken", summary: nil, path: "skills/broken/SKILL.md")])
}

@Test func notFoundRepoIsSkippedOthersContinue() async {
    var gh = StubGitHubClient()
    gh.trees["o/r"] = ["skills/a/SKILL.md", "skills/new/SKILL.md"]
    gh.files["skills/new/SKILL.md"] = skillFile("new", "N")
    let result = await SourceCheck(github: gh).run(
        lock: lock([("a", "o/r"), ("x", "gone/repo")]), installedFolders: ["a", "x"])
    #expect(result.completed)
    #expect(result.findings.map(\.id) == ["o/r"])
}

@Test func rateLimitAbortsRunIncomplete() async {
    var gh = StubGitHubClient()
    gh.trees["a/one"] = ["skills/new/SKILL.md"]
    gh.files["skills/new/SKILL.md"] = skillFile("new", "N")
    gh.failure = .rateLimited
    let result = await SourceCheck(github: gh).run(lock: lock([("k", "a/one"), ("j", "b/two")]), installedFolders: ["k", "j"])
    #expect(!result.completed)
    #expect(result.findings.isEmpty)
}

@Test func neverDownloadsInstalledSkills() async {
    var gh = StubGitHubClient()
    gh.trees["o/r"] = ["skills/a/SKILL.md"]
    let result = await SourceCheck(github: gh).run(lock: lock([("a", "o/r")]), installedFolders: ["a"])
    #expect(result == SourceCheckResult(findings: [], completed: true))
}
