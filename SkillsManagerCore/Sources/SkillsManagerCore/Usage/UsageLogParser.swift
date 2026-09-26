import Foundation

/// Turns one session-log line into skill-invocation events. Decodes only the
/// fields named here (spec §5 privacy); anything else on the line is never read.
public enum UsageLogParser {
    // Declares nothing but what we need. `content` is a string on user lines
    // and an array on assistant lines, so it is decoded leniently.
    private struct Line: Decodable {
        let type: String?
        let timestamp: String?
        let cwd: String?
        let sessionId: String?
        let message: Message?
    }
    private struct Message: Decodable { let content: Blocks? }
    private struct Blocks: Decodable {
        let blocks: [Block]
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            blocks = (try? c.decode([Block].self)) ?? []
        }
    }
    private struct Block: Decodable {
        let type: String?
        let name: String?
        let input: Input?
    }
    private struct Input: Decodable { let skill: String? }

    private static let decoder = JSONDecoder()

    public static func events(inLine data: Data, source: UsageSource, logFile: String) -> [SkillUsageEvent] {
        guard !data.isEmpty, let line = try? decoder.decode(Line.self, from: data) else { return [] }
        guard line.type == "assistant",
              let timestamp = ISODate.parse(line.timestamp),
              let sessionID = line.sessionId,
              let blocks = line.message?.content?.blocks else { return [] }
        let projectRoot: URL? = switch source {
        case .claudeCode: line.cwd.map { URL(fileURLWithPath: Canonical.path($0), isDirectory: true) }
        case .cowork: nil   // sandbox path, not a user folder (spec §3)
        }
        return blocks.compactMap { block in
            guard block.type == "tool_use", block.name == "Skill",
                  let skill = block.input?.skill, !skill.isEmpty else { return nil }
            return SkillUsageEvent(skillName: skill, timestamp: timestamp, projectRoot: projectRoot,
                                   sessionID: sessionID, source: source, logFile: logFile)
        }
    }
}
