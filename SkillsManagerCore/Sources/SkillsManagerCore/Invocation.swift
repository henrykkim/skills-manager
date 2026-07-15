import Foundation

/// Computes what the user actually types — the heart of the cheat sheet (spec §5.2).
public enum Invocation {
    /// Uses displayName (the skill's declared frontmatter name, folder fallback):
    /// agents resolve skills by declared name, and the detail header shows the
    /// same value — the copyable command must never contradict the title above it.
    public static func string(for skill: Skill) -> String {
        switch skill.source {
        case .personal, .shared:
            return "/\(skill.displayName)"
        case .plugin(let pluginID):
            let pluginName = pluginID.split(separator: "@", maxSplits: 1).first.map(String.init) ?? pluginID
            return "/\(pluginName):\(skill.displayName)"
        }
    }

    public static func availabilityLabel(for skill: Skill) -> String {
        // A skill that still shows as .shared is NOT connected to Claude Code
        // (connected ones are deduped into the personal list by Inventory.load).
        // Never claim Claude Code can use it.
        if case .shared = skill.source {
            return "In the shared skills folder — agents that read ~/.agents/skills can use it. "
                + "Claude Code sees it only once it's connected there."
        }
        switch (skill.userInvocable, skill.modelInvocable) {
        case (true, true):
            return "Type the command yourself, or Claude uses it automatically when relevant."
        case (false, true):
            return "Claude uses this automatically — it won't appear in the / menu."
        case (true, false):
            return "Only runs when you type its command — Claude won't trigger it on its own."
        case (false, false):
            return "Currently not invocable — check the skill's settings."
        }
    }
}
