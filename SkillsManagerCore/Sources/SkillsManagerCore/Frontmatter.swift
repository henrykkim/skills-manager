import Foundation
import Yams

/// The fields Skills Manager reads from a SKILL.md YAML header.
/// Unknown fields are ignored (and left untouched on disk — we never rewrite files).
public struct Frontmatter: Equatable, Sendable {
    public var name: String?
    public var description: String?
    public var argumentHint: String?
    public var userInvocable: Bool?
    public var disableModelInvocation: Bool?
    public var whenToUse: String?

    public init(name: String? = nil, description: String? = nil, argumentHint: String? = nil,
                userInvocable: Bool? = nil, disableModelInvocation: Bool? = nil, whenToUse: String? = nil) {
        self.name = name
        self.description = description
        self.argumentHint = argumentHint
        self.userInvocable = userInvocable
        self.disableModelInvocation = disableModelInvocation
        self.whenToUse = whenToUse
    }
}

public enum FrontmatterResult: Sendable {
    case parsed(Frontmatter, body: String)
    case missing(body: String)
    case malformed(reason: String)
}

public enum FrontmatterParser {
    public static func parse(_ text: String) -> FrontmatterResult {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        guard lines.first == "---" else { return .missing(body: normalized) }
        guard let closeIndex = lines.dropFirst().firstIndex(of: "---") else {
            return .malformed(reason: "The header never closes (missing the second ---)")
        }
        let yamlText = lines[1..<closeIndex].joined(separator: "\n")
        let body = lines[(closeIndex + 1)...].joined(separator: "\n")
        do {
            guard let dict = try Yams.load(yaml: yamlText) as? [String: Any] else {
                return .malformed(reason: "The header is not a list of key: value fields")
            }
            var fm = Frontmatter()
            fm.name = dict["name"] as? String
            fm.description = dict["description"] as? String
            fm.argumentHint = dict["argument-hint"] as? String
            fm.userInvocable = boolValue(dict["user-invocable"])
            fm.disableModelInvocation = boolValue(dict["disable-model-invocation"])
            fm.whenToUse = dict["when_to_use"] as? String
            return .parsed(fm, body: body)
        } catch {
            return .malformed(reason: "The header isn't valid YAML: \(String(describing: error))")
        }
    }

    private static func boolValue(_ raw: Any?) -> Bool? {
        if let b = raw as? Bool { return b }
        if let s = raw as? String {
            if s.lowercased() == "true" { return true }
            if s.lowercased() == "false" { return false }
        }
        return nil
    }
}
