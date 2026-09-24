import Foundation

public struct ScanResult: Sendable {
    public var skills: [Skill]
    public var issues: [ParseIssue]

    public init(skills: [Skill] = [], issues: [ParseIssue] = []) {
        self.skills = skills
        self.issues = issues
    }
}

public enum SkillScanner {
    public enum One {
        case skill(Skill)
        case issue(ParseIssue)
        case notASkill          // folder has no SKILL.md
    }

    /// Scans a directory whose children are skill folders (each holding SKILL.md).
    /// A missing directory is normal (not every machine has every source) — empty result.
    public static func scan(directory: URL, source: SkillSource, lock: SkillLock = .empty,
                            lockScope: URL? = nil, skipOnlineOnly: Bool = false) -> ScanResult {
        let fm = FileManager.default
        var result = ScanResult()
        guard let entries = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return result }

        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            // fileExists(atPath:isDirectory:) follows symlinks — symlinked skill
            // folders (how installers connect agents) must scan like real ones.
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: entry.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            switch scanOne(folder: entry, source: source, lock: lock, lockScope: lockScope,
                           skipOnlineOnly: skipOnlineOnly) {
            case .skill(let skill): result.skills.append(skill)
            case .issue(let issue): result.issues.append(issue)
            case .notASkill:
                result.issues.append(ParseIssue(location: entry, detail: "No SKILL.md inside this folder"))
            }
        }
        return result
    }

    /// Reads one skill folder.
    public static func scanOne(folder entry: URL, source: SkillSource, isEnabled: Bool = true,
                               lock: SkillLock = .empty, lockScope: URL? = nil,
                               skipOnlineOnly: Bool = false) -> One {
        let fm = FileManager.default
        let skillFile = entry.appending(path: "SKILL.md")
        guard fm.fileExists(atPath: skillFile.path) else { return .notASkill }
        if skipOnlineOnly && !LocalFile.isDownloaded(skillFile) {
            return .issue(ParseIssue(location: skillFile,
                                     detail: "Stored online only — download it in Finder to see it here"))
        }
        guard let text = try? String(contentsOf: skillFile, encoding: .utf8) else {
            return .issue(ParseIssue(location: skillFile, detail: "File can't be read as text"))
        }
        switch FrontmatterParser.parse(text) {
        case .malformed(let reason):
            return .issue(ParseIssue(location: skillFile, detail: reason))
        case .missing:
            return .issue(ParseIssue(location: skillFile, detail: "Missing the --- name/description --- header"))
        case .parsed(let fm2, _):
            let modified = (try? skillFile.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            let resolved = URL(fileURLWithPath: entry.path).resolvingSymlinksInPath().path
            let scopeOK = lockScope.map { resolved.hasPrefix($0.resolvingSymlinksInPath().path + "/") } ?? true
            let lockEntry = scopeOK ? lock[entry.lastPathComponent] : nil
            return .skill(Skill(
                folderName: entry.lastPathComponent,
                displayName: fm2.name ?? entry.lastPathComponent,
                summary: fm2.description,
                argumentHint: fm2.argumentHint,
                userInvocable: fm2.userInvocable ?? true,
                modelInvocable: !(fm2.disableModelInvocation ?? false),
                whenToUse: fm2.whenToUse,
                source: source,
                directory: entry,
                lastModified: modified,
                sourceURL: lockEntry?.sourceURL,
                sourceLabel: lockEntry?.sourceLabel,
                installedAt: lockEntry?.installedAt,
                updatedAt: lockEntry?.updatedAt,
                isEnabled: isEnabled))
        }
    }
}
