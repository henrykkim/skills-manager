import Foundation

/// One record from ~/.agents/.skill-lock.json — provenance the skills.sh
/// installer wrote when it added a shared skill.
public struct SkillLockEntry: Sendable, Equatable {
    public let sourceLabel: String?   // "owner/repo"
    public let sourceURL: URL?        // cloneable URL with a trailing ".git" removed
    public let installedAt: Date?
    public let updatedAt: Date?

    public init(sourceLabel: String?, sourceURL: URL?, installedAt: Date?, updatedAt: Date?) {
        self.sourceLabel = sourceLabel
        self.sourceURL = sourceURL
        self.installedAt = installedAt
        self.updatedAt = updatedAt
    }
}

/// Lookup keyed by skill folder name. Lenient: any problem reading the file
/// means an empty lock — the skills themselves are still perfectly valid.
public struct SkillLock: Sendable {
    private let entries: [String: SkillLockEntry]

    public static let empty = SkillLock(entries: [:])

    public init(entries: [String: SkillLockEntry]) {
        self.entries = entries
    }

    public subscript(folderName: String) -> SkillLockEntry? { entries[folderName] }

    public static func load(file: URL) -> SkillLock {
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let skills = json["skills"] as? [String: Any] else {
            return .empty
        }
        var entries: [String: SkillLockEntry] = [:]
        for (folder, value) in skills {
            guard let record = value as? [String: Any] else { continue }
            entries[folder] = SkillLockEntry(
                sourceLabel: record["source"] as? String,
                sourceURL: GitURL.browsable(record["sourceUrl"] as? String),
                installedAt: ISODate.parse(record["installedAt"] as? String),
                updatedAt: ISODate.parse(record["updatedAt"] as? String))
        }
        return SkillLock(entries: entries)
    }
}

/// Turns the URLs Claude Code and skills.sh store into something a browser can open.
enum GitURL {
    /// "https://github.com/o/r.git" → https://github.com/o/r ; nil/empty → nil.
    static func browsable(_ raw: String?) -> URL? {
        guard var string = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else {
            return nil
        }
        if string.hasSuffix(".git") { string.removeLast(4) }
        guard let url = URL(string: string), url.scheme == "https" || url.scheme == "http" else {
            return nil
        }
        return url
    }

    /// "owner/repo" (GitHub shorthand) → https://github.com/owner/repo
    static func github(repo: String?) -> URL? {
        guard let repo, repo.split(separator: "/").count == 2 else { return nil }
        return URL(string: "https://github.com/\(repo)")
    }
}
