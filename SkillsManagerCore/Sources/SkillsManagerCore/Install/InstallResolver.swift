import Foundation

/// Spec §5: turn a recognized intent into a verified preview. Throws InstallError.
public struct InstallResolver: Sendable {
    private let github: GitHubClient
    private let paths: ClaudePaths
    private static let maxSkills = 50

    public init(github: GitHubClient, paths: ClaudePaths) {
        self.github = github
        self.paths = paths
    }

    public func resolve(_ intent: InstallIntent) async throws -> InstallPreview {
        switch intent {
        case .unrecognized(let diagnosis):
            throw InstallError.other(diagnosis)
        case .skillsRepo(let owner, let repo, let subpath, let only):
            return try await resolveRepo(owner: owner, repo: repo, subpath: subpath, only: only)
        case .plugin(let name, let market, let source):
            return resolvePlugin(name: name, marketplace: market, source: source)
        }
    }

    // MARK: skills repo

    private func resolveRepo(owner: String, repo: String, subpath: String?, only: [String]?) async throws -> InstallPreview {
        let info = try await github.repo(owner: owner, repo: repo)
        var paths = try await github.treePaths(owner: owner, repo: repo, branch: info.defaultBranch)
            .filter { $0 == "SKILL.md" || $0.hasSuffix("/SKILL.md") }
        if let subpath {
            let prefix = subpath.hasSuffix("/") ? subpath : subpath + "/"
            paths = paths.filter { $0.hasPrefix(prefix) || $0 == subpath + "/SKILL.md" }
        }
        guard !paths.isEmpty else { throw InstallError.noSkills }

        let installed = installedSkillFolders()
        var skills: [PreviewSkill] = []
        for path in paths.prefix(Self.maxSkills) {
            let folder = path == "SKILL.md" ? repo : String(path.dropLast("/SKILL.md".count).split(separator: "/").last ?? Substring(repo))
            let isInstalled = installed.contains(folder)
            let text: String
            do {
                text = try await github.raw(owner: owner, repo: repo, branch: info.defaultBranch, path: path)
            } catch let error as InstallError {
                switch error {
                case .rateLimited, .network:
                    // A wholesale API outage isn't a per-file formatting problem —
                    // let it propagate so the caller shows the real cause instead
                    // of a misleading "invalid skill" row.
                    throw error
                case .repoNotFound, .noSkills, .other:
                    skills.append(PreviewSkill(folder: folder, name: folder, summary: nil, body: "", invocation: "/\(folder)",
                                               isInstalled: isInstalled, isValid: false, isPreselected: false))
                    continue
                }
            } catch {
                skills.append(PreviewSkill(folder: folder, name: folder, summary: nil, body: "", invocation: "/\(folder)",
                                           isInstalled: isInstalled, isValid: false, isPreselected: false))
                continue
            }
            switch FrontmatterParser.parse(text) {
            case .parsed(let fm, let body):
                let wanted = only.map { $0.contains(folder) } ?? true
                skills.append(PreviewSkill(folder: folder, name: fm.name ?? folder, summary: fm.description, body: body,
                                           invocation: "/\(folder)", isInstalled: isInstalled, isValid: true,
                                           isPreselected: wanted && !isInstalled))
            case .missing(let body):
                skills.append(PreviewSkill(folder: folder, name: folder, summary: nil, body: body, invocation: "/\(folder)",
                                           isInstalled: isInstalled, isValid: false, isPreselected: false))
            case .malformed:
                skills.append(PreviewSkill(folder: folder, name: folder, summary: nil, body: text, invocation: "/\(folder)",
                                           isInstalled: isInstalled, isValid: false, isPreselected: false))
            }
        }
        skills.sort { $0.folder < $1.folder }
        return InstallPreview(kind: .skillsRepo, title: "\(owner)/\(repo)", summary: info.description,
                              authorName: owner, authorURL: info.ownerURL, sourceURL: info.htmlURL,
                              skills: skills, marketplaceNote: nil, isPluginInstalled: false,
                              owner: owner, repo: repo, pluginName: nil, marketplace: nil, marketplaceSource: nil)
    }

    /// Folder names present in either skills dir (symlinks count — that's how connected skills look).
    private func installedSkillFolders() -> Set<String> {
        let fm = FileManager.default
        var names = Set<String>()
        for dir in [paths.personalSkillsDir, paths.sharedSkillsDir] {
            for entry in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where !entry.hasPrefix(".") {
                names.insert(entry)
            }
        }
        return names
    }

    // MARK: plugin

    private func resolvePlugin(name: String, marketplace: String, source: String?) -> InstallPreview {
        let pluginID = "\(name)@\(marketplace)"
        let installed = ((try? PluginRegistry.loadRecords(installedPluginsFile: paths.installedPluginsFile)) ?? [])
            .contains { $0.pluginID == pluginID }
        let known = knownMarketplaces().contains(marketplace)
        var summary: String?
        var homepage: URL?
        if known, let entry = marketplaceEntry(marketplace: marketplace, plugin: name) {
            summary = entry["description"] as? String
            homepage = GitURL.browsable(entry["homepage"] as? String)
        }
        let note: String? = (!known && source != nil) ? "Will add marketplace \(marketplace) from \(source!) first." : nil
        return InstallPreview(kind: .plugin, title: name, summary: summary, authorName: nil, authorURL: nil,
                              sourceURL: homepage, skills: [], marketplaceNote: note, isPluginInstalled: installed,
                              owner: nil, repo: nil, pluginName: name, marketplace: marketplace, marketplaceSource: source)
    }

    private func knownMarketplaces() -> Set<String> {
        guard let data = try? Data(contentsOf: paths.knownMarketplacesFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return Set(json.keys)
    }

    private func marketplaceEntry(marketplace: String, plugin: String) -> [String: Any]? {
        let file = paths.pluginsDir.appending(path: "marketplaces/\(marketplace)/.claude-plugin/marketplace.json")
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = json["plugins"] as? [[String: Any]] else { return nil }
        return plugins.first { ($0["name"] as? String) == plugin }
    }
}
