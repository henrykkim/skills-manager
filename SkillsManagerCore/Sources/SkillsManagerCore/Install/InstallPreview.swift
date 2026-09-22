import Foundation

public enum PreviewKind: Sendable, Equatable { case skillsRepo, plugin }

/// One skill the install would add, as verified from the source.
public struct PreviewSkill: Identifiable, Sendable, Equatable {
    public var id: String { folder }
    public let folder: String
    public let name: String
    public let summary: String?
    public let body: String
    public let invocation: String
    public let isInstalled: Bool
    public let isValid: Bool          // frontmatter parsed
    public let isPreselected: Bool    // checked by default

    public init(folder: String, name: String, summary: String?, body: String, invocation: String,
                isInstalled: Bool, isValid: Bool, isPreselected: Bool) {
        self.folder = folder; self.name = name; self.summary = summary; self.body = body
        self.invocation = invocation; self.isInstalled = isInstalled; self.isValid = isValid; self.isPreselected = isPreselected
    }
}

/// Everything the sheet shows before Install, and everything Installer needs after.
public struct InstallPreview: Sendable, Equatable {
    public let kind: PreviewKind
    public let title: String
    public let summary: String?
    public let authorName: String?
    public let authorURL: URL?
    public let sourceURL: URL?
    public let skills: [PreviewSkill]
    public let marketplaceNote: String?
    public let isPluginInstalled: Bool
    // Identity carried forward to Installer.
    public let owner: String?
    public let repo: String?
    public let pluginName: String?
    public let marketplace: String?
    public let marketplaceSource: String?

    public init(kind: PreviewKind, title: String, summary: String?, authorName: String?, authorURL: URL?,
                sourceURL: URL?, skills: [PreviewSkill], marketplaceNote: String?, isPluginInstalled: Bool,
                owner: String?, repo: String?, pluginName: String?, marketplace: String?, marketplaceSource: String?) {
        self.kind = kind; self.title = title; self.summary = summary; self.authorName = authorName
        self.authorURL = authorURL; self.sourceURL = sourceURL; self.skills = skills
        self.marketplaceNote = marketplaceNote; self.isPluginInstalled = isPluginInstalled
        self.owner = owner; self.repo = repo; self.pluginName = pluginName
        self.marketplace = marketplace; self.marketplaceSource = marketplaceSource
    }
}
