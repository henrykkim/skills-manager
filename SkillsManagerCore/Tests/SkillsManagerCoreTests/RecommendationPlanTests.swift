import Foundation
import Testing
@testable import SkillsManagerCore

private func skill(_ folder: String, installed: Bool = false, valid: Bool = true) -> PreviewSkill {
    PreviewSkill(folder: folder, name: folder, summary: nil, body: "", invocation: "/\(folder)",
                 isInstalled: installed, isValid: valid, isPreselected: !installed && valid)
}

private func repo(_ skills: [PreviewSkill]) -> InstallPreview {
    InstallPreview(kind: .skillsRepo, title: "o/r", summary: nil, authorName: "o", authorURL: nil, sourceURL: nil,
                   skills: skills, marketplaceNote: nil, isPluginInstalled: false, owner: "o", repo: "r",
                   pluginName: nil, marketplace: nil, marketplaceSource: nil)
}

private func plugin(installed: Bool) -> InstallPreview {
    InstallPreview(kind: .plugin, title: "p", summary: nil, authorName: nil, authorURL: nil, sourceURL: nil, skills: [],
                   marketplaceNote: nil, isPluginInstalled: installed, owner: nil, repo: nil,
                   pluginName: "p", marketplace: "m", marketplaceSource: nil)
}

private let items = [
    RecommendationItem(name: "Plugin", source: "claude plugin install p@m", blurb: nil),
    RecommendationItem(name: "Repo", source: "https://github.com/o/r", blurb: nil),
    RecommendationItem(name: "Broken", source: "nonsense", blurb: nil),
]

@Test func pluginInstalledState() {
    #expect(RecommendationPlan.isInstalled(plugin(installed: true)))
    #expect(!RecommendationPlan.isInstalled(plugin(installed: false)))
}

@Test func repoInstalledOnlyWhenEveryValidSkillIsInstalled() {
    #expect(RecommendationPlan.isInstalled(repo([skill("a", installed: true), skill("b", installed: true)])))
    #expect(!RecommendationPlan.isInstalled(repo([skill("a", installed: true), skill("b")])))
    // Invalid skills never count either way.
    #expect(RecommendationPlan.isInstalled(repo([skill("a", installed: true), skill("x", valid: false)])))
    // A repo with no valid skills is not "installed"; it is unavailable.
    #expect(!RecommendationPlan.isInstalled(repo([skill("x", valid: false)])))
}

@Test func foldersToInstallAreValidAndMissing() {
    let p = repo([skill("a", installed: true), skill("b"), skill("x", valid: false), skill("c")])
    #expect(RecommendationPlan.folders(toInstallFrom: p) == ["b", "c"])
    #expect(RecommendationPlan.folders(toInstallFrom: plugin(installed: false)) == [])
}

@Test func keepsCatalogOrderAndSkipsUnselected() {
    let previews = [items[0].id: plugin(installed: false), items[1].id: repo([skill("a")])]
    let steps = RecommendationPlan.make(items: items, previews: previews, selected: [items[1].id, items[0].id])
    #expect(steps.map(\.itemID) == [items[0].id, items[1].id])
    let only = RecommendationPlan.make(items: items, previews: previews, selected: [items[1].id])
    #expect(only.map(\.itemID) == [items[1].id])
}

@Test func skipsItemsWithoutPreview() {
    let previews = [items[0].id: plugin(installed: false)]
    let steps = RecommendationPlan.make(items: items, previews: previews, selected: Set(items.map(\.id)))
    #expect(steps.map(\.itemID) == [items[0].id])
}

@Test func skipsInstalledItems() {
    let previews = [items[0].id: plugin(installed: true), items[1].id: repo([skill("a", installed: true)])]
    #expect(RecommendationPlan.make(items: items, previews: previews, selected: Set(items.map(\.id))).isEmpty)
}

@Test func installsOnlyMissingValidSkills() {
    let previews = [items[1].id: repo([skill("a", installed: true), skill("b"), skill("x", valid: false)])]
    let steps = RecommendationPlan.make(items: items, previews: previews, selected: [items[1].id])
    #expect(steps.count == 1)
    #expect(steps[0].folders == ["b"])
}

@Test func pluginStepHasNoFolders() {
    let steps = RecommendationPlan.make(items: items, previews: [items[0].id: plugin(installed: false)], selected: [items[0].id])
    #expect(steps[0].folders == [])
}
