import Foundation

public struct InstalledPluginRecord: Sendable, Equatable {
    public let pluginID: String
    public let name: String
    public let marketplace: String
    public let version: String?
    public let installPath: String?
    public let installedAt: Date?
    public let lastUpdated: Date?
    /// Installed for the user (`--scope user`), not only for a project.
    public var hasUserScope: Bool = true
}

public struct PluginLoadResult: Sendable {
    public var plugins: [Plugin]
    public var issues: [ParseIssue]

    public init(plugins: [Plugin] = [], issues: [ParseIssue] = []) {
        self.plugins = plugins
        self.issues = issues
    }
}

public enum PluginRegistry {
    /// Decodes installed_plugins.json (v2). Throws on unreadable/undecodable content —
    /// callers decide whether that is an issue (file exists but broken) or normal (no file).
    public static func loadRecords(installedPluginsFile: URL) throws -> [InstalledPluginRecord] {
        struct RegistryFile: Decodable {
            let version: Int
            let plugins: [String: [Entry]]
            struct Entry: Decodable {
                let scope: String?
                let installPath: String?
                let version: String?
                let installedAt: String?
                let lastUpdated: String?
            }
        }
        let data = try Data(contentsOf: installedPluginsFile)
        let file = try JSONDecoder().decode(RegistryFile.self, from: data)
        return file.plugins.compactMap { pluginID, entries in
            let userEntry = entries.first(where: { $0.scope == "user" })
            guard let entry = userEntry ?? entries.first else { return nil }
            let parts = pluginID.split(separator: "@", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return InstalledPluginRecord(
                pluginID: pluginID,
                name: String(parts[0]),
                marketplace: String(parts[1]),
                version: entry.version,
                installPath: entry.installPath,
                installedAt: ISODate.parse(entry.installedAt),
                lastUpdated: ISODate.parse(entry.lastUpdated),
                hasUserScope: userEntry != nil)
        }
    }

    public static func loadPlugins(paths: ClaudePaths, enabledPlugins: [String: Bool]) -> PluginLoadResult {
        loadPlugins(store: paths.userPluginStore, enabledPlugins: enabledPlugins, scope: .user, only: nil)
    }

    /// `only`: when set, load just these plugin IDs (project scope) and report
    /// any that aren't installed.
    public static func loadPlugins(store: PluginStore, enabledPlugins: [String: Bool],
                                   scope: PluginScope, only: Set<String>?) -> PluginLoadResult {
        let fm = FileManager.default
        var result = PluginLoadResult()
        var records: [InstalledPluginRecord]
        do {
            records = try loadRecords(installedPluginsFile: store.installedPluginsFile)
        } catch {
            if fm.fileExists(atPath: store.installedPluginsFile.path) {
                result.issues.append(ParseIssue(
                    location: store.installedPluginsFile,
                    detail: "Plugin registry can't be read: \(error.localizedDescription)"))
            }
            records = []
        }
        // A plugin installed only for a project (--scope project/local) isn't
        // on for all your projects; project loads pick it up via `only`.
        if scope == .user && only == nil {
            records = records.filter(\.hasUserScope)
        }
        if let only {
            records = records.filter { only.contains($0.pluginID) }
            let found = Set(records.map(\.pluginID))
            for missing in only.subtracting(found).sorted() {
                result.issues.append(ParseIssue(
                    location: store.installedPluginsFile,
                    detail: "\(missing) is turned on for a project but isn't installed"))
            }
        }

        let marketplaces = marketplaceInfo(knownMarketplacesFile: store.knownMarketplacesFile)

        for record in records.sorted(by: { $0.pluginID < $1.pluginID }) {
            guard let contentDir = contentDirectory(for: record, store: store) else {
                result.issues.append(ParseIssue(
                    location: store.cacheDir,
                    detail: "\(record.pluginID) is registered but its files are missing"))
                continue
            }
            let scan = SkillScanner.scan(
                directory: contentDir.appending(path: "skills", directoryHint: .isDirectory),
                source: .plugin(pluginID: record.pluginID))
            result.issues.append(contentsOf: scan.issues)
            let manifest = Manifest.read(contentDir: contentDir)
            let market = marketplaces[record.marketplace]
            result.plugins.append(Plugin(
                pluginID: record.pluginID,
                name: record.name,
                marketplace: record.marketplace,
                summary: manifest.description,
                provenance: market?.provenance,
                version: record.version,
                contentDirectory: contentDir,
                lastUpdated: record.lastUpdated,
                isEnabled: enabledPlugins[record.pluginID] ?? true,
                skills: scan.skills,
                commands: loadCommands(
                    pluginName: record.name,
                    commandsDir: contentDir.appending(path: "commands", directoryHint: .isDirectory)),
                authorName: manifest.authorName,
                authorURL: manifest.authorURL,
                homepageURL: manifest.homepageURL,
                marketplaceURL: market?.url,
                installedAt: record.installedAt,
                scope: scope))
        }
        return result
    }

    /// The fields we show from the plugin's own manifest. Every field optional.
    struct Manifest {
        var description: String?
        var authorName: String?
        var authorURL: URL?
        var homepageURL: URL?

        static func read(contentDir: URL) -> Manifest {
            let file = contentDir.appending(path: ".claude-plugin/plugin.json")
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return Manifest()
            }
            var m = Manifest()
            m.description = json["description"] as? String
            if let author = json["author"] as? [String: Any] {
                m.authorName = author["name"] as? String
                m.authorURL = GitURL.browsable(author["url"] as? String)
            } else if let author = json["author"] as? String {
                m.authorName = author            // some manifests use a bare string
            }
            let repositoryURLString: String?
            if let repoString = json["repository"] as? String {
                repositoryURLString = repoString
            } else if let repoDict = json["repository"] as? [String: Any] {
                repositoryURLString = repoDict["url"] as? String
            } else {
                repositoryURLString = nil
            }
            m.homepageURL = GitURL.browsable(json["homepage"] as? String)
                ?? GitURL.browsable(repositoryURLString)
            return m
        }
    }

