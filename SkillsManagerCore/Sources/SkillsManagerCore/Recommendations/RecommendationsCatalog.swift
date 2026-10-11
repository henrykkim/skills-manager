import Foundation

/// One entry in a bundled recommendations catalog (spec §4). `source` is any
/// string the Install box accepts: a GitHub link, a skills.sh link, or an
/// install command. `name` and `blurb` are display-only.
public struct RecommendationItem: Codable, Sendable, Equatable, Identifiable {
    public let name: String
    public let source: String
    public let blurb: String?
    public var id: String { source }

    public init(name: String, source: String, blurb: String?) {
        self.name = name; self.source = source; self.blurb = blurb
    }
}

/// The bundled `Recommendations.json`. A missing or malformed file decodes
/// as `.empty`; the app never fails over catalog content.
public struct RecommendationsCatalog: Codable, Sendable, Equatable {
    public let title: String
    public let intro: String?
    public let items: [RecommendationItem]

    public static let empty = RecommendationsCatalog(title: "Recommended", intro: nil, items: [])
    public var isEmpty: Bool { items.isEmpty }

    public init(title: String, intro: String?, items: [RecommendationItem]) {
        self.title = title; self.intro = intro; self.items = items
    }

    private enum CodingKeys: String, CodingKey { case title, intro, items }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Recommended"
        intro = try c.decodeIfPresent(String.self, forKey: .intro)
        let raw = try c.decodeIfPresent([RecommendationItem].self, forKey: .items) ?? []
        // Blank sources can't install; duplicate sources would install twice.
        var seen: Set<String> = []
        items = raw.filter { item in
            let key = item.source.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    /// Decodes `data`; nil or undecodable input yields `.empty`.
    public static func load(_ data: Data?) -> RecommendationsCatalog {
        guard let data, let c = try? JSONDecoder().decode(RecommendationsCatalog.self, from: data) else { return .empty }
        return c
    }
}
