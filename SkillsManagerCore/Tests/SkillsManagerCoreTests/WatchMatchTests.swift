import Foundation
import Testing
@testable import SkillsManagerCore

@Test func watchEventUnderTargetMatchesOnlyAtASeparator() {
    let t = "/Users/me/P/.claude/skills"
    #expect(WatchMatch.isRelevant(eventPath: t, target: t))
    #expect(WatchMatch.isRelevant(eventPath: t + "/", target: t))            // FSEvents dir paths end in "/"
    #expect(WatchMatch.isRelevant(eventPath: t + "/review/", target: t))
    #expect(!WatchMatch.isRelevant(eventPath: t + "-old/", target: t))      // sibling sharing a prefix
}

@Test func watchEventOnAncestorMatchesOnlyTheDirectParent() {
    let t = "/Users/me/P/.claude/skills"
    #expect(WatchMatch.isRelevant(eventPath: "/Users/me/P/.claude/", target: t))  // target may have appeared
    #expect(!WatchMatch.isRelevant(eventPath: "/Users/me/P/", target: t))
    #expect(!WatchMatch.isRelevant(eventPath: "/Users/me/", target: t))           // ~/.zsh_history etc.
    #expect(!WatchMatch.isRelevant(eventPath: "/Users/me/P/.claude/worktrees/x/", target: t))
}
