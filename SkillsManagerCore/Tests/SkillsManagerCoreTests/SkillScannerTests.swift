import Foundation
import Testing
@testable import SkillsManagerCore

@Test func scansPersonalSkillsWithIssues() throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let paths = ClaudePaths(home: home)

    let result = SkillScanner.scan(directory: paths.personalSkillsDir, source: .personal)

    // good-skill, minimal-skill, background-skill, and the symlinked shared-skill parse;
    // broken-skill and empty-folder become issues
    #expect(result.skills.count == 4)
    #expect(result.issues.count == 2)

    // Symlinked skill folders (how npx skills connects agents) must scan like real ones
    let linked = try #require(result.skills.first { $0.folderName == "shared-skill" })
    #expect(linked.source == .personal) // scanned where Claude Code sees it

    let good = try #require(result.skills.first { $0.folderName == "good-skill" })
    #expect(good.displayName == "good-skill")
    #expect(good.summary?.contains("release notes") == true)
    #expect(good.argumentHint == "<version-number>")
    #expect(good.userInvocable == true)
    #expect(good.modelInvocable == true)
    #expect(good.source == .personal)
    #expect(good.lastModified != nil)

    let minimal = try #require(result.skills.first { $0.folderName == "minimal-skill" })
    #expect(minimal.displayName == "minimal-skill") // falls back to folder name

    let background = try #require(result.skills.first { $0.folderName == "background-skill" })
    #expect(background.userInvocable == false)

    #expect(result.issues.contains { $0.location.path.contains("broken-skill") })
    #expect(result.issues.contains { $0.location.path.contains("empty-folder") })
}

@Test func missingDirectoryYieldsEmptyResult() {
    let result = SkillScanner.scan(
        directory: URL(fileURLWithPath: "/definitely/not/real"), source: .shared)
    #expect(result.skills.isEmpty)
    #expect(result.issues.isEmpty)
}
