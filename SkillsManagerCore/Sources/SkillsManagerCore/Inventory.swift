import Foundation

/// Everything the app knows, loaded in one synchronous pass (callers move it
/// off the main thread). The filesystem is the source of truth — reload = re-scan.
public struct Inventory: Sendable {
    public var personalSkills: [Skill]
    public var sharedSkills: [Skill]
    public var plugins: [Plugin]                 // user scope
    public var issues: [ParseIssue]
    public var projects: [Project] = []
    public var projectSkills: [Skill] = []
    public var projectPlugins: [Plugin] = []
    public var coworkPlugins: [Plugin] = []
    public var accountSkills: [Skill] = []
    public var accountLastSynced: Date?
    public var notes: [NoteFolder] = []
    public var library = Library()

    public init(personalSkills: [Skill] = [], sharedSkills: [Skill] = [],
                plugins: [Plugin] = [], issues: [ParseIssue] = []) {
        self.personalSkills = personalSkills
        self.sharedSkills = sharedSkills
        self.plugins = plugins
        self.issues = issues
    }

    /// Each project's .claude folder, for the file watcher.
    public var projectWatchTargets: [URL] {
        projects.map { $0.root.appending(path: ".claude", directoryHint: .isDirectory) }
    }

    /// `includeProjects: false` skips everything that can trigger macOS
    /// folder-access prompts, until the user has seen the first-run note (spec §5.5).
    public static func load(paths: ClaudePaths, addedFolders: [URL] = [], includeProjects: Bool = true) -> Inventory {
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

        var inv = Inventory(
            personalSkills: personal.skills,
            sharedSkills: unconnectedShared,
            plugins: pluginResult.plugins,
            issues: personal.issues + shared.issues + pluginResult.issues)

        // Claude account + Cowork plugins: the desktop app's own folder, no prompts.
        let account = AccountSkills.load(dir: paths.accountSkillsDir)
        inv.accountSkills = account.skills
        inv.accountLastSynced = account.lastSynced
        inv.issues += account.issues
        let cowork = CoworkPlugins.load(sessionsDir: paths.coworkSessionsDir)
        inv.coworkPlugins = cowork.plugins
        inv.issues += cowork.issues

        // Added folders: projects vs. notes.
        var addedProjects: [URL] = []
        for folder in addedFolders {
            switch NoteFolders.classify(folder) {
            case .project: addedProjects.append(folder)
            case .notes: if let n = NoteFolders.load(folder) { inv.notes.append(n) }
            case .neither:
                inv.issues.append(ParseIssue(location: folder,
                    detail: "This added folder no longer has Claude skills or markdown files."))
            }
        }

        if includeProjects {
            let discovery = ProjectSources.discover(paths: paths, addedProjects: addedProjects)
            inv.projects = discovery.projects
            inv.issues += discovery.issues
            for project in discovery.projects {
                let scan = ProjectScanner.scan(project, paths: paths)
                inv.projectSkills += scan.skills
                inv.projectPlugins += scan.plugins
                inv.issues += scan.issues
            }
        }

        inv.library = Library.build(
            personal: inv.personalSkills, project: inv.projectSkills, account: inv.accountSkills,
            plugins: inv.plugins + inv.projectPlugins + inv.coworkPlugins, projects: inv.projects)
        return inv
    }
}
