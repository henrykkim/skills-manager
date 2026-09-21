import Foundation

/// Where a skill lives. Later plans add project and cloud sources.
public enum SkillSource: Sendable, Hashable {
    case personal                       // ~/.claude/skills
    case shared                         // ~/.agents/skills
    case plugin(pluginID: String)       // e.g. "superpowers@claude-plugins-official"
}

public struct Skill: Identifiable, Sendable, Hashable {
    public var id: String { directory.path }
    public let folderName: String
    public let displayName: String      // frontmatter name, falling back to folder name
    public let summary: String?         // frontmatter description
    public let argumentHint: String?
    public let userInvocable: Bool      // default true
    public let modelInvocable: Bool     // false when disable-model-invocation is set
    public let whenToUse: String?
    public let source: SkillSource
    public let directory: URL
    public let lastModified: Date?

    public init(folderName: String, displayName: String, summary: String?, argumentHint: String?,
                userInvocable: Bool, modelInvocable: Bool, whenToUse: String?,
                source: SkillSource, directory: URL, lastModified: Date?) {
        self.folderName = folderName
        self.displayName = displayName
        self.summary = summary
        self.argumentHint = argumentHint
        self.userInvocable = userInvocable
        self.modelInvocable = modelInvocable
        self.whenToUse = whenToUse
        self.source = source
        self.directory = directory
        self.lastModified = lastModified
    }
}

/// Something that didn't parse. Drives the "Needs Attention" list — items
/// must never silently vanish (spec §7).
public struct ParseIssue: Identifiable, Sendable, Hashable {
    public var id: String { location.path + "|" + detail }
    public let location: URL
    public let detail: String

    public init(location: URL, detail: String) {
        self.location = location
        self.detail = detail
    }
}
