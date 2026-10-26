import Foundation
import Observation
import SkillsManagerCore

/// Checks the user's skill sources for new skills, persists the result, and
/// installs chosen skills one at a time. Pure scheduling arithmetic lives in
/// `SourceUpdatesRules`.
@MainActor
@Observable
final class SourceUpdatesModel {
    enum RowState: Equatable { case idle, installing, failed(message: String, log: String) }
    enum Trigger { case launch, timer, manual }

    private(set) var findings: [SourceFinding]
    private(set) var isChecking = false
    private(set) var lastCompleted: Date?
    private(set) var lastRunFailed = false
    private(set) var dismissedUntilNew: Bool
    private(set) var rowStates: [String: RowState] = [:]
    private(set) var isInstalling = false

    var isVisible: Bool {
        SourceUpdatesRules.isVisible(findings: findings, dismissedUntilNew: dismissedUntilNew)
    }
    var newSkillCount: Int { findings.reduce(0) { $0 + $1.skills.count } }

    /// Called with (title, body) when a completed check has unannounced skills.
    var onAnnounce: (@MainActor (String, String) -> Void)?

    @ObservationIgnored private let paths: ClaudePaths
    @ObservationIgnored private let github: GitHubClient
    @ObservationIgnored private let installer: Installer
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var timer: Task<Void, Never>?

    private enum Key {
        static let findings = "sourceCheckLastFindings"
        static let lastStarted = "sourceCheckLastStarted"
        static let lastCompleted = "sourceCheckLastCompleted"
        static let dismissed = "sourceCheckDismissedUntilNew"
        static let notified = "sourceCheckNotifiedSkills"
    }

    init(paths: ClaudePaths, github: GitHubClient, runner: CommandRunner,
         defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = Date.init) {
        self.paths = paths
        self.github = github
        self.installer = Installer(runner: runner)
        self.defaults = defaults
        self.now = now
        if let data = defaults.data(forKey: Key.findings),
           let saved = try? JSONDecoder().decode([SourceFinding].self, from: data) {
            findings = saved
        } else {
            findings = []
        }
        lastCompleted = defaults.object(forKey: Key.lastCompleted) as? Date
        dismissedUntilNew = defaults.bool(forKey: Key.dismissed)
    }

    deinit { timer?.cancel() }

    // MARK: scheduling

    func start() {
        checkIfDue(.launch)
        guard timer == nil else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
                guard !Task.isCancelled else { return }
                self?.checkIfDue(.timer)
            }
        }
    }

    func checkIfDue(_ trigger: Trigger) {
        guard !isChecking else { return }
        let current = now()
        switch trigger {
        case .launch, .timer:
            guard SourceUpdatesRules.isDailyDue(lastCompleted: lastCompleted, now: current) else { return }
        case .manual:
            let started = defaults.object(forKey: Key.lastStarted) as? Date
            guard SourceUpdatesRules.isManualAllowed(lastStarted: started, now: current) else { return }
        }
        isChecking = true
        defaults.set(current, forKey: Key.lastStarted)
        generation += 1
        let gen = generation
        let paths = self.paths
        let github = self.github
        Task { [weak self] in
            let result = await Task.detached {
                let lock = SkillLock.load(file: paths.agentsLockFile)
                let installed = InstalledSkillFolders.names(paths: paths)
                return await SourceCheck(github: github).run(lock: lock, installedFolders: installed)
            }.value
            self?.apply(result, generation: gen)
        }
    }

    private func apply(_ result: SourceCheckResult, generation gen: Int) {
        guard gen == generation else { return }
        isChecking = false
        lastCompleted = SourceUpdatesRules.nextLastCompleted(previous: lastCompleted, result: result, now: now())
        if let lastCompleted { defaults.set(lastCompleted, forKey: Key.lastCompleted) }
        guard result.completed else {
            lastRunFailed = true
            return
        }
        lastRunFailed = false
        // An install may have finished while the check ran; don't resurrect skills that are now present.
        let installedNow = InstalledSkillFolders.names(paths: paths)
        findings = result.findings.compactMap { f in
            let rest = f.skills.filter { !installedNow.contains($0.folder) }
            return rest.isEmpty ? nil : SourceFinding(owner: f.owner, repo: f.repo, skills: rest)
        }
        persistFindings()
        let liveKeys = Set(findings.flatMap { f in f.skills.map { f.key($0) } })
        rowStates = rowStates.filter { liveKeys.contains($0.key) }
        let notifiedList = defaults.stringArray(forKey: Key.notified) ?? []
        let notified = Set(notifiedList)
        let unannounced = SourceUpdatesRules.unannouncedKeys(findings: findings, notified: notified)
        dismissedUntilNew = SourceUpdatesRules.dismissedAfterCheck(
            previouslyDismissed: dismissedUntilNew, unannounced: unannounced)
        defaults.set(dismissedUntilNew, forKey: Key.dismissed)
        if !unannounced.isEmpty {
            defaults.set(notifiedList + unannounced, forKey: Key.notified)
        }
        if let text = SourceUpdatesRules.notificationText(findings: findings, unannounced: unannounced) {
            onAnnounce?(text.title, text.body)
        }
    }

    // MARK: install

    func install(_ skill: NewSkill, from finding: SourceFinding) async {
        await run(finding: finding, skills: [skill])
    }

    func installAll(_ finding: SourceFinding) async {
        await run(finding: finding, skills: finding.skills)
    }

    private func run(finding: SourceFinding, skills: [NewSkill]) async {
        guard !isInstalling, !skills.isEmpty else { return }
        isInstalling = true
        let keys = skills.map { finding.key($0) }
        for key in keys { rowStates[key] = .installing }
        let preview = InstallPreview(
            kind: .skillsRepo, title: finding.id, summary: nil, authorName: finding.owner,
            authorURL: nil, sourceURL: finding.htmlURL, skills: [], marketplaceNote: nil,
            isPluginInstalled: false, owner: finding.owner, repo: finding.repo,
            pluginName: nil, marketplace: nil, marketplaceSource: nil)
        let outcome = await installer.install(preview, selectedFolders: skills.map(\.folder))
        isInstalling = false
        switch outcome {
        case .success:
            let done = Set(skills.map(\.folder))
            findings = findings.compactMap { f in
                guard f.id == finding.id else { return f }
                let rest = f.skills.filter { !done.contains($0.folder) }
                return rest.isEmpty ? nil : SourceFinding(owner: f.owner, repo: f.repo, skills: rest)
            }
            for key in keys { rowStates[key] = nil }
            persistFindings()
        case .failure(let message, let log):
            for key in keys { rowStates[key] = .failed(message: message, log: log) }
        }
    }

    func dismiss() {
        dismissedUntilNew = true
        defaults.set(true, forKey: Key.dismissed)
    }

    private func persistFindings() {
        if let data = try? JSONEncoder().encode(findings) { defaults.set(data, forKey: Key.findings) }
    }
}
