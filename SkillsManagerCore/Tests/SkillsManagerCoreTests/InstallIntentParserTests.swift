import Foundation
import Testing
@testable import SkillsManagerCore

@Test func parsesSlashPluginPair() {
    let text = "/plugin marketplace add jakubkrehel/skills\n/plugin install interfaces@interfaces"
    #expect(InstallIntentParser.parse(text) ==
        .plugin(name: "interfaces", marketplace: "interfaces", marketplaceSource: "jakubkrehel/skills"))
}

@Test func parsesSlashPluginSingle() {
    #expect(InstallIntentParser.parse("/plugin install superpowers@claude-plugins-official") ==
        .plugin(name: "superpowers", marketplace: "claude-plugins-official", marketplaceSource: nil))
}

@Test func parsesCliPluginWithMarketplaceAdd() {
    let text = "claude plugin marketplace add https://github.com/obra/superpowers-marketplace\nclaude plugin install superpowers@superpowers-marketplace"
    #expect(InstallIntentParser.parse(text) ==
        .plugin(name: "superpowers", marketplace: "superpowers-marketplace",
                marketplaceSource: "https://github.com/obra/superpowers-marketplace"))
}

@Test func parsesNpxSkillsAdd() {
    #expect(InstallIntentParser.parse("npx skills add jakubkrehel/skills") ==
        .skillsRepo(owner: "jakubkrehel", repo: "skills", subpath: nil, onlySkills: nil))
}

@Test func parsesNpxSkillsAddWithSkillFlags() {
    #expect(InstallIntentParser.parse("npx skills add emilkowalski/skills --skill apple-design,emil-design-eng") ==
        .skillsRepo(owner: "emilkowalski", repo: "skills", subpath: nil, onlySkills: ["apple-design", "emil-design-eng"]))
    #expect(InstallIntentParser.parse("npx skills add emilkowalski/skills -s apple-design") ==
        .skillsRepo(owner: "emilkowalski", repo: "skills", subpath: nil, onlySkills: ["apple-design"]))
}

@Test func cliPluginPairInsideBackticks() {
    let text = "Run `claude plugin marketplace add obra/superpowers-marketplace` then `claude plugin install superpowers@superpowers-marketplace`."
    #expect(InstallIntentParser.parse(text) ==
        .plugin(name: "superpowers", marketplace: "superpowers-marketplace", marketplaceSource: "obra/superpowers-marketplace"))
}

@Test func parsesNpxSkillsAddWithGitHubURL() {
    #expect(InstallIntentParser.parse("npx skills add https://github.com/vercel-labs/agent-skills") ==
        .skillsRepo(owner: "vercel-labs", repo: "agent-skills", subpath: nil, onlySkills: nil))
}

@Test func npxSkillFlagsAfterOtherFlags() {
    #expect(InstallIntentParser.parse("npx skills add o/r -g -y --skill apple-design") ==
        .skillsRepo(owner: "o", repo: "r", subpath: nil, onlySkills: ["apple-design"]))
    #expect(InstallIntentParser.parse("npx skills add o/r -a claude-code -s a,b -y") ==
        .skillsRepo(owner: "o", repo: "r", subpath: nil, onlySkills: ["a", "b"]))
    #expect(InstallIntentParser.parse("npx skills add o/r --skill a --skill b") ==
        .skillsRepo(owner: "o", repo: "r", subpath: nil, onlySkills: ["a", "b"]))
}

@Test func parsesNpxInsideReadmeSentence() {
    let text = "## Install\n\nWe recommend the CLI. Run `npx skills add emilkowalski/skills --skill apple-design` and restart Claude."
    #expect(InstallIntentParser.parse(text) ==
        .skillsRepo(owner: "emilkowalski", repo: "skills", subpath: nil, onlySkills: ["apple-design"]))
}

@Test func parsesSkillsShLinks() {
    #expect(InstallIntentParser.parse("https://skills.sh/jakubkrehel/skills") ==
        .skillsRepo(owner: "jakubkrehel", repo: "skills", subpath: nil, onlySkills: nil))
    #expect(InstallIntentParser.parse("https://www.skills.sh/jakubkrehel/skills/better-ui") ==
        .skillsRepo(owner: "jakubkrehel", repo: "skills", subpath: nil, onlySkills: ["better-ui"]))
}

@Test func parsesGitHubLinks() {
    #expect(InstallIntentParser.parse("https://github.com/jakubkrehel/skills") ==
        .skillsRepo(owner: "jakubkrehel", repo: "skills", subpath: nil, onlySkills: nil))
    #expect(InstallIntentParser.parse("https://github.com/jakubkrehel/skills.git") ==
        .skillsRepo(owner: "jakubkrehel", repo: "skills", subpath: nil, onlySkills: nil))
    #expect(InstallIntentParser.parse("https://github.com/jakubkrehel/skills/tree/main/skills/better-ui") ==
        .skillsRepo(owner: "jakubkrehel", repo: "skills", subpath: "skills/better-ui", onlySkills: ["better-ui"]))
}

@Test func parsesBareShorthandAloneOnALine() {
    #expect(InstallIntentParser.parse("  jakubkrehel/skills \n") ==
        .skillsRepo(owner: "jakubkrehel", repo: "skills", subpath: nil, onlySkills: nil))
    // Not alone on a line → not shorthand.
    #expect(InstallIntentParser.parse("check out jakubkrehel/skills sometime") == .unrecognized(diagnosis: Diagnosis.generic))
}

@Test func slashPluginWinsOverEmbeddedRepoShorthand() {
    // The marketplace-add line also contains "o/r"; plugin shape must be matched first.
    let text = "/plugin marketplace add jakubkrehel/skills\n/plugin install interfaces@interfaces"
    if case .plugin = InstallIntentParser.parse(text) {} else { Issue.record("expected plugin") }
}

@Test func rejectsPackageManagers() {
    #expect(InstallIntentParser.parse("brew install ripgrep") == .unrecognized(diagnosis: Diagnosis.packageManager("Homebrew")))
    #expect(InstallIntentParser.parse("npm install -g typescript") == .unrecognized(diagnosis: Diagnosis.packageManager("npm")))
    #expect(InstallIntentParser.parse("pip install requests") == .unrecognized(diagnosis: Diagnosis.packageManager("pip")))
}

@Test func rejectsNonGitHubURL() {
    #expect(InstallIntentParser.parse("https://notion.so/some-page") == .unrecognized(diagnosis: Diagnosis.nonGitHubURL))
}

@Test func rejectsProseAndEmpty() {
    #expect(InstallIntentParser.parse("hello there") == .unrecognized(diagnosis: Diagnosis.generic))
    #expect(InstallIntentParser.parse("   ") == .unrecognized(diagnosis: Diagnosis.generic))
}
