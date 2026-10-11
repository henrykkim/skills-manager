import Foundation
import Testing
@testable import SkillsManagerCore

private func data(_ s: String) -> Data { Data(s.utf8) }

@Test func decodesDocumentedShape() {
    let json = """
    {"title":"Recommended at Home Depot","intro":"A starting set.",
     "items":[{"name":"Agentation","source":"https://github.com/benjitaylor/agentation","blurb":"Toolbar."}]}
    """
    let c = RecommendationsCatalog.load(data(json))
    #expect(c.title == "Recommended at Home Depot")
    #expect(c.intro == "A starting set.")
    #expect(c.items.count == 1)
    #expect(c.items[0].name == "Agentation")
    #expect(c.items[0].source == "https://github.com/benjitaylor/agentation")
    #expect(c.items[0].blurb == "Toolbar.")
    #expect(c.items[0].id == c.items[0].source)
    #expect(!c.isEmpty)
}

@Test func missingOptionalFieldsTakeDefaults() {
    let c = RecommendationsCatalog.load(data(#"{"items":[{"name":"X","source":"o/r"}]}"#))
    #expect(c.title == "Recommended")
    #expect(c.intro == nil)
    #expect(c.items[0].blurb == nil)
}

@Test func unknownKeysAreIgnored() {
    let c = RecommendationsCatalog.load(data(#"{"items":[{"name":"X","source":"o/r","icon":"x"}],"version":2}"#))
    #expect(c.items.count == 1)
}

@Test func invalidJSONIsEmpty() {
    #expect(RecommendationsCatalog.load(data("{not json")) == .empty)
    #expect(RecommendationsCatalog.load(data("{not json")).isEmpty)
}

@Test func missingDataIsEmpty() {
    #expect(RecommendationsCatalog.load(nil) == .empty)
}

@Test func emptyItemsIsEmpty() {
    #expect(RecommendationsCatalog.load(data(#"{"title":"T","items":[]}"#)).isEmpty)
}

@Test func dropsDuplicateSources() {
    let json = #"{"items":[{"name":"A","source":"o/r"},{"name":"B","source":"o/r"},{"name":"C","source":"o/s"}]}"#
    let c = RecommendationsCatalog.load(data(json))
    #expect(c.items.map(\.name) == ["A", "C"])
}

@Test func dropsItemsWithBlankSource() {
    let json = #"{"items":[{"name":"A","source":"   "},{"name":"B","source":"o/s"}]}"#
    #expect(RecommendationsCatalog.load(data(json)).items.map(\.name) == ["B"])
}

@Test func decodesOptionalURL() {
    let json = #"{"items":[{"name":"A","source":"o/r","url":"https://github.com/o/r"},{"name":"B","source":"o/s"}]}"#
    let c = RecommendationsCatalog.load(data(json))
    #expect(c.items[0].url == URL(string: "https://github.com/o/r"))
    #expect(c.items[1].url == nil)
}
