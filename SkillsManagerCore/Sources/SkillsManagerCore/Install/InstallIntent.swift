import Foundation

/// What the user pasted, once recognized. Verified by InstallResolver before
/// anything is shown; never acted on directly.
public enum InstallIntent: Sendable, Equatable {
    case skillsRepo(owner: String, repo: String, subpath: String?, onlySkills: [String]?)
    case plugin(name: String, marketplace: String, marketplaceSource: String?)
    case unrecognized(diagnosis: String)
}

/// Typed failures that map 1:1 to the plain-English sentences in spec §5/§7.
public enum InstallError: Error, Sendable, Equatable {
    case repoNotFound
    case noSkills
    case rateLimited
    case network(String)
    case other(String)
}

/// Spec §4.3 — exact sentences for unrecognized input.
public enum Diagnosis {
    public static func packageManager(_ tool: String) -> String {
        "That looks like a \(tool) command, not a skill or plugin."
    }
    public static let nonGitHubURL = "Only GitHub and skills.sh links are supported right now."
    public static let generic = "Couldn't find a skill or plugin in that. Try pasting just the link or the install command."
}

/// Tier-1 recognition (spec §4.1). Pure, deterministic, order-sensitive.
public enum InstallIntentParser {
    private static let ident = #"[A-Za-z0-9_.-]+"#

    public static func parse(_ raw: String) -> InstallIntent {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .unrecognized(diagnosis: Diagnosis.generic) }

        if let plugin = parsePlugin(text) { return plugin }
        if let npx = parseNpx(text) { return npx }
        if let site = parseSkillsSh(text) { return site }
        if let gh = parseGitHub(text) { return gh }
        if let bare = parseBareShorthand(text) { return bare }
        return .unrecognized(diagnosis: diagnose(text))
    }

    // MARK: shapes

    private static func parsePlugin(_ text: String) -> InstallIntent? {
        // "/plugin install p@m" or "claude plugin install p@m"
        let install = try! NSRegularExpression(pattern: #"(?:^|\s)(?:/plugin|claude\s+plugin)\s+install\s+(\#(ident))@(\#(ident))"#)
        guard let m = install.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let name = text[m.range(at: 1)], let market = text[m.range(at: 2)] else { return nil }
        let add = try! NSRegularExpression(pattern: #"(?:^|\s)(?:/plugin|claude\s+plugin)\s+marketplace\s+add\s+(\S+)"#)
        let source = add.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
            .flatMap { text[$0.range(at: 1)] }
        return .plugin(name: name, marketplace: market, marketplaceSource: source)
    }

    private static func parseNpx(_ text: String) -> InstallIntent? {
        let re = try! NSRegularExpression(pattern: #"npx\s+(?:-y\s+)?skills\s+add\s+(\S+)((?:\s+(?:--skill|-s)\s+[^\s`]+)*)"#)
        guard let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let ref = text[m.range(at: 1)] else { return nil }
        guard let (owner, repo) = ownerRepo(fromRef: ref.trimmingCharacters(in: CharacterSet(charactersIn: "`'\""))) else { return nil }
        var only: [String]?
        if let flags = text[m.range(at: 2)] {
            let skillRe = try! NSRegularExpression(pattern: #"(?:--skill|-s)\s+([^\s`]+)"#)
            if let sm = skillRe.firstMatch(in: flags, range: NSRange(flags.startIndex..., in: flags)),
               let list = flags[sm.range(at: 1)] {
                only = list.split(separator: ",").map { String($0) }
            }
        }
        return .skillsRepo(owner: owner, repo: repo, subpath: nil, onlySkills: only)
    }

    private static func parseSkillsSh(_ text: String) -> InstallIntent? {
        let re = try! NSRegularExpression(pattern: #"https?://(?:www\.)?skills\.sh/(\#(ident))/(\#(ident))(?:/(\#(ident)))?"#)
        guard let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let owner = text[m.range(at: 1)], let repo = text[m.range(at: 2)] else { return nil }
        let skill = text[m.range(at: 3)]
        return .skillsRepo(owner: owner, repo: repo, subpath: nil, onlySkills: skill.map { [$0] })
    }

    private static func parseGitHub(_ text: String) -> InstallIntent? {
        let re = try! NSRegularExpression(pattern: #"https?://(?:www\.)?github\.com/(\#(ident))/(\#(ident))(?:/tree/[^/\s`]+/([^\s`]+))?"#)
        guard let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let owner = text[m.range(at: 1)], var repo = text[m.range(at: 2)] else { return nil }
        if repo.hasSuffix(".git") { repo.removeLast(4) }
        let path = text[m.range(at: 3)]?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let last = path?.split(separator: "/").last.map(String.init)
        return .skillsRepo(owner: owner, repo: repo, subpath: path, onlySkills: last.map { [$0] })
    }

    private static func parseBareShorthand(_ text: String) -> InstallIntent? {
        let re = try! NSRegularExpression(pattern: #"^\s*(\#(ident))/(\#(ident))\s*$"#, options: [.anchorsMatchLines])
        guard let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let owner = text[m.range(at: 1)], let repo = text[m.range(at: 2)] else { return nil }
        return .skillsRepo(owner: owner, repo: repo, subpath: nil, onlySkills: nil)
    }

    // MARK: helpers

    /// "o/r", "github.com/o/r", or a GitHub URL → (o, r)
    private static func ownerRepo(fromRef ref: String) -> (String, String)? {
        var s = ref
        for prefix in ["https://", "http://", "www.", "github.com/"] where s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
        if s.hasPrefix("github.com/") { s.removeFirst("github.com/".count) }
        if s.hasSuffix(".git") { s.removeLast(4) }
        let parts = s.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    private static func diagnose(_ text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("brew install") { return Diagnosis.packageManager("Homebrew") }
        if lower.contains("npm install") || lower.contains("npm i ") { return Diagnosis.packageManager("npm") }
        if lower.contains("pip install") || lower.contains("pip3 install") { return Diagnosis.packageManager("pip") }
        if lower.contains("http://") || lower.contains("https://") { return Diagnosis.nonGitHubURL }
        return Diagnosis.generic
    }
}

private extension String {
    subscript(_ range: NSRange) -> String? {
        guard range.location != NSNotFound, let r = Range(range, in: self) else { return nil }
        return String(self[r])
    }
}
