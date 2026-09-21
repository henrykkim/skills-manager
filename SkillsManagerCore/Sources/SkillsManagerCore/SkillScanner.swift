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
    /// Scans a directory whose children are skill folders (each holding SKILL.md).
    /// A missing directory is normal (not every machine has every source) — empty result.
    public static func scan(directory: URL, source: SkillSource) -> ScanResult {
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
            let skillFile = entry.appending(path: "SKILL.md")
            guard fm.fileExists(atPath: skillFile.path) else {
                result.issues.append(ParseIssue(location: entry, detail: "No SKILL.md inside this folder"))
                continue
            }
            guard let text = try? String(contentsOf: skillFile, encoding: .utf8) else {
                result.issues.append(ParseIssue(location: skillFile, detail: "File can't be read as text"))
                continue
            }
            switch FrontmatterParser.parse(text) {
            case .malformed(let reason):
                result.issues.append(ParseIssue(location: skillFile, detail: reason))
            case .missing:
                result.issues.append(ParseIssue(location: skillFile, detail: "Missing the --- name/description --- header"))
            case .parsed(let fm2, _):
                let modified = (try? skillFile.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                result.skills.append(Skill(
                    folderName: entry.lastPathComponent,
                    displayName: fm2.name ?? entry.lastPathComponent,
                    summary: fm2.description,
                    argumentHint: fm2.argumentHint,
                    userInvocable: fm2.userInvocable ?? true,
                    modelInvocable: !(fm2.disableModelInvocation ?? false),
                    whenToUse: fm2.whenToUse,
                    source: source,
                    directory: entry,
                    lastModified: modified))
            }
        }
        return result
    }
}
