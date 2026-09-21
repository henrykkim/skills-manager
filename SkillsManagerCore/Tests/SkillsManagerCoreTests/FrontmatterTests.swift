import Testing
@testable import SkillsManagerCore

@Test func parsesFullFrontmatter() {
    let text = """
    ---
    name: good-skill
    description: Formats release notes.
    argument-hint: "<version>"
    user-invocable: false
    disable-model-invocation: true
    when_to_use: Before every release.
    ---

    # Body
    """
    guard case .parsed(let fm, let body) = FrontmatterParser.parse(text) else {
        Issue.record("expected .parsed"); return
    }
    #expect(fm.name == "good-skill")
    #expect(fm.description == "Formats release notes.")
    #expect(fm.argumentHint == "<version>")
    #expect(fm.userInvocable == false)
    #expect(fm.disableModelInvocation == true)
    #expect(fm.whenToUse == "Before every release.")
    #expect(body.contains("# Body"))
}

@Test func stringBooleansAreCoerced() {
    let text = "---\nname: x\nuser-invocable: \"false\"\n---\nbody"
    guard case .parsed(let fm, _) = FrontmatterParser.parse(text) else {
        Issue.record("expected .parsed"); return
    }
    #expect(fm.userInvocable == false)
}

@Test func missingFrontmatterIsMissing() {
    guard case .missing(let body) = FrontmatterParser.parse("# Just markdown\n") else {
        Issue.record("expected .missing"); return
    }
    #expect(body.contains("Just markdown"))
}

@Test func unclosedFrontmatterIsMalformed() {
    guard case .malformed = FrontmatterParser.parse("---\nname: x\nno closing fence") else {
        Issue.record("expected .malformed"); return
    }
}

@Test func invalidYAMLIsMalformed() {
    guard case .malformed = FrontmatterParser.parse("---\ndescription: [unclosed\n---\nbody") else {
        Issue.record("expected .malformed"); return
    }
}

@Test func nonMapYAMLIsMalformed() {
    guard case .malformed = FrontmatterParser.parse("---\n- just\n- a list\n---\nbody") else {
        Issue.record("expected .malformed"); return
    }
}
