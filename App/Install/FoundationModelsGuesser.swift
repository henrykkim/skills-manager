import Foundation
import SkillsManagerCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Tier-2 recognition (spec §4.2): on-device Apple model, only for text the
/// deterministic parser rejected. Output is validated before becoming an intent.
struct FoundationModelsGuesser: IntentGuesser {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    func guess(_ text: String) async -> InstallIntent {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *), Self.isAvailable else { return .unrecognized(diagnosis: Diagnosis.generic) }
        let session = LanguageModelSession(instructions: """
            You read text a user pasted into an installer for AI coding skills and extract what to install.
            skills-repo = a GitHub repository of skills installed with `npx skills add owner/repo`.
            plugin = a Claude Code plugin installed with `/plugin install name@marketplace` or `claude plugin install`.
            Anything else is unknown. Never invent names that are not in the text.
            """)
        let guessed: GuessedIntent? = await withTaskGroup(of: GuessedIntent?.self) { group in
            group.addTask { try? await session.respond(to: "Input:\n\(text)", generating: GuessedIntent.self).content }
            group.addTask { try? await Task.sleep(for: .seconds(5)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let g = guessed else { return .unrecognized(diagnosis: Diagnosis.generic) }
        return Self.validate(g)
        #else
        return .unrecognized(diagnosis: Diagnosis.generic)
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    @Generable
    struct GuessedIntent {
        @Guide(description: "One of: skills-repo, plugin, unknown") var kind: String
        @Guide(description: "GitHub owner/repo exactly as written in the text, else empty") var repo: String
        @Guide(description: "Marketplace name for a plugin install, else empty") var marketplace: String
        @Guide(description: "Plugin name for a plugin install, else empty") var plugin: String
        @Guide(description: "Skill names explicitly named in the text, else empty") var skills: [String]
    }

    @available(macOS 26, *)
    static func validate(_ g: GuessedIntent) -> InstallIntent {
        let ident = #"^[A-Za-z0-9_.-]+$"#
        func ok(_ s: String) -> Bool { s.range(of: ident, options: .regularExpression) != nil }
        switch g.kind {
        case "skills-repo":
            let parts = g.repo.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2, parts.allSatisfy(ok) else { return .unrecognized(diagnosis: Diagnosis.generic) }
            let only = g.skills.filter(ok)
            return .skillsRepo(owner: parts[0], repo: parts[1], subpath: nil, onlySkills: only.isEmpty ? nil : only)
        case "plugin":
            guard ok(g.plugin), ok(g.marketplace) else { return .unrecognized(diagnosis: Diagnosis.generic) }
            return .plugin(name: g.plugin, marketplace: g.marketplace, marketplaceSource: nil)
        default:
            return .unrecognized(diagnosis: Diagnosis.generic)
        }
    }
    #endif
}
