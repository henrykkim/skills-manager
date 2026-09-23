import Foundation

public enum InstallOutcome: Sendable, Equatable {
    case success(log: String)
    case failure(message: String, log: String)
}

/// Spec §7 — exact sentences keyed on what the tool printed.
public enum FailureCopy {
    public static func sentence(for result: CommandResult, marketplace: String?) -> String {
        if result.timedOut { return "The installer didn't finish in two minutes. Check your connection and try again." }
        let out = result.combinedOutput
        if out.contains("ENOTFOUND") || out.contains("Could not resolve host") { return "Couldn't reach GitHub. Check your connection." }
        if out.contains("Repository not found") || out.contains("404") { return "That repository doesn't exist or is private." }
        if out.contains("EACCES") || out.localizedCaseInsensitiveContains("permission denied") { return "macOS blocked writing to your skills folder." }
        if out.contains("not found in marketplace") { return "That plugin isn't in the \(marketplace ?? "") marketplace." }
        return "The installer reported a problem. Show details for what it said."
    }
}

/// Spec §6. Builds the exact commands, runs them in order, stops at the first failure.
public struct Installer: Sendable {
    public static let timeout: TimeInterval = 120
    private let runner: CommandRunner

    public init(runner: CommandRunner) { self.runner = runner }

    public func plan(_ preview: InstallPreview, selectedFolders: [String]) -> [[String]] {
        switch preview.kind {
        case .skillsRepo:
            guard let owner = preview.owner, let repo = preview.repo else { return [] }
            var argv = ["npx", "-y", "skills", "add", "\(owner)/\(repo)", "-g", "-y", "-a", "claude-code"]
            // `skills` reads -s as space-separated names up to the next flag, so
            // keep it last and pass one argv entry per folder (commas would be one name).
            if !selectedFolders.isEmpty { argv += ["-s"] + selectedFolders }
            return [argv]
        case .plugin:
            guard let name = preview.pluginName, let market = preview.marketplace else { return [] }
            var commands: [[String]] = []
            if preview.marketplaceNote != nil, let source = preview.marketplaceSource {
                commands.append(["claude", "plugin", "marketplace", "add", source])
            }
            commands.append(["claude", "plugin", "install", "\(name)@\(market)", "-y"])
            return commands
        }
    }

    public func install(_ preview: InstallPreview, selectedFolders: [String]) async -> InstallOutcome {
        var log = ""
        for argv in plan(preview, selectedFolders: selectedFolders) {
            let result = await runner.run(argv, timeout: Self.timeout)
            if !log.isEmpty { log += "\n" }
            log += result.combinedOutput
            guard result.status == 0, !result.timedOut else {
                return .failure(message: FailureCopy.sentence(for: result, marketplace: preview.marketplace), log: log)
            }
        }
        return .success(log: log)
    }
}

/// Tier-2 recognition hook (spec §4.2). The FoundationModels implementation lives
/// in the app target; Core only knows the protocol and a no-op.
public protocol IntentGuesser: Sendable {
    func guess(_ text: String) async -> InstallIntent
}

public struct NoopGuesser: IntentGuesser {
    public init() {}
    public func guess(_ text: String) async -> InstallIntent { .unrecognized(diagnosis: Diagnosis.generic) }
}
