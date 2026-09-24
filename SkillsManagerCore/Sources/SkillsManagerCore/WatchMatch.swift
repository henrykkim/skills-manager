import Foundation

/// Which FSEvents paths matter for a watched target (both canonical paths).
public enum WatchMatch {
    /// Relevant when the event is the target or inside it (at a "/" boundary),
    /// or is the target's direct parent — a parent-folder event may mean the
    /// target itself just appeared. Events higher up (e.g. the home folder
    /// when ~/.zsh_history changes) are ignored.
    public static func isRelevant(eventPath: String, target: String) -> Bool {
        // Directory-level FSEvents paths end in "/".
        var event = eventPath
        while event.count > 1 && event.hasSuffix("/") { event.removeLast() }
        if event == target || event.hasPrefix(target + "/") { return true }
        return event == (target as NSString).deletingLastPathComponent
    }
}
