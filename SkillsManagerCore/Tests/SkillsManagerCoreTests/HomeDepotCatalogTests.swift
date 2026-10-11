import Foundation
import Testing
@testable import SkillsManagerCore

/// Reads the catalog file that ships in the Home Depot build straight from
/// the repo, so a bad edit fails here before it ships.
private func repoCatalog(_ flavor: String) throws -> RecommendationsCatalog {
    // .../SkillsManagerCore/Tests/SkillsManagerCoreTests/HomeDepotCatalogTests.swift → repo root is four levels up.
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let url = root.appending(path: "Catalogs/\(flavor)/Recommendations.json")
    return RecommendationsCatalog.load(try Data(contentsOf: url))
}

@Test func homeDepotCatalogHasExactlyTheAgreedItems() throws {
    let c = try repoCatalog("HomeDepot")
    #expect(c.title == "Recommended at Home Depot")
    #expect(c.items.map(\.name) == ["Superpowers", "Agentation", "Emil's Skills", "Jakub's Skills"])
    #expect(c.items.map(\.source) == [
        "claude plugin install superpowers@claude-plugins-official",
        "https://github.com/benjitaylor/agentation",
        "https://github.com/emilkowalski/skills",
        "https://github.com/jakubkrehel/skills",
    ])
    #expect(c.items.allSatisfy { $0.blurb?.isEmpty == false })
}

@Test func homeDepotSourcesAllParse() throws {
    for item in try repoCatalog("HomeDepot").items {
        if case .unrecognized = InstallIntentParser.parse(item.source) { Issue.record("unrecognized: \(item.source)") }
    }
    #expect(InstallIntentParser.parse("claude plugin install superpowers@claude-plugins-official") ==
        .plugin(name: "superpowers", marketplace: "claude-plugins-official", marketplaceSource: nil))
}

@Test func generalCatalogIsEmpty() throws {
    #expect(try repoCatalog("General").isEmpty)
}
