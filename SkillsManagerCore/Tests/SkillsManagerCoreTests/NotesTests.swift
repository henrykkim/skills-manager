import Foundation
import Testing
@testable import SkillsManagerCore

@Test func classifyFolders() throws {
    let t = try TempTree(); defer { t.remove() }
    try t.skill("x", in: "proj/.claude/skills")
    try t.write("{}", to: "settingsOnly/.claude/settings.json")
    try t.write("# Brief", to: "brain/skills/morning-brief.md")
    try t.skill("y", in: "bareSkills")            // not loaded by Claude → not a project
    try t.write("hi", to: "empty/readme.txt")

    #expect(NoteFolders.classify(t.url("proj")) == .project)
    #expect(NoteFolders.classify(t.url("settingsOnly")) == .project)
    #expect(NoteFolders.classify(t.url("brain/skills")) == .notes)
    #expect(NoteFolders.classify(t.url("bareSkills")) == .neither)
    #expect(NoteFolders.classify(t.url("empty")) == .neither)
}

@Test func loadListsTopLevelMarkdownOnly() throws {
    let t = try TempTree(); defer { t.remove() }
    try t.write("a", to: "brain/skills/b-note.md")
    try t.write("a", to: "brain/skills/a-note.md")
    try t.write("a", to: "brain/skills/deeper/c-note.md")
    try t.write("a", to: "brain/skills/image.png")

    let folder = try #require(NoteFolders.load(t.url("brain/skills")))
    #expect(folder.name == "skills")
    #expect(folder.files.map(\.name) == ["a-note.md", "b-note.md"])
    #expect(NoteFolders.load(t.url("missing")) == nil)
}

@Test func markdownBlocksParseCommonShapes() {
    let md = """
    ---
    name: skip-me
    ---
    # Morning brief
    Pull my calendar
    and my inbox.

    - first
    * second
    1. numbered
    ```
    code line
    ```
    ## Done
    """
    #expect(MarkdownBlocks.parse(md) == [
        .heading(level: 1, text: "Morning brief"),
        .paragraph("Pull my calendar and my inbox."),
        .bullet("first"),
        .bullet("second"),
        .numbered("numbered"),
        .code("code line"),
        .heading(level: 2, text: "Done"),
    ])
}

@Test func markdownBlocksHandleCRLFLineEndings() {
    let md = "# T\r\nline one\r\nline two\r\n```\r\na\r\nb\r\n```"
    #expect(MarkdownBlocks.parse(md) == [
        .heading(level: 1, text: "T"),
        .paragraph("line one line two"),
        .code("a\nb"),
    ])
}

@Test func markdownBlocksHandleAdversarialLines() {
    #expect(MarkdownBlocks.parse("#") == [.paragraph("#")])
    #expect(MarkdownBlocks.parse("1.") == [.paragraph("1.")])
    #expect(MarkdownBlocks.parse("```\ncode") == [.code("code")])
}
