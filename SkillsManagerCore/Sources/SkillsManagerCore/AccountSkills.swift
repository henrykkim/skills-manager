import Foundation

public struct AccountSkillsResult: Sendable {
    public var skills: [Skill] = []
    public var lastSynced: Date?
    public var issues: [ParseIssue] = []
}

/// The Claude desktop app's local copy of the skills in the user's Claude
/// account: skills-plugin/<account>/<org>/{manifest.json, skills/<name>/SKILL.md}.
public enum AccountSkills {
    struct Manifest: Decodable {
        let lastUpdated: Double?
        let skills: [Entry]
        struct Entry: Decodable {
            let name: String
            let creatorType: String?
            let enabled: Bool?
        }
    }

    public static func load(dir: URL) -> AccountSkillsResult {
        let fm = FileManager.default
        func children(_ u: URL) -> [URL] {
            (try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        }
        var result = AccountSkillsResult()
        var seen = Set<String>()
        for a in children(dir).sorted(by: { $0.path < $1.path }) {
            for b in children(a).sorted(by: { $0.path < $1.path }) {
                let manifestFile = b.appending(path: "manifest.json")
                guard fm.fileExists(atPath: manifestFile.path) else { continue }
                guard let data = try? Data(contentsOf: manifestFile),
                      let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
                    result.issues.append(ParseIssue(
                        location: manifestFile,
                        detail: "Couldn't read your Claude account's skill list. Claude account skills may be missing."))
                    continue
                }
                if let ms = manifest.lastUpdated {
                    let date = Date(timeIntervalSince1970: ms / 1000)
                    result.lastSynced = max(result.lastSynced ?? date, date)
                }
                for entry in manifest.skills where seen.insert(entry.name).inserted {
                    let folder = b.appending(path: "skills/\(entry.name)", directoryHint: .isDirectory)
                    let source = SkillSource.account(userMade: entry.creatorType == "user")
                    switch SkillScanner.scanOne(folder: folder, source: source, isEnabled: entry.enabled ?? true) {
                    case .skill(let skill): result.skills.append(skill)
                    case .issue(let issue): result.issues.append(issue)
                    case .notASkill: break     // listed but not synced yet — not the user's problem
                    }
                }
            }
        }
        result.skills.sort { $0.folderName < $1.folderName }
        return result
    }
}
