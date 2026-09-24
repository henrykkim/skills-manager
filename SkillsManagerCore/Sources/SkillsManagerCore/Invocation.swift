import Foundation

/// Computes what the user actually types — the heart of the cheat sheet (spec §5.2).
public enum Invocation {
    /// Uses folderName: per Claude Code's docs ("How a skill gets its command
    /// name"), the typed command comes from the skill's DIRECTORY name — the
    /// frontmatter `name` is a display label and does not change what you type.
    /// (Exception not relevant here: a plugin-root SKILL.md; plan 2 note.)
    public static func string(for skill: Skill) -> String {
        switch skill.source {
        case .personal, .shared, .project:
            return "/\(skill.folderName)"
        case .plugin(let pluginID):
            let pluginName = pluginID.split(separator: "@", maxSplits: 1).first.map(String.init) ?? pluginID
            return "/\(pluginName):\(skill.folderName)"
        case .account:
            // Claude-account skills load in Claude Code (desktop) as the
            // built-in anthropic-skills plugin.
            return "/anthropic-skills:\(skill.folderName)"
        }
    }

    public static func availabilityLabel(for skill: Skill) -> String {
        if case .account = skill.source, !skill.isEnabled {
            return "Turned off in your Claude account. Turn it back on in Claude → Settings → Skills."
        }
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
