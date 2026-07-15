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

    public init(pluginID: String, name: String, marketplace: String, summary: String?,
                provenance: String?, version: String?, contentDirectory: URL,
                lastUpdated: Date?, isEnabled: Bool, skills: [Skill], commands: [PluginCommand]) {
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
    }
}
