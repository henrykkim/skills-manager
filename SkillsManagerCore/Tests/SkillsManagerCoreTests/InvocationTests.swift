import Foundation
import Testing
@testable import SkillsManagerCore

private func makeSkill(folder: String, displayName: String? = nil, source: SkillSource,
                       userInvocable: Bool = true, modelInvocable: Bool = true) -> Skill {
    Skill(folderName: folder, displayName: displayName ?? folder, summary: nil, argumentHint: nil,
          userInvocable: userInvocable, modelInvocable: modelInvocable, whenToUse: nil,
          source: source, directory: URL(fileURLWithPath: "/tmp/\(folder)"), lastModified: nil)
}

@Test func personalSkillInvocationIsSlashName() {
    let skill = makeSkill(folder: "good-skill", source: .personal)
    #expect(Invocation.string(for: skill) == "/good-skill")
}

@Test func invocationUsesFolderNameNotDeclaredName() {
    // Ground truth (Claude Code docs, "How a skill gets its command name"):
    // the typed command comes from the DIRECTORY name; frontmatter `name` is a
    // display label only. displayName stays for headers — never for commands.
    let skill = makeSkill(folder: "folder-name", displayName: "actual-name", source: .personal)
    #expect(Invocation.string(for: skill) == "/folder-name")
}

@Test func sharedSkillInvocationIsSlashName() {
    let skill = makeSkill(folder: "shared-skill", source: .shared)
    #expect(Invocation.string(for: skill) == "/shared-skill")
}

@Test func pluginSkillInvocationIsNamespaced() {
    let skill = makeSkill(folder: "brainstorming", source: .plugin(pluginID: "superpowers@claude-plugins-official"))
    #expect(Invocation.string(for: skill) == "/superpowers:brainstorming")
}

@Test func availabilityLabelsArePlainEnglish() {
    #expect(Invocation.availabilityLabel(for: makeSkill(folder: "a", source: .personal))
        == "Type the command yourself, or Claude uses it automatically when relevant.")
    #expect(Invocation.availabilityLabel(for: makeSkill(folder: "b", source: .personal, userInvocable: false))
        == "Claude uses this automatically — it won't appear in the / menu.")
    #expect(Invocation.availabilityLabel(for: makeSkill(folder: "c", source: .personal, modelInvocable: false))
        == "Only runs when you type its command — Claude won't trigger it on its own.")
}

@Test func sharedSkillLabelNeverClaimsClaudeCodeAccess() {
    // A skill only in ~/.agents/skills is NOT visible to Claude Code (spec §4);
    // wrong info is worse than missing info (spec §7).
    let label = Invocation.availabilityLabel(for: makeSkill(folder: "s", source: .shared))
    #expect(label.contains("shared skills folder"))
    #expect(!label.contains("Claude uses it automatically"))
}
