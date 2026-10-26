import Foundation

public struct NewSkill: Sendable, Codable, Equatable, Identifiable {
    public let folder: String
    public let name: String          // frontmatter name, else folder
    public let summary: String?      // frontmatter description
    public let path: String          // "skills/teardown/SKILL.md"
    public var id: String { folder }

    public init(folder: String, name: String, summary: String?, path: String) {
        self.folder = folder
        self.name = name
        self.summary = summary
        self.path = path
    }
}

public struct SourceFinding: Sendable, Codable, Equatable, Identifiable {
    public let owner: String
    public let repo: String
    public let skills: [NewSkill]    // sorted by folder
    public var id: String { "\(owner)/\(repo)" }

    public init(owner: String, repo: String, skills: [NewSkill]) {
        self.owner = owner
        self.repo = repo
        self.skills = skills
    }

    public var htmlURL: URL { URL(string: "https://github.com/\(owner)/\(repo)")! }

    /// https://github.com/o/r/tree/HEAD/<dir of path>
    public func skillURL(_ skill: NewSkill) -> URL {
        let dir = skill.path.split(separator: "/").dropLast().joined(separator: "/")
        return dir.isEmpty ? htmlURL : htmlURL.appending(path: "tree/HEAD/\(dir)")
    }

    /// "owner/repo#folder"
    public func key(_ skill: NewSkill) -> String { "\(owner)/\(repo)#\(skill.folder)" }
}

public struct SourceCheckResult: Sendable, Equatable {
    public let findings: [SourceFinding]  // only repos with ≥1 new skill, sorted by SkillRepo order
    public let completed: Bool            // false after .rateLimited or .network

    public init(findings: [SourceFinding], completed: Bool) {
        self.findings = findings
        self.completed = completed
    }
}

/// Diffs each source repo named in the lock file against what's installed.
public struct SourceCheck: Sendable {
    private let github: GitHubClient

    public init(github: GitHubClient) { self.github = github }

    public func run(lock: SkillLock, installedFolders: Set<String>) async -> SourceCheckResult {
        let known = installedFolders.union(lock.folderNames)
        var findings: [SourceFinding] = []
        for source in lock.sources {
            do {
                let skills = try await newSkills(in: source, known: known)
                if !skills.isEmpty {
                    findings.append(SourceFinding(owner: source.owner, repo: source.repo, skills: skills))
                }
            } catch let error as InstallError {
                switch error {
                case .rateLimited, .network:
                    return SourceCheckResult(findings: [], completed: false)
                case .repoNotFound, .noSkills, .other:
                    continue
                }
            } catch {
                continue
            }
        }
        return SourceCheckResult(findings: findings, completed: true)
    }

    private func newSkills(in source: SkillRepo, known: Set<String>) async throws -> [NewSkill] {
        let paths = try await github.treePaths(owner: source.owner, repo: source.repo, branch: "HEAD")
            .filter { $0 == "SKILL.md" || $0.hasSuffix("/SKILL.md") }
        var skills: [NewSkill] = []
        for path in paths {
            let folder = path == "SKILL.md"
                ? source.repo
                : String(path.dropLast("/SKILL.md".count).split(separator: "/").last ?? Substring(source.repo))
            if known.contains(folder) { continue }
            var name = folder
            var summary: String?
            do {
                let text = try await github.raw(owner: source.owner, repo: source.repo, branch: "HEAD", path: path)
                if case .parsed(let fm, _) = FrontmatterParser.parse(text) {
                    name = fm.name ?? folder
                    summary = fm.description
                }
            } catch let error as InstallError {
                switch error {
                case .rateLimited, .network: throw error
                case .repoNotFound, .noSkills, .other: break
                }
            } catch {}
            skills.append(NewSkill(folder: folder, name: name, summary: summary, path: path))
        }
        return skills.sorted { $0.folder < $1.folder }
    }
}
