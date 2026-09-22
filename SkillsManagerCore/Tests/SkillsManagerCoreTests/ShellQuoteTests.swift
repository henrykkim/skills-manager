import Testing
@testable import SkillsManagerCore

@Test func safeTokensAreNotQuoted() {
    for s in ["o/r", "p@m", "a,b", "https://github.com/o/r.git", "-s", "--skill", "claude-code", "-y"] {
        #expect(ShellCommandRunner.quote(s) == s)
    }
}

@Test func unsafeTokensAreSingleQuotedAndEscaped() {
    #expect(ShellCommandRunner.quote("a b") == "'a b'")
    #expect(ShellCommandRunner.quote("x;rm -rf ~") == "'x;rm -rf ~'")
    #expect(ShellCommandRunner.quote("$(whoami)") == "'$(whoami)'")
    #expect(ShellCommandRunner.quote("it's") == "'it'\\''s'")
    #expect(ShellCommandRunner.quote("`ls`") == "'`ls`'")
    #expect(ShellCommandRunner.quote("") == "''")
}