    struct MarketplaceInfo {
        var provenance: String?   // sidebar caption text, unchanged from plan 1
        var url: URL?
    }

    /// Per marketplace, from known_marketplaces.json. Lenient: unreadable → empty.
    private static func marketplaceInfo(knownMarketplacesFile: URL) -> [String: MarketplaceInfo] {
        guard let data = try? Data(contentsOf: knownMarketplacesFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var result: [String: MarketplaceInfo] = [:]
        for (name, value) in json {
            guard let entry = value as? [String: Any],
                  let source = entry["source"] as? [String: Any] else { continue }
            if let repo = source["repo"] as? String {
                result[name] = MarketplaceInfo(provenance: "GitHub: \(repo)", url: GitURL.github(repo: repo))
            } else if let url = source["url"] as? String {
                result[name] = MarketplaceInfo(provenance: "Git: \(url)", url: GitURL.browsable(url))
            }
        }
        return result
    }

    /// Prefer the cache layout (relocatable, verified format); fall back to the
    /// registry's absolute installPath only if the cache copy is absent.
    private static func contentDirectory(for record: InstalledPluginRecord, store: PluginStore) -> URL? {
        let fm = FileManager.default
        if let version = record.version {
            let cacheDir = store.cacheDir
                .appending(path: record.marketplace, directoryHint: .isDirectory)
                .appending(path: record.name, directoryHint: .isDirectory)
                .appending(path: version, directoryHint: .isDirectory)
            if fm.fileExists(atPath: cacheDir.path) { return cacheDir }
        }
        if let installPath = record.installPath, fm.fileExists(atPath: installPath) {
            return URL(fileURLWithPath: installPath, isDirectory: true)
        }
        return nil
    }

    // Top-level command files only. Some plugins nest commands in subdirectories;
    // their invocation naming needs verification against Claude Code, so they
    // ship in plan 2 rather than guessing here (wrong info is worse than missing).
    private static func loadCommands(pluginName: String, commandsDir: URL) -> [PluginCommand] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: commandsDir, includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { file in
                let stem = file.deletingPathExtension().lastPathComponent
                var summary: String?
                var argumentHint: String?
                if let text = try? String(contentsOf: file, encoding: .utf8),
                   case .parsed(let fm, _) = FrontmatterParser.parse(text) {
                    summary = fm.description
                    argumentHint = fm.argumentHint
                }
                return PluginCommand(name: stem, summary: summary, argumentHint: argumentHint,
                                     invocation: "/\(pluginName):\(stem)")
            }
    }
}
