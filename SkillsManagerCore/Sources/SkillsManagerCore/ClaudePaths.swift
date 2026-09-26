import Foundation

/// Single source for every filesystem location the app reads.
/// Inject `home` for tests; set env var SKILLS_MANAGER_HOME to sandbox the whole app.
public struct ClaudePaths: Sendable {
    public let home: URL

    public init(home: URL? = nil) {
        if let home {
            self.home = home
        } else if let override = ProcessInfo.processInfo.environment["SKILLS_MANAGER_HOME"] {
            self.home = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            self.home = FileManager.default.homeDirectoryForCurrentUser
        }
    }

    public var claudeDir: URL { home.appending(path: ".claude", directoryHint: .isDirectory) }
    public var personalSkillsDir: URL { claudeDir.appending(path: "skills", directoryHint: .isDirectory) }
    /// Claude Code session transcripts (terminal and desktop Code tab), one
    /// JSONL per session under an escaped-cwd folder.
    public var claudeCodeLogsDir: URL { claudeDir.appending(path: "projects", directoryHint: .isDirectory) }
    public var settingsFile: URL { claudeDir.appending(path: "settings.json") }
    public var pluginsDir: URL { claudeDir.appending(path: "plugins", directoryHint: .isDirectory) }
    public var installedPluginsFile: URL { pluginsDir.appending(path: "installed_plugins.json") }
    public var knownMarketplacesFile: URL { pluginsDir.appending(path: "known_marketplaces.json") }
    public var pluginsCacheDir: URL { pluginsDir.appending(path: "cache", directoryHint: .isDirectory) }
    public var agentsDir: URL { home.appending(path: ".agents", directoryHint: .isDirectory) }
    public var sharedSkillsDir: URL { agentsDir.appending(path: "skills", directoryHint: .isDirectory) }
    /// Written by the `npx skills` installer; records where each shared skill came from.
    public var agentsLockFile: URL { agentsDir.appending(path: ".skill-lock.json") }

    /// Terminal Claude Code's settings, including the `projects` map of every
    /// folder it has been opened in.
    public var claudeJSON: URL { home.appending(path: ".claude.json") }
    public var desktopSupportDir: URL {
        home.appending(path: "Library/Application Support/Claude", directoryHint: .isDirectory)
    }
    /// Claude desktop app, Code tab: one JSON file per session (`cwd`, `originCwd`).
    public var codeSessionsDir: URL { desktopSupportDir.appending(path: "claude-code-sessions", directoryHint: .isDirectory) }
    /// Claude desktop app, Cowork: session files (`userSelectedFolders`) and Cowork's own plugins.
    public var coworkSessionsDir: URL { desktopSupportDir.appending(path: "local-agent-mode-sessions", directoryHint: .isDirectory) }
    /// Local copy of the skills in the user's Claude account.
    public var accountSkillsDir: URL { coworkSessionsDir.appending(path: "skills-plugin", directoryHint: .isDirectory) }
    public var userPluginStore: PluginStore { PluginStore(root: pluginsDir) }
}
