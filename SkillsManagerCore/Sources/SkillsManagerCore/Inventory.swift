import Foundation

/// Everything the app knows, loaded in one synchronous pass (callers move it
/// off the main thread). The filesystem is the source of truth — reload = re-scan.
public struct Inventory: Sendable {
    public var personalSkills: [Skill]
    public var sharedSkills: [Skill]
    public var plugins: [Plugin]
    public var issues: [ParseIssue]

    public init(personalSkills: [Skill] = [], sharedSkills: [Skill] = [],
                plugins: [Plugin] = [], issues: [ParseIssue] = []) {
        self.personalSkills = personalSkills
        self.sharedSkills = sharedSkills
        self.plugins = plugins
        self.issues = issues
    }

    public static func load(paths: ClaudePaths) -> Inventory {
        let enabled = SettingsReader.enabledPlugins(settingsFile: paths.settingsFile)
        let lock = SkillLock.load(file: paths.agentsLockFile)
        let personal = SkillScanner.scan(directory: paths.personalSkillsDir, source: .personal, lock: lock, lockScope: paths.sharedSkillsDir)
        let shared = SkillScanner.scan(directory: paths.sharedSkillsDir, source: .shared, lock: lock, lockScope: paths.sharedSkillsDir)
        let pluginResult = PluginRegistry.loadPlugins(paths: paths, enabledPlugins: enabled)

        // A shared skill symlinked into ~/.claude/skills is the same skill —
        // show it once, where Claude Code sees it (spec §6.5 duplicate rule).
        let personalResolved = Set(personal.skills.map {
            $0.directory.resolvingSymlinksInPath().path
        })
        let unconnectedShared = shared.skills.filter {
            !personalResolved.contains($0.directory.resolvingSymlinksInPath().path)
        }

        return Inventory(
            personalSkills: personal.skills,
            sharedSkills: unconnectedShared,
            plugins: pluginResult.plugins,
            issues: personal.issues + shared.issues + pluginResult.issues)
    }
}
