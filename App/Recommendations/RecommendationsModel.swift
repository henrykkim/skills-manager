import Foundation
import Observation
import SkillsManagerCore

/// Drives the Recommended sheet (spec §5–6): resolves every catalog item
/// through the Install box's resolver, then installs the selected ones in
/// catalog order. One failure never stops the rest.
@MainActor
@Observable
final class RecommendationsModel {
    enum ItemState: Equatable {
        case checking
        case ready(InstallPreview)
        case installed
        case unavailable(String)
        case installing
        case done
        case failed(message: String, log: String)
    }

    let catalog: RecommendationsCatalog
    private(set) var states: [String: ItemState] = [:]
    var selected: Set<String> = []
    private(set) var missingTool: String?
    private(set) var isInstalling = false
    private(set) var finished = false
    private(set) var isResolving = false

    private let resolver: InstallResolver
    private let installer: Installer
    private let runner: CommandRunner
    private var resolution: Task<Void, Never>?
    private var generation = 0

    init(catalog: RecommendationsCatalog, paths: ClaudePaths, github: GitHubClient, runner: CommandRunner) {
        self.catalog = catalog
        self.resolver = InstallResolver(github: github, paths: paths)
        self.installer = Installer(runner: runner)
        self.runner = runner
    }

    // MARK: resolution

    /// Re-resolves every item and clears the selection on every call; the view
    /// must call it once per showing. A newer call wins, exactly like
    /// `InstallSheetModel`'s generation counter.
    func start() {
        // A re-presented sheet must not abandon a running install.
        guard !isInstalling else { return }
        resolution?.cancel()
        generation += 1
        let gen = generation
        finished = false
        isInstalling = false
        isResolving = true
        selected = []
        missingTool = nil
        for item in catalog.items { states[item.id] = .checking }
        resolution = Task { [weak self] in
            guard let self else { return }
            await withTaskGroup(of: (String, ItemState).self) { group in
                for item in self.catalog.items {
                    group.addTask { [resolver = self.resolver] in
                        let intent = InstallIntentParser.parse(item.source)
                        if case .unrecognized(let diagnosis) = intent { return (item.id, .unavailable(diagnosis)) }
                        do {
                            let preview = try await resolver.resolve(intent)
                            return (item.id, RecommendationPlan.isInstalled(preview) ? .installed : .ready(preview))
                        } catch let error as InstallError {
                            return (item.id, .unavailable(InstallSheetModel.sentence(for: error)))
                        } catch {
                            return (item.id, .unavailable(InstallSheetModel.sentence(for: .network(error.localizedDescription))))
                        }
                    }
                }
                for await (id, state) in group {
                    guard !Task.isCancelled, gen == self.generation else { return }
                    self.states[id] = state
                    if case .ready = state { self.selected.insert(id) }
                }
            }
            guard gen == self.generation else { return }
            await self.checkTools(generation: gen)
            guard gen == self.generation else { return }
            self.isResolving = false
        }
    }

    /// Skills repos need `npx`; plugins need `claude`. Only tools the
    /// selectable items actually use are checked, with the Install box's copy.
    private func checkTools(generation gen: Int) async {
        let kinds = Set(readyPreviews.values.map(\.kind))
        if kinds.contains(.skillsRepo), !(await ToolCheck.resolves("npx", runner: runner)) {
            guard gen == generation else { return }
            missingTool = "Node.js is needed to install skills. Install it from nodejs.org, then try again."
            return
        }
        if kinds.contains(.plugin), !(await ToolCheck.resolves("claude", runner: runner)) {
            guard gen == generation else { return }
            missingTool = "Claude Code's command-line tool wasn't found. Install Claude Code, then try again."
            return
        }
        guard gen == generation else { return }
        missingTool = nil
    }

    // MARK: derived

    private var readyPreviews: [String: InstallPreview] {
        states.reduce(into: [:]) { acc, pair in if case .ready(let p) = pair.value { acc[pair.key] = p } }
    }

    var canInstall: Bool {
        !isResolving && !isInstalling && !finished && missingTool == nil
            && !RecommendationPlan.make(items: catalog.items, previews: readyPreviews, selected: selected).isEmpty
    }

    var selectableIDs: [String] { catalog.items.map(\.id).filter { if case .ready = states[$0] { true } else { false } } }
    var allSelected: Bool { !selectableIDs.isEmpty && selectableIDs.allSatisfy { selected.contains($0) } }
    func selectAll() { selected.formUnion(selectableIDs) }
    func deselectAll() { selected.subtract(selectableIDs) }

    /// Status line under a ready row, e.g. "3 skills" or "Plugin from claude-plugins-official".
    func summary(for preview: InstallPreview) -> String {
        switch preview.kind {
        case .plugin:
            return "Plugin from \(preview.marketplace ?? "a marketplace")"
        case .skillsRepo:
            let n = RecommendationPlan.folders(toInstallFrom: preview).count
            let installed = preview.skills.filter { $0.isValid && $0.isInstalled }.count
            let base = n == 1 ? "1 skill" : "\(n) skills"
            return installed > 0 ? "\(base) (\(installed) already installed)" : base
        }
    }

    // MARK: install

    func install() async {
        guard canInstall else { return }
        let steps = RecommendationPlan.make(items: catalog.items, previews: readyPreviews, selected: selected)
        let gen = generation
        isInstalling = true
        for step in steps {
            states[step.itemID] = .installing
            let outcome = await installer.install(step.preview, selectedFolders: step.folders)
            guard gen == generation else { return }
            switch outcome {
            case .success:
                states[step.itemID] = .done
            case .failure(let message, let log):
                states[step.itemID] = .failed(message: message, log: log)
            }
        }
        guard gen == generation else { return }
        isInstalling = false
        finished = true
    }

    func reset() {
        resolution?.cancel()
        generation += 1
        states = [:]
        selected = []
        missingTool = nil
        isInstalling = false
        isResolving = false
        finished = false
    }
}
