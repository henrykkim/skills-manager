import Foundation

public enum UsageSource: String, Codable, Sendable, Hashable {
    case claudeCode, cowork
}

/// One explicit skill invocation, as recorded in a session log (spec §5).
/// Never carries message text or the invocation's arguments.
public struct SkillUsageEvent: Codable, Sendable, Hashable {
    public let skillName: String      // exactly as logged, e.g. "superpowers:brainstorming"
    public let timestamp: Date        // from the log line, never from file dates
    public let projectRoot: URL?      // canonical `cwd`; nil for Cowork sandbox paths
    public let sessionID: String
    public let source: UsageSource
    public let logFile: String        // canonical path of the log that produced it

    public init(skillName: String, timestamp: Date, projectRoot: URL?, sessionID: String,
                source: UsageSource, logFile: String) {
        self.skillName = skillName
        self.timestamp = timestamp
        self.projectRoot = projectRoot
        self.sessionID = sessionID
        self.source = source
        self.logFile = logFile
    }
}

/// Where the last scan stopped in one log file.
public struct UsageFileCursor: Codable, Sendable, Hashable {
    public let byteOffset: Int
    public let fileSize: Int

    public init(byteOffset: Int, fileSize: Int) {
        self.byteOffset = byteOffset
        self.fileSize = fileSize
    }
}

/// Everything the store file holds. Keys of `cursors` are canonical log paths.
public struct UsageStoreData: Codable, Sendable, Hashable {
    public var events: [SkillUsageEvent]
    public var cursors: [String: UsageFileCursor]

    public init(events: [SkillUsageEvent] = [], cursors: [String: UsageFileCursor] = [:]) {
        self.events = events
        self.cursors = cursors
    }
}
