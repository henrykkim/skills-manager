import Foundation
import Observation
import SkillsManagerCore

/// Orchestrates paste → recognize → verify → install for the Install sheet.
/// Every network/process step is cancellable; a newer paste always wins.
@MainActor
@Observable
final class InstallSheetModel {
    enum Phase: Equatable {
        case idle
        case looking
        case preview(InstallPreview)
        case unrecognized(String)
        case installing(step: String)
        case success(log: String, installed: [PreviewSkill])
        case failure(message: String, log: String)
    }

    var text: String = "" { didSet { if text != oldValue { scheduleRecognition() } } }
    private(set) var phase: Phase = .idle
    var selected: Set<String> = []
    private(set) var missingTool: String?

    private let paths: ClaudePaths
    private let resolver: InstallResolver
    private let guesser: IntentGuesser
    private let installer: Installer
    private let runner: CommandRunner
    private var recognition: Task<Void, Never>?
    private var generation = 0

    init(paths: ClaudePaths, github: GitHubClient, guesser: IntentGuesser, runner: CommandRunner) {
        self.paths = paths
        self.resolver = InstallResolver(github: github, paths: paths)
        self.guesser = guesser
        self.installer = Installer(runner: runner)
        self.runner = runner
    }

    // MARK: recognition

    private func scheduleRecognition() {
        recognition?.cancel()
        generation += 1
        let gen = generation
        let input = text
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { phase = .idle; return }
        phase = .looking
        recognition = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled, gen == self.generation else { return }
            var intent = InstallIntentParser.parse(input)
            if case .unrecognized = intent {
                intent = await self.guesser.guess(input)
            }
            guard !Task.isCancelled, gen == self.generation else { return }
            if case .unrecognized(let diagnosis) = intent { self.phase = .unrecognized(diagnosis); return }
            do {
                let preview = try await self.resolver.resolve(intent)
                guard !Task.isCancelled, gen == self.generation else { return }
                self.selected = Set(preview.skills.filter(\.isPreselected).map(\.folder))
                self.phase = .preview(preview)
                await self.checkTools(for: preview.kind)
            } catch let error as InstallError {
                guard gen == self.generation else { return }
                self.phase = .unrecognized(Self.sentence(for: error))
            } catch {
                guard gen == self.generation else { return }
                self.phase = .unrecognized("Couldn't reach GitHub. Check your connection.")
            }
        }
    }

    static func sentence(for error: InstallError) -> String {
        switch error {
        case .repoNotFound: "That GitHub repository doesn't exist or is private."
        case .noSkills: "That repository doesn't contain any skills (no SKILL.md files)."
        case .rateLimited: "GitHub is rate-limiting requests from this Mac. Try again in a few minutes."
        case .network: "Couldn't reach GitHub. Check your connection."
        case .other(let s): s
        }
    }

    // MARK: preconditions

    func checkTools(for kind: PreviewKind) async {
        let tool = kind == .skillsRepo ? "npx" : "claude"
        let present = await ToolCheck.resolves(tool, runner: runner)
        missingTool = present ? nil : (kind == .skillsRepo
            ? "Node.js is needed to install skills. Install it from nodejs.org, then try again."
            : "Claude Code's command-line tool wasn't found.")
    }

    // MARK: derived

    var preview: InstallPreview? { if case .preview(let p) = phase { p } else { nil } }

    var plannedCommands: [String] {
        guard let preview else { return [] }
        return installer.plan(preview, selectedFolders: orderedSelection(preview)).map { $0.joined(separator: " ") }
    }

    var canInstall: Bool {
        guard let preview, missingTool == nil else { return false }
        switch preview.kind {
        case .skillsRepo: return !selected.isEmpty
        case .plugin: return !preview.isPluginInstalled
        }
    }

    private func orderedSelection(_ preview: InstallPreview) -> [String] {
        preview.skills.map(\.folder).filter { selected.contains($0) }
    }

    // MARK: install

    func install() async {
        guard let preview, canInstall else { return }
        let folders = orderedSelection(preview)
        phase = .installing(step: preview.kind == .skillsRepo ? "Downloading skills…" : "Installing plugin…")
        switch await installer.install(preview, selectedFolders: folders) {
        case .failure(let message, let log):
            phase = .failure(message: message, log: log)
        case .success(let log):
            let installed = await waitForInstalled(preview, folders: folders)
            phase = .success(log: log, installed: installed)
        }
    }

    /// Spec §6: the cheat sheet is read from disk after install. Falls back to
    /// the predicted rows if nothing appears within 3 s.
    private func waitForInstalled(_ preview: InstallPreview, folders: [String]) async -> [PreviewSkill] {
        guard preview.kind == .skillsRepo else { return [] }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            let present = folders.allSatisfy {
                FileManager.default.fileExists(atPath: paths.personalSkillsDir.appending(path: $0).path)
            }
            if present { break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return preview.skills.filter { folders.contains($0.folder) }
    }

    func retry() { if let preview { phase = .preview(preview) } }

    func reset() {
        recognition?.cancel()
        generation += 1
        text = ""
        selected = []
        missingTool = nil
        phase = .idle
    }

    /// Cancels any in-flight recognition/resolve work without disturbing what's
    /// already on screen (unlike `reset()`, which also clears text/phase).
    /// Bumping `generation` makes any already-running closure's checks no-op.
    func cancel() {
        recognition?.cancel()
        generation += 1
    }
}
