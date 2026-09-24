import Foundation

public struct PluginCommand: Identifiable, Sendable, Hashable {
    public var id: String { invocation }
    public let name: String
    public let summary: String?
    public let argumentHint: String?
    public let invocation: String   // e.g. "/demo-plugin:do-thing"

    public init(name: String, summary: String?, argumentHint: String?, invocation: String) {
        self.name = name
        self.summary = summary
        self.argumentHint = argumentHint
        self.invocation = invocation
    }
}

public struct Plugin: Identifiable, Sendable, Hashable {
    public var id: String { pluginID }
    public let pluginID: String         // "name@marketplace"
    public let name: String
    public let marketplace: String
    public let summary: String?         // description from .claude-plugin/plugin.json
    public let provenance: String?      // human origin, e.g. "GitHub: owner/repo"
    public let version: String?
    public let contentDirectory: URL    // where the installed copy lives
    public let lastUpdated: Date?
    public let isEnabled: Bool
    public let skills: [Skill]
    public let commands: [PluginCommand]
    // Provenance for the detail view. All optional — manifests vary wildly.
    public let authorName: String?
    public let authorURL: URL?
    public let homepageURL: URL?        // manifest homepage, else repository
    public let marketplaceURL: URL?     // derived from known_marketplaces.json
    public let installedAt: Date?
    public let scope: PluginScope

    public init(pluginID: String, name: String, marketplace: String, summary: String?,
                provenance: String?, version: String?, contentDirectory: URL,
                lastUpdated: Date?, isEnabled: Bool, skills: [Skill], commands: [PluginCommand],
                authorName: String? = nil, authorURL: URL? = nil, homepageURL: URL? = nil,
                marketplaceURL: URL? = nil, installedAt: Date? = nil, scope: PluginScope = .user) {
        self.pluginID = pluginID
        self.name = name
        self.marketplace = marketplace
        self.summary = summary
        self.provenance = provenance
        self.version = version
        self.contentDirectory = contentDirectory
        self.lastUpdated = lastUpdated
        self.isEnabled = isEnabled
        self.skills = skills
        self.commands = commands
        self.authorName = authorName
        self.authorURL = authorURL
        self.homepageURL = homepageURL
        self.marketplaceURL = marketplaceURL
        self.installedAt = installedAt
        self.scope = scope
    }
}

public enum PluginScope: Sendable, Hashable {
    case user                   // ~/.claude/settings.json
    case project(root: URL)     // <root>/.claude/settings(.local).json
    case cowork                 // Cowork's own plugin set
}

/// A plugin installation area with Claude Code's layout: installed_plugins.json,
/// known_marketplaces.json, cache/<market>/<name>/<version>/. Claude Code's is
/// ~/.claude/plugins; Cowork keeps an identical one per account.
public struct PluginStore: Sendable, Hashable {
    public let root: URL
    public init(root: URL) { self.root = root }
    public var installedPluginsFile: URL { root.appending(path: "installed_plugins.json") }
    public var knownMarketplacesFile: URL { root.appending(path: "known_marketplaces.json") }
    public var cacheDir: URL { root.appending(path: "cache", directoryHint: .isDirectory) }
}
