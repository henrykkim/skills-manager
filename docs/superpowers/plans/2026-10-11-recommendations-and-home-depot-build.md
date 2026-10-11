# Recommendations Catalog and Home Depot Build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a bundled recommendations catalog that is offered on first launch, and a second "Skills Manager for Home Depot" build that ships a catalog of four open source items while sharing all code and releases with the general app.

**Architecture:** Core gains a `RecommendationsCatalog` model and a pure `RecommendationPlan` that turns resolved previews plus a selection into ordered install steps. The app gains a `RecommendationsModel` that resolves each catalog item through the existing `InstallResolver` and installs through the existing `Installer`, and a `RecommendationsSheet` presented from `LibraryView`. XcodeGen declares a second target that differs only in bundled catalog, display name, bundle ID and Sparkle feed; the release workflow builds and publishes both.

**Tech Stack:** Swift 6, SwiftUI, Observation, Swift Testing (`@Test`/`#expect`), XcodeGen, Sparkle 2, zsh scripts, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-11-recommendations-and-home-depot-build-design.md`

## Global Constraints

- macOS deployment target `14.0`; Swift tools version `6.0`; strict concurrency (everything public in Core is `Sendable`).
- Core tests run with `cd SkillsManagerCore && swift test`. The app has no test target; app work is verified by `xcodegen generate && xcodebuild -project SkillsManager.xcodeproj -scheme <Scheme> -configuration Debug build`.
- General target: display name `Skills Manager`, bundle ID `com.henrykkim.SkillsManager`, feed `https://github.com/henrykkim/skills-manager/releases/latest/download/appcast.xml`.
- Home Depot target: display name `Skills Manager for Home Depot`, bundle ID `com.henrykkim.SkillsManagerHomeDepot`, feed `https://github.com/henrykkim/skills-manager/releases/latest/download/appcast-homedepot.xml`.
- Catalog file name in both bundles: `Recommendations.json`. General catalog is empty.
- Home Depot catalog contains exactly four items: Superpowers (plugin), Agentation, Emil's Skills, Jakub's Skills. No Eux plugins.
- Dismissal flag key: `recommendationsDismissed` in `UserDefaults.standard`.
- Copy for errors and missing tools is reused from `InstallSheetModel.sentence(for:)` and the existing `missingTool` strings; do not invent new error sentences.
- Spacing uses the `Spacing` enum from `App/DesignSystem.swift`; no ad-hoc values.
- Commit messages end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## Review Focus

1. A catalog item whose `source` is not recognizable (typo, non-GitHub link): its row must show the diagnosis sentence and be unselectable; other rows must still install. Pinned by `RecommendationPlanTests.skipsItemsWithoutPreview` (Task 2) and the model's `.unavailable` path (Task 5).
2. A skills repository where some skills are already installed: only the missing valid skills install, and the row is not marked "Already installed". Pinned by `RecommendationPlanTests.installsOnlyMissingValidSkills` (Task 2).
3. Two catalog items with the same `source`: the second is dropped at load time so one install never runs twice. Pinned by `RecommendationsCatalogTests.dropsDuplicateSources` (Task 1).
4. The catalog resource is missing from the bundle or is malformed: the app must behave as if the catalog were empty, never crash, and never show the sheet or menu item. Pinned by `RecommendationsCatalogTests.invalidJSONIsEmpty` and `.missingDataIsEmpty` (Task 1).
5. A user who has dismissed the sheet, then installs the app's next update: the sheet must not reappear. Pinned by storing the flag under a stable key and the manual check in Task 6.

---

### Task 1: `RecommendationsCatalog` model and loader (Core)

**Files:**
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/Recommendations/RecommendationsCatalog.swift`
- Test: `SkillsManagerCore/Tests/SkillsManagerCoreTests/RecommendationsCatalogTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `public struct RecommendationItem: Codable, Sendable, Equatable, Identifiable { public let name: String; public let source: String; public let blurb: String?; public var id: String { source } }`
  - `public struct RecommendationsCatalog: Codable, Sendable, Equatable { public let title: String; public let intro: String?; public let items: [RecommendationItem]; public var isEmpty: Bool; public static let empty: RecommendationsCatalog; public static func load(_ data: Data?) -> RecommendationsCatalog }`

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SkillsManagerCore && swift test --filter RecommendationsCatalogTests`
Expected: compile error, `RecommendationsCatalog` not found.

- [ ] **Step 3: Write the implementation**

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SkillsManagerCore && swift test --filter RecommendationsCatalogTests`
Expected: 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add SkillsManagerCore/Sources/SkillsManagerCore/Recommendations/RecommendationsCatalog.swift SkillsManagerCore/Tests/SkillsManagerCoreTests/RecommendationsCatalogTests.swift
git commit -m "feat(recommendations): catalog model and tolerant loader

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: `RecommendationPlan` (Core)

**Files:**
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/Recommendations/RecommendationPlan.swift`
- Test: `SkillsManagerCore/Tests/SkillsManagerCoreTests/RecommendationPlanTests.swift`

**Interfaces:**
- Consumes: `RecommendationItem` (Task 1), `InstallPreview`, `PreviewSkill`, `PreviewKind` (existing).
- Produces:
  - `public enum RecommendationPlan`
  - `public struct RecommendationPlan.Step: Sendable, Equatable { public let itemID: String; public let preview: InstallPreview; public let folders: [String] }`
  - `public static func isInstalled(_ preview: InstallPreview) -> Bool`
  - `public static func folders(toInstallFrom preview: InstallPreview) -> [String]`
  - `public static func make(items: [RecommendationItem], previews: [String: InstallPreview], selected: Set<String>) -> [Step]`

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SkillsManagerCore && swift test --filter RecommendationPlanTests`
Expected: compile error, `RecommendationPlan` not found.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Pure planning for the Recommended sheet (spec §6): which catalog items
/// to install, in catalog order, and which skill folders each one needs.
/// Resolution (network) and execution (processes) live elsewhere.
public enum RecommendationPlan {
    public struct Step: Sendable, Equatable {
        public let itemID: String
        public let preview: InstallPreview
        /// Skill folders to pass to `Installer`; empty for plugins.
        public let folders: [String]
        public init(itemID: String, preview: InstallPreview, folders: [String]) {
            self.itemID = itemID; self.preview = preview; self.folders = folders
        }
    }

    /// A plugin is installed when the registry says so. A skills repo is
    /// installed when it has at least one valid skill and all of them are
    /// on disk; invalid skills are ignored (they could never be installed).
    public static func isInstalled(_ preview: InstallPreview) -> Bool {
        switch preview.kind {
        case .plugin:
            return preview.isPluginInstalled
        case .skillsRepo:
            let valid = preview.skills.filter(\.isValid)
            return !valid.isEmpty && valid.allSatisfy(\.isInstalled)
        }
    }

    /// Valid skills not yet on disk, in preview order. Empty for plugins.
    public static func folders(toInstallFrom preview: InstallPreview) -> [String] {
        guard preview.kind == .skillsRepo else { return [] }
        return preview.skills.filter { $0.isValid && !$0.isInstalled }.map(\.folder)
    }

    /// One step per selected, resolved, not-yet-installed item, in catalog order.
    public static func make(items: [RecommendationItem], previews: [String: InstallPreview],
                            selected: Set<String>) -> [Step] {
        items.compactMap { item in
            guard selected.contains(item.id), let preview = previews[item.id], !isInstalled(preview) else { return nil }
            let folders = folders(toInstallFrom: preview)
            if preview.kind == .skillsRepo, folders.isEmpty { return nil }
            return Step(itemID: item.id, preview: preview, folders: folders)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SkillsManagerCore && swift test --filter RecommendationPlanTests`
Expected: 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add SkillsManagerCore/Sources/SkillsManagerCore/Recommendations/RecommendationPlan.swift SkillsManagerCore/Tests/SkillsManagerCoreTests/RecommendationPlanTests.swift
git commit -m "feat(recommendations): pure install plan over resolved previews

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Catalog files, Home Depot target, and catalog fixture test

**Files:**
- Create: `Catalogs/General/Recommendations.json`
- Create: `Catalogs/HomeDepot/Recommendations.json`
- Modify: `project.yml` (add `SkillsManagerHomeDepot` target and scheme; add the general catalog as a resource)
- Modify: `.gitignore` (add `App/Info-HomeDepot.plist`)
- Test: `SkillsManagerCore/Tests/SkillsManagerCoreTests/HomeDepotCatalogTests.swift`

**Interfaces:**
- Consumes: `RecommendationsCatalog.load` (Task 1), `InstallIntentParser.parse` (existing).
- Produces: a bundle resource named `Recommendations.json` in both app targets; Xcode scheme `SkillsManagerHomeDepot`.

Why the Superpowers source is a command, not the GitHub link: `InstallIntentParser.parseGitHub` turns any `github.com/owner/repo` link into a skills-repo intent, which would install Superpowers' skills with `npx skills` instead of as a Claude Code plugin. The plugin command form is what the parser maps to `.plugin`, and `superpowers@claude-plugins-official` is the marketplace the owner's own machine uses.

- [ ] **Step 1: Write the fixture test**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SkillsManagerCore && swift test --filter HomeDepotCatalogTests`
Expected: FAIL, the catalog files do not exist (`Data(contentsOf:)` throws).

- [ ] **Step 3: Create the catalog files**

`Catalogs/General/Recommendations.json`:

```json
{
  "title": "Recommended",
  "items": []
}
```

`Catalogs/HomeDepot/Recommendations.json`:

```json
{
  "title": "Recommended at Home Depot",
  "intro": "A starting set our team uses. Install any or all; you can add more later from File → Install.",
  "items": [
    {
      "name": "Superpowers",
      "source": "claude plugin install superpowers@claude-plugins-official",
      "blurb": "Workflow skills for Claude Code: brainstorming, planning, test-driven development, debugging."
    },
    {
      "name": "Agentation",
      "source": "https://github.com/benjitaylor/agentation",
      "blurb": "A visual feedback toolbar so you can annotate a page and hand the notes to Claude."
    },
    {
      "name": "Emil's Skills",
      "source": "https://github.com/emilkowalski/skills",
      "blurb": "Design engineering and animation skills from Emil Kowalski."
    },
    {
      "name": "Jakub's Skills",
      "source": "https://github.com/jakubkrehel/skills",
      "blurb": "Accessibility, layout, typography, color and UI polish reviews from Jakub Krehel."
    }
  ]
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SkillsManagerCore && swift test --filter HomeDepotCatalogTests`
Expected: 3 tests pass.

- [ ] **Step 5: Add the Home Depot target to `project.yml`**

Replace the `targets:` and `schemes:` sections with:

```yaml
targets:
  SkillsManager:
    type: application
    platform: macOS
    sources:
      - App
      - path: Catalogs/General/Recommendations.json
        buildPhase: resources
    dependencies:
      - package: SkillsManagerCore
      - package: Sparkle
      - sdk: FoundationModels.framework
        weak: true
    info:
      path: App/Info.plist
      properties:
        CFBundleDisplayName: "Skills Manager"
        CFBundleIconFile: AppIcon
        CFBundleShortVersionString: "$(MARKETING_VERSION)"
        CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"
        LSApplicationCategoryType: public.app-category.developer-tools
        NSHumanReadableCopyright: ""
        SUFeedURL: "$(SU_FEED_URL)"
        SUPublicEDKey: "$(SPARKLE_PUBLIC_KEY)"
        SUEnableAutomaticChecks: "$(SU_AUTOMATIC_CHECKS)"
        SUAutomaticallyUpdate: false
        SUAllowsAutomaticUpdates: true

  # Same code, Home Depot catalog. Its own bundle ID and feed keep Sparkle
  # from ever updating one flavor with the other (spec §6).
  SkillsManagerHomeDepot:
    type: application
    platform: macOS
    sources:
      - App
      - path: Catalogs/HomeDepot/Recommendations.json
        buildPhase: resources
    dependencies:
      - package: SkillsManagerCore
      - package: Sparkle
      - sdk: FoundationModels.framework
        weak: true
    settings:
      base:
        PRODUCT_NAME: "Skills Manager for Home Depot"
        PRODUCT_BUNDLE_IDENTIFIER: com.henrykkim.SkillsManagerHomeDepot
        SU_FEED_URL: "https://github.com/henrykkim/skills-manager/releases/latest/download/appcast-homedepot.xml"
    info:
      path: App/Info-HomeDepot.plist
      properties:
        CFBundleDisplayName: "Skills Manager for Home Depot"
        CFBundleIconFile: AppIcon
        CFBundleShortVersionString: "$(MARKETING_VERSION)"
        CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"
        LSApplicationCategoryType: public.app-category.developer-tools
        NSHumanReadableCopyright: ""
        SUFeedURL: "$(SU_FEED_URL)"
        SUPublicEDKey: "$(SPARKLE_PUBLIC_KEY)"
        SUEnableAutomaticChecks: "$(SU_AUTOMATIC_CHECKS)"
        SUAutomaticallyUpdate: false
        SUAllowsAutomaticUpdates: true

schemes:
  SkillsManager:
    build:
      targets:
        SkillsManager: all
    run:
      config: Debug
  SkillsManagerHomeDepot:
    build:
      targets:
        SkillsManagerHomeDepot: all
    run:
      config: Debug
```

Also add `App/Info-HomeDepot.plist` on its own line to `.gitignore`, directly under `App/Info.plist`.

- [ ] **Step 6: Generate and build both schemes**

Run:

```bash
xcodegen generate && xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManagerHomeDepot -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

Expected: `BUILD SUCCEEDED` twice. Then verify the catalog and identity landed:

```bash
cat "build/Build/Products/Debug/Skills Manager for Home Depot.app/Contents/Resources/Recommendations.json" | head -3
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "build/Build/Products/Debug/Skills Manager for Home Depot.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "build/Build/Products/Debug/Skills Manager for Home Depot.app/Contents/Info.plist"
cat "build/Build/Products/Debug/Skills Manager.app/Contents/Resources/Recommendations.json"
```

Expected: the Home Depot JSON title line, `com.henrykkim.SkillsManagerHomeDepot`, the `appcast-homedepot.xml` feed, and the empty general catalog.

- [ ] **Step 7: Commit**

```bash
git add Catalogs project.yml .gitignore SkillsManagerCore/Tests/SkillsManagerCoreTests/HomeDepotCatalogTests.swift
git commit -m "feat(home-depot): second app target with its own catalog, bundle ID and feed

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: `InventoryStore` loads the catalog and owns the dismissal flag

**Files:**
- Modify: `App/InventoryStore.swift:7-33` (properties and `init`), add two methods after `acknowledgeProjectAccess()`.

**Interfaces:**
- Consumes: `RecommendationsCatalog.load` (Task 1).
- Produces on `InventoryStore`:
  - `let recommendations: RecommendationsCatalog`
  - `private(set) var needsRecommendations: Bool` (true when catalog non-empty and not dismissed)
  - `func dismissRecommendations()` (sets the flag, persists it)

- [ ] **Step 1: Add the properties and loading**

In `InventoryStore`, after `private(set) var needsProjectAccessNote: Bool`, add:

```swift
    /// Bundled `Recommendations.json` (spec §4). Empty in the general build.
    let recommendations: RecommendationsCatalog
    /// True until the Recommended sheet is dismissed once (spec §5).
    private(set) var needsRecommendations: Bool
```

After `private static let scopeKey = "libraryScope"`, add:

```swift
    private static let recommendationsDismissedKey = "recommendationsDismissed"
```

In `init()`, after the `needsProjectAccessNote` line, add:

```swift
        let catalogData = Bundle.main.url(forResource: "Recommendations", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
        recommendations = RecommendationsCatalog.load(catalogData)
        needsRecommendations = !recommendations.isEmpty
            && !UserDefaults.standard.bool(forKey: Self.recommendationsDismissedKey)
```

After `acknowledgeProjectAccess()`, add:

```swift
    /// Any dismissal (Not now, Done, closing the sheet) is permanent; the
    /// sheet stays reachable from File → Recommended….
    func dismissRecommendations() {
        defaults.set(true, forKey: Self.recommendationsDismissedKey)
        needsRecommendations = false
    }
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add App/InventoryStore.swift
git commit -m "feat(recommendations): load bundled catalog and persist dismissal

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: `RecommendationsModel` (app)

**Files:**
- Create: `App/Recommendations/RecommendationsModel.swift`

**Interfaces:**
- Consumes: `RecommendationsCatalog`, `RecommendationItem` (Task 1); `RecommendationPlan` (Task 2); existing `InstallIntentParser`, `InstallResolver`, `Installer`, `InstallError`, `InstallSheetModel.sentence(for:)`, `ToolCheck`, `ClaudePaths`, `GitHubClient`, `CommandRunner`.
- Produces:
  - `@MainActor @Observable final class RecommendationsModel`
  - `enum ItemState: Equatable { case checking, ready(InstallPreview), installed, unavailable(String), installing, done, failed(message: String, log: String) }`
  - `let catalog: RecommendationsCatalog`
  - `private(set) var states: [String: ItemState]` keyed by `RecommendationItem.id`
  - `var selected: Set<String>`
  - `private(set) var missingTool: String?`
  - `private(set) var isInstalling: Bool`, `private(set) var finished: Bool`
  - `var canInstall: Bool`
  - `func summary(for preview: InstallPreview) -> String`
  - `func start()` (resolves all items; idempotent per sheet showing), `func install() async`, `func reset()`

- [ ] **Step 1: Write the model**

```swift
import Foundation
import Observation
import SkillsManagerCore

/// Drives the Recommended sheet (spec §5–6): resolves every catalog item
/// through the Install box's resolver, then installs the selected ones in
/// catalog order. One failure never stops the rest.
@MainActor
@Observable
final class RecommendationsModel {
    enum ItemState: Equatable {
        case checking
        case ready(InstallPreview)
        case installed
        case unavailable(String)
        case installing
        case done
        case failed(message: String, log: String)
    }

    let catalog: RecommendationsCatalog
    private(set) var states: [String: ItemState] = [:]
    var selected: Set<String> = []
    private(set) var missingTool: String?
    private(set) var isInstalling = false
    private(set) var finished = false

    private let resolver: InstallResolver
    private let installer: Installer
    private let runner: CommandRunner
    private var resolution: Task<Void, Never>?
    private var generation = 0

    init(catalog: RecommendationsCatalog, paths: ClaudePaths, github: GitHubClient, runner: CommandRunner) {
        self.catalog = catalog
        self.resolver = InstallResolver(github: github, paths: paths)
        self.installer = Installer(runner: runner)
        self.runner = runner
    }

    // MARK: resolution

    /// Resolves every item concurrently. Safe to call again: a newer call
    /// wins, exactly like `InstallSheetModel`'s generation counter.
    func start() {
        resolution?.cancel()
        generation += 1
        let gen = generation
        finished = false
        isInstalling = false
        selected = []
        missingTool = nil
        for item in catalog.items { states[item.id] = .checking }
        resolution = Task { [weak self] in
            guard let self else { return }
            await withTaskGroup(of: (String, ItemState).self) { group in
                for item in self.catalog.items {
                    group.addTask { [resolver = self.resolver] in
                        let intent = InstallIntentParser.parse(item.source)
                        if case .unrecognized(let diagnosis) = intent { return (item.id, .unavailable(diagnosis)) }
                        do {
                            let preview = try await resolver.resolve(intent)
                            return (item.id, RecommendationPlan.isInstalled(preview) ? .installed : .ready(preview))
                        } catch let error as InstallError {
                            return (item.id, .unavailable(InstallSheetModel.sentence(for: error)))
                        } catch {
                            return (item.id, .unavailable("Couldn't reach GitHub. Check your connection."))
                        }
                    }
                }
                for await (id, state) in group {
                    guard !Task.isCancelled, gen == self.generation else { return }
                    self.states[id] = state
                    if case .ready = state { self.selected.insert(id) }
                }
            }
            guard gen == self.generation else { return }
            await self.checkTools(generation: gen)
        }
    }

    /// Skills repos need `npx`; plugins need `claude`. Only tools the
    /// selectable items actually use are checked, with the Install box's copy.
    private func checkTools(generation gen: Int) async {
        let kinds = Set(readyPreviews.values.map(\.kind))
        if kinds.contains(.skillsRepo), !(await ToolCheck.resolves("npx", runner: runner)) {
            guard gen == generation else { return }
            missingTool = "Node.js is needed to install skills. Install it from nodejs.org, then try again."
            return
        }
        if kinds.contains(.plugin), !(await ToolCheck.resolves("claude", runner: runner)) {
            guard gen == generation else { return }
            missingTool = "Claude Code's command-line tool wasn't found. Install Claude Code, then try again."
            return
        }
        guard gen == generation else { return }
        missingTool = nil
    }

    // MARK: derived

    private var readyPreviews: [String: InstallPreview] {
        states.reduce(into: [:]) { acc, pair in if case .ready(let p) = pair.value { acc[pair.key] = p } }
    }

    var canInstall: Bool {
        !isInstalling && !finished && missingTool == nil
            && !RecommendationPlan.make(items: catalog.items, previews: readyPreviews, selected: selected).isEmpty
    }

    var selectableIDs: [String] { catalog.items.map(\.id).filter { if case .ready = states[$0] { true } else { false } } }
    var allSelected: Bool { !selectableIDs.isEmpty && selectableIDs.allSatisfy { selected.contains($0) } }
    func selectAll() { selected.formUnion(selectableIDs) }
    func deselectAll() { selected.subtract(selectableIDs) }

    /// Status line under a ready row, e.g. "3 skills" or "Plugin from claude-plugins-official".
    func summary(for preview: InstallPreview) -> String {
        switch preview.kind {
        case .plugin:
            return "Plugin from \(preview.marketplace ?? "a marketplace")"
        case .skillsRepo:
            let n = RecommendationPlan.folders(toInstallFrom: preview).count
            let installed = preview.skills.filter { $0.isValid && $0.isInstalled }.count
            let base = n == 1 ? "1 skill" : "\(n) skills"
            return installed > 0 ? "\(base) (\(installed) already installed)" : base
        }
    }

    // MARK: install

    func install() async {
        guard canInstall else { return }
        let steps = RecommendationPlan.make(items: catalog.items, previews: readyPreviews, selected: selected)
        isInstalling = true
        for step in steps {
            states[step.itemID] = .installing
            switch await installer.install(step.preview, selectedFolders: step.folders) {
            case .success:
                states[step.itemID] = .done
            case .failure(let message, let log):
                states[step.itemID] = .failed(message: message, log: log)
            }
        }
        isInstalling = false
        finished = true
    }

    func reset() {
        resolution?.cancel()
        generation += 1
        states = [:]
        selected = []
        missingTool = nil
        isInstalling = false
        finished = false
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"`
Expected: `BUILD SUCCEEDED`. If Swift 6 complains that `InstallResolver` is captured in the task group, it is `Sendable` already; the `[resolver = self.resolver]` capture list is what keeps the closure free of `self`.

- [ ] **Step 3: Commit**

```bash
git add App/Recommendations/RecommendationsModel.swift
git commit -m "feat(recommendations): sheet model resolving and installing catalog items

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: `RecommendationsSheet`, presentation in `LibraryView`, and the menu item

**Files:**
- Create: `App/Recommendations/RecommendationsSheet.swift`
- Modify: `App/LibraryView.swift:23-31` (state), `:66-80` (sheet switch and notification), `:94-113` (`ActiveSheet` and `activeSheet`), `:595` (notification name)
- Modify: `App/SkillsManagerApp.swift:30-35` (menu)

**Interfaces:**
- Consumes: `RecommendationsModel` (Task 5), `InventoryStore.recommendations`, `.needsRecommendations`, `.dismissRecommendations()` (Task 4), `Spacing`, `Font.detailTitle`, `Font.cardLabel` (existing).
- Produces: `struct RecommendationsSheet: View { let model: RecommendationsModel; let onDone: () -> Void }`; `Notification.Name.showRecommendations`.

- [ ] **Step 1: Write the sheet**

```swift
import SwiftUI
import SkillsManagerCore

/// The Recommended sheet (spec §5). Rows mirror the Install box's skill rows;
/// the footer mirrors its Install/Done states.
struct RecommendationsSheet: View {
    @Bindable var model: RecommendationsModel
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header
            rows
            if let missing = model.missingTool {
                Label(missing, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.secondary)
            }
            footer
        }
        .padding(Spacing.xl)
        .frame(width: 560)
        .onAppear { model.start() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(model.catalog.title).font(.detailTitle).accessibilityAddTraits(.isHeader)
            if let intro = model.catalog.intro { Text(intro).foregroundStyle(.secondary) }
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Plugins and skills").textCase(.uppercase).tracking(0.4).font(.cardLabel).foregroundStyle(.secondary)
                Spacer()
                Button(model.allSelected ? "Deselect All" : "Select All") {
                    if model.allSelected { model.deselectAll() } else { model.selectAll() }
                }
                .buttonStyle(.link).font(.callout)
                .disabled(model.selectableIDs.isEmpty || model.isInstalling || model.finished)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.catalog.items) { item in
                        row(item)
                        if item.id != model.catalog.items.last?.id { Divider() }
                    }
                }
            }
            .frame(maxHeight: 320)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.quaternary))
        }
    }

    private func row(_ item: RecommendationItem) -> some View {
        let state = model.states[item.id] ?? .checking
        let selectable: Bool = { if case .ready = state { !model.isInstalling && !model.finished } else { false } }()
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Toggle(isOn: Binding(
                get: { model.selected.contains(item.id) },
                set: { on in if on { model.selected.insert(item.id) } else { model.selected.remove(item.id) } }
            )) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(item.name).lineLimit(1).truncationMode(.tail)
                    if let blurb = item.blurb { Text(blurb).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    status(state)
                }
            }
            .toggleStyle(.checkbox)
            .disabled(!selectable)
            .accessibilityLabel(accessibilityLabel(item, state))
            if case .failed(_, let log) = state {
                DisclosureGroup("Show Details") {
                    ScrollView { Text(log).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(maxHeight: 120)
                }
                .font(.caption)
                .padding(.leading, Spacing.lg + Spacing.xs)
            }
        }
        .padding(Spacing.sm)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func status(_ state: RecommendationsModel.ItemState) -> some View {
        switch state {
        case .checking:
            HStack(spacing: Spacing.xs) { ProgressView().controlSize(.mini); Text("Checking…") }
                .font(.metadata).foregroundStyle(.tertiary)
        case .ready(let preview):
            Text(model.summary(for: preview)).font(.metadata).foregroundStyle(.tertiary)
        case .installed:
            Text("Already installed").font(.metadata).foregroundStyle(.tertiary)
        case .unavailable(let sentence):
            Label(sentence, systemImage: "exclamationmark.triangle").font(.metadata).foregroundStyle(.secondary)
        case .installing:
            HStack(spacing: Spacing.xs) { ProgressView().controlSize(.mini); Text("Installing…") }
                .font(.metadata).foregroundStyle(.secondary)
        case .done:
            Label("Installed", systemImage: "checkmark.circle").font(.metadata).foregroundStyle(.secondary)
        case .failed(let message, _):
            Label(message, systemImage: "exclamationmark.triangle").font(.metadata).foregroundStyle(.secondary)
        }
    }

    private func accessibilityLabel(_ item: RecommendationItem, _ state: RecommendationsModel.ItemState) -> String {
        var parts = [item.name]
        if let blurb = item.blurb { parts.append(blurb) }
        switch state {
        case .checking: parts.append("Checking")
        case .ready(let p): parts.append(model.summary(for: p))
        case .installed: parts.append("Already installed, can't be selected")
        case .unavailable(let s): parts.append("Unavailable. \(s)")
        case .installing: parts.append("Installing")
        case .done: parts.append("Installed")
        case .failed(let m, _): parts.append("Failed. \(m)")
        }
        return parts.joined(separator: ". ")
    }

    private var footer: some View {
        HStack {
            Spacer()
            if model.finished {
                Button("Done") { model.reset(); onDone() }.keyboardShortcut(.defaultAction)
            } else if model.isInstalling {
                Button("Cancel") {}.disabled(true).accessibilityHint("Installing — please wait")
            } else {
                Button("Not Now") { model.reset(); onDone() }.keyboardShortcut(.cancelAction)
                Button("Install Selected") { Task { await model.install() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canInstall)
            }
        }
    }
}
```

`Font.metadata` is used by `InstallSheet.skillRow`; confirm it exists in `App/DesignSystem.swift` (grep `static let metadata`). If it does not, use `.caption2` in its place.

- [ ] **Step 2: Wire presentation in `LibraryView`**

After `@State private var dismissedAccessNote = false` add:

```swift
    @State private var showRecommendations = false
    @State private var recommendationsModel: RecommendationsModel?
```

Change `ActiveSheet` to:

```swift
    private enum ActiveSheet: Identifiable {
        case install, projectAccess, recommendations
        var id: Self { self }
    }
```

Change `activeSheet` to:

```swift
    /// Install wins while it's open; then the first-run access note; then
    /// the Recommended sheet (first launch, or File → Recommended…).
    private var activeSheet: Binding<ActiveSheet?> {
        Binding(
            get: {
                if showInstall { return .install }
                if store.needsProjectAccessNote && !dismissedAccessNote { return .projectAccess }
                if showRecommendations || store.needsRecommendations { return .recommendations }
                return nil
            },
            set: { newValue in
                guard newValue == nil else { return }
                if showInstall { showInstall = false }
                else if store.needsProjectAccessNote && !dismissedAccessNote { dismissedAccessNote = true }
                else { closeRecommendations() }
            })
    }

    private func closeRecommendations() {
        showRecommendations = false
        store.dismissRecommendations()
    }
```

In the `.sheet(item:)` switch add:

```swift
            case .recommendations:
                RecommendationsSheet(model: recommendationsModelInstance) { closeRecommendations() }
```

Add this computed property next to `activeSheet` (one model per window, built lazily so the general build never allocates one):

```swift
    private var recommendationsModelInstance: RecommendationsModel {
        if let recommendationsModel { return recommendationsModel }
        let m = RecommendationsModel(catalog: store.recommendations, paths: ClaudePaths(),
                                     github: URLSessionGitHubClient(), runner: ShellCommandRunner())
        // Assigning @State inside a computed getter is allowed in SwiftUI; the
        // next render reads the stored instance.
        DispatchQueue.main.async { recommendationsModel = m }
        return m
    }
```

After the `.showInstallSheet` `.onReceive`, add:

```swift
        .onReceive(NotificationCenter.default.publisher(for: .showRecommendations)) { _ in showRecommendations = true }
```

Next to `static let showInstallSheet` add:

```swift
    static let showRecommendations = Notification.Name("SkillsManager.showRecommendations")
```

- [ ] **Step 3: Add the menu item**

In `SkillsManagerApp.swift`, inside `CommandGroup(replacing: .newItem)` after the `Add Folder…` button:

```swift
                if !store.recommendations.isEmpty {
                    Divider()
                    Button("Recommended…") { NotificationCenter.default.post(name: .showRecommendations, object: nil) }
                }
```

- [ ] **Step 4: Build both schemes**

Run:

```bash
xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManagerHomeDepot -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

Expected: `BUILD SUCCEEDED` twice.

- [ ] **Step 5: Manual check, both flavors**

Reset the flag and launch the Home Depot build:

```bash
defaults delete com.henrykkim.SkillsManagerHomeDepot recommendationsDismissed 2>/dev/null; open "build/Build/Products/Debug/Skills Manager for Home Depot.app"
```

Check, in order:
- The Recommended sheet appears after the first-run project access note (or immediately if that was already acknowledged). Four rows resolve to summaries; any already-installed item shows "Already installed" with its checkbox off.
- **Not Now** closes it. Quit and relaunch: no sheet. **File → Recommended…** reopens it.
- Uncheck all but one, **Install Selected**: the row shows "Installing…" then "Installed"; the footer becomes **Done**; the library behind the sheet shows the new entry after the watcher fires.
- Relaunch and open **File → Recommended…**: that item is "Already installed".

Launch the general build: `open "build/Build/Products/Debug/Skills Manager.app"`. No sheet, and the File menu has no **Recommended…** item.

- [ ] **Step 6: Commit**

```bash
git add App/Recommendations/RecommendationsSheet.swift App/LibraryView.swift App/SkillsManagerApp.swift
git commit -m "feat(recommendations): first-launch sheet and File → Recommended…

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Scripts learn the second flavor

**Files:**
- Modify: `scripts/install-local.sh` (flag `--home-depot`)
- Modify: `scripts/check-update-settings.sh` (optional third argument: expected feed URL)
- Modify: `scripts/make-dmg.sh` (optional third argument: volume name)
- Modify: `scripts/make-appcast.sh` (optional `--title`)
- Modify: `scripts/tests/test-make-appcast.sh` (assert the default and custom title)

**Interfaces:**
- Produces: `scripts/install-local.sh [--home-depot]`; `scripts/check-update-settings.sh <App.app> <YES|NO> [feed-url]`; `scripts/make-dmg.sh <App.app> <out.dmg> [volname]`; `scripts/make-appcast.sh ... [--title <text>]`.

- [ ] **Step 1: Extend the appcast test first**

Append to `scripts/tests/test-make-appcast.sh`, before the "Missing notes must fail" block:

```zsh
[[ "$(x 'string(//channel/title)')" == "Skills Manager" ]] || fail "default channel title"
scripts/make-appcast.sh --version 0.2.0 --build 42 --title "Skills Manager for Home Depot" \
  --url "https://example.com/SkillsManagerHomeDepot-0.2.0.dmg" \
  --sign-output 'sparkle:edSignature="QUJD" length="12345"' \
  --notes "$T/notes.md" --out "$T/appcast-hd.xml"
[[ "$(xmllint --xpath 'string(//channel/title)' "$T/appcast-hd.xml")" == "Skills Manager for Home Depot" ]] || fail "custom channel title"
```

Run: `scripts/tests/test-make-appcast.sh`
Expected: fails on `--title` (unknown option from `zparseopts -F`).

- [ ] **Step 2: Add `--title` to `make-appcast.sh`**

Change the `zparseopts` line and the variable block to:

```zsh
zparseopts -D -E -F -A opt -- -version: -build: -url: -sign-output: -notes: -out: -title:
VERSION="${opt[--version]}"; BUILD="${opt[--build]}"; URL="${opt[--url]}"
SIGN="${opt[--sign-output]}"; NOTES="${opt[--notes]}"; OUT="${opt[--out]}"
TITLE="${opt[--title]:-Skills Manager}"
```

And in the heredoc replace `<title>Skills Manager</title>` with `<title>$(esc "$TITLE")</title>`.

Run: `scripts/tests/test-make-appcast.sh`
Expected: passes.

- [ ] **Step 3: Volume name for `make-dmg.sh`**

Replace the body after `set -euo pipefail` with:

```zsh
APP="$1"; OUT="$2"; VOLNAME="${3:-Skills Manager}"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$OUT"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDZO -quiet "$OUT"
rm -rf "$STAGE"
echo "wrote $OUT"
```

Update the usage comment to `Usage: scripts/make-dmg.sh <path/to/App.app> <out.dmg> [volume name]`.

- [ ] **Step 4: Feed argument for `check-update-settings.sh`**

Replace the `APP=`/`FEED=` lines with:

```zsh
APP="$1"; EXPECT_CHECKS="$2"
PLIST="$APP/Contents/Info.plist"
FEED="${3:-https://github.com/henrykkim/skills-manager/releases/latest/download/appcast.xml}"
```

Update the usage comment to `Usage: scripts/check-update-settings.sh <App.app> <YES|NO> [feed-url]`.

- [ ] **Step 5: `--home-depot` for `install-local.sh`**

Replace the `APP_NAME=` line and the `xcodebuild` scheme with:

```zsh
SCHEME="SkillsManager"; APP_NAME="Skills Manager"
if [[ "${1:-}" == "--home-depot" ]]; then SCHEME="SkillsManagerHomeDepot"; APP_NAME="Skills Manager for Home Depot"; fi
DEST="/Applications/$APP_NAME.app"
```

and change `-scheme SkillsManager` to `-scheme "$SCHEME"`. Update the usage comment to `Usage: scripts/install-local.sh [--home-depot]`. The "Removing stray Debug builds" `find` already uses `$APP_NAME`, so it cleans the right flavor.

- [ ] **Step 6: Verify the scripts**

```bash
scripts/tests/test-make-appcast.sh
zsh -n scripts/install-local.sh && zsh -n scripts/make-dmg.sh && zsh -n scripts/check-update-settings.sh
scripts/check-update-settings.sh "build/Build/Products/Debug/Skills Manager for Home Depot.app" NO "https://github.com/henrykkim/skills-manager/releases/latest/download/appcast-homedepot.xml"
scripts/check-update-settings.sh "build/Build/Products/Debug/Skills Manager.app" NO
```

Expected: appcast test passes, syntax checks print nothing, both update-settings checks print `✓ update settings OK (NO)`.

- [ ] **Step 7: Commit**

```bash
git add scripts
git commit -m "build: scripts accept the Home Depot flavor (scheme, feed, DMG volume, appcast title)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Release workflow builds and publishes both apps

**Files:**
- Modify: `.github/workflows/release.yml` (Build through Publish steps)
- Create: `packaging/homebrew/skills-manager-home-depot.rb`
- Modify: `README.md` (short "Home Depot build" note under installation)

**Interfaces:**
- Consumes: script flags from Task 7.
- Produces per tag: `SkillsManager-X.Y.Z.dmg`, `SkillsManagerHomeDepot-X.Y.Z.dmg`, their `.sha256` files, `appcast.xml`, `appcast-homedepot.xml`, all on one GitHub release.

- [ ] **Step 1: Rewrite the Build step to build both schemes**

Replace the `Build` step's `run:` with:

```yaml
        run: |
          VERSION="${GITHUB_REF_NAME#v}"
          xcodegen generate
          # CURRENT_PROJECT_VERSION comes from GITHUB_RUN_NUMBER and Sparkle compares
          # it to decide what's newer; renaming/recreating this workflow resets the
          # counter and would stop updates reaching existing installs.
          for SCHEME in SkillsManager SkillsManagerHomeDepot; do
            xcodebuild -project SkillsManager.xcodeproj -scheme "$SCHEME" \
              -configuration Release -derivedDataPath build \
              MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$GITHUB_RUN_NUMBER" ENABLE_HARDENED_RUNTIME=YES \
              SU_AUTOMATIC_CHECKS=YES \
              CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM="$TEAM_ID" \
              OTHER_CODE_SIGN_FLAGS="--timestamp" build
          done
          codesign --verify --deep --strict --verbose=2 "build/Build/Products/Release/Skills Manager.app"
          codesign --verify --deep --strict --verbose=2 "build/Build/Products/Release/Skills Manager for Home Depot.app"
          scripts/check-update-settings.sh "build/Build/Products/Release/Skills Manager.app" YES
          scripts/check-update-settings.sh "build/Build/Products/Release/Skills Manager for Home Depot.app" YES \
            "https://github.com/henrykkim/skills-manager/releases/latest/download/appcast-homedepot.xml"
          echo "VERSION=$VERSION" >> "$GITHUB_ENV"
```

- [ ] **Step 2: Loop the re-sign step over both apps**

Replace the `Re-sign Sparkle for notarization` step's `run:` with:

```yaml
        run: |
          ID="Developer ID Application"
          SIGN=(codesign -f -s "$ID" -o runtime --timestamp)
          for APP in "build/Build/Products/Release/Skills Manager.app" "build/Build/Products/Release/Skills Manager for Home Depot.app"; do
            FW="$APP/Contents/Frameworks/Sparkle.framework"
            "${SIGN[@]}" "$FW/Versions/B/XPCServices/Installer.xpc"
            "${SIGN[@]}" --preserve-metadata=entitlements "$FW/Versions/B/XPCServices/Downloader.xpc"
            "${SIGN[@]}" "$FW/Versions/B/Autoupdate"
            "${SIGN[@]}" "$FW/Versions/B/Updater.app"
            "${SIGN[@]}" "$FW"
            "${SIGN[@]}" --preserve-metadata=entitlements "$APP"
            codesign --verify --deep --strict --verbose=2 "$APP"
            # Notarization requires the hardened runtime on the app itself.
            codesign -dv "$APP" 2>&1 | grep -q "flags=.*runtime" || { echo "::error::$APP is missing the hardened runtime"; exit 1; }
          done
```

- [ ] **Step 3: Package both DMGs**

Replace the `Package DMG` step's `run:` with:

```yaml
        run: |
          scripts/make-dmg.sh "build/Build/Products/Release/Skills Manager.app" "SkillsManager-$VERSION.dmg"
          scripts/make-dmg.sh "build/Build/Products/Release/Skills Manager for Home Depot.app" "SkillsManagerHomeDepot-$VERSION.dmg" "Skills Manager for Home Depot"
```

- [ ] **Step 4: Notarize both DMGs**

Replace the `Notarize and staple` step's `run:` with:

```yaml
        run: |
          echo "$KEY_P8" > "$RUNNER_TEMP/AuthKey.p8"
          AUTH=(--key "$RUNNER_TEMP/AuthKey.p8" --key-id "$KEY_ID" --issuer "$ISSUER_ID")
          for DMG in "SkillsManager-$VERSION.dmg" "SkillsManagerHomeDepot-$VERSION.dmg"; do
            xcrun notarytool submit "$DMG" "${AUTH[@]}" --wait --output-format json > notary.json || true
            cat notary.json
            ID=$(python3 -c 'import json;print(json.load(open("notary.json"))["id"])')
            STATUS=$(python3 -c 'import json;print(json.load(open("notary.json"))["status"])')
            if [ "$STATUS" != "Accepted" ]; then
              echo "::group::Apple notarization log ($DMG)"
              xcrun notarytool log "$ID" "${AUTH[@]}"
              echo "::endgroup::"
              rm "$RUNNER_TEMP/AuthKey.p8"
              exit 1
            fi
            xcrun stapler staple "$DMG"
          done
          rm "$RUNNER_TEMP/AuthKey.p8"
```

- [ ] **Step 5: Sign and write both appcasts**

Replace the `Sign update and write appcast` step's `run:` with:

```yaml
        run: |
          SIGN_UPDATE="build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
          [ -x "$SIGN_UPDATE" ] || { echo "::error::sign_update not found in the SwiftPM Sparkle artifact"; exit 1; }
          sign_one() {   # <dmg> <appcast out> <channel title> <app path>
            local DMG="$1" OUT="$2" TITLE="$3" APP="$4"
            local SIGN_OUT
            SIGN_OUT=$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - "$DMG")
            scripts/make-appcast.sh --version "$VERSION" --build "$GITHUB_RUN_NUMBER" --title "$TITLE" \
              --url "https://github.com/${GITHUB_REPOSITORY}/releases/download/${GITHUB_REF_NAME}/$DMG" \
              --sign-output "$SIGN_OUT" --notes "release-notes/$VERSION.md" --out "$OUT"
            xmllint --noout "$OUT"
            local PUB SIG
            PUB=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$APP/Contents/Info.plist")
            SIG=$(sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p' <<< "$SIGN_OUT")
            swift scripts/verify-update-signature.swift "$DMG" "$SIG" "$PUB"
          }
          sign_one "SkillsManager-$VERSION.dmg" appcast.xml "Skills Manager" "build/Build/Products/Release/Skills Manager.app"
          sign_one "SkillsManagerHomeDepot-$VERSION.dmg" appcast-homedepot.xml "Skills Manager for Home Depot" "build/Build/Products/Release/Skills Manager for Home Depot.app"
```

- [ ] **Step 6: Publish everything on one release**

Replace the `Publish release` step's `run:` with:

```yaml
        run: |
          shasum -a 256 "SkillsManager-$VERSION.dmg" > "SkillsManager-$VERSION.dmg.sha256"
          shasum -a 256 "SkillsManagerHomeDepot-$VERSION.dmg" > "SkillsManagerHomeDepot-$VERSION.dmg.sha256"
          gh release create "$GITHUB_REF_NAME" \
            "SkillsManager-$VERSION.dmg" "SkillsManager-$VERSION.dmg.sha256" appcast.xml \
            "SkillsManagerHomeDepot-$VERSION.dmg" "SkillsManagerHomeDepot-$VERSION.dmg.sha256" appcast-homedepot.xml \
            --title "Skills Manager $VERSION" --generate-notes
```

- [ ] **Step 7: Add the Home Depot cask template**

`packaging/homebrew/skills-manager-home-depot.rb`:

```ruby
# Homebrew cask for Skills Manager for Home Depot. Lives in the
# henrykkim/homebrew-tap repo as Casks/skills-manager-home-depot.rb; copy it
# there and bump version + sha256 per release (same version as skills-manager).
cask "skills-manager-home-depot" do
  version "0.5.0"
  sha256 "REPLACE_WITH_SHA256_FROM_THE_RELEASE"

  url "https://github.com/henrykkim/skills-manager/releases/download/v#{version}/SkillsManagerHomeDepot-#{version}.dmg"
  name "Skills Manager for Home Depot"
  desc "Skills Manager with a starter set of recommended Claude Code skills and plugins"
  homepage "https://github.com/henrykkim/skills-manager"

  # Sparkle updates the app in place; brew shouldn't fight it.
  auto_updates true
  depends_on macos: :sonoma

  app "Skills Manager for Home Depot.app"

  zap trash: [
    "~/Library/Preferences/com.henrykkim.SkillsManagerHomeDepot.plist",
  ]
end
```

The sha256 placeholder is filled at the first release that includes this build, the same manual step the general cask already needs.

- [ ] **Step 8: README note**

Under the existing installation section of `README.md`, add:

```markdown
### Skills Manager for Home Depot

The same app with a starter list of recommended plugins and skills shown on first launch (Superpowers, Agentation, Emil's Skills, Jakub's Skills). Download `SkillsManagerHomeDepot-<version>.dmg` from the latest release, or `brew install henrykkim/tap/skills-manager-home-depot`. It updates on the same schedule as the general app.
```

- [ ] **Step 9: Validate the workflow file and scripts**

```bash
python3 -c 'import yaml,sys; yaml.safe_load(open(".github/workflows/release.yml")); print("yaml ok")'
scripts/tests/test-make-appcast.sh
```

Expected: `yaml ok` and the appcast test passes. (If PyYAML is not installed, `ruby -ryaml -e 'YAML.load_file(".github/workflows/release.yml"); puts "yaml ok"'`.)

- [ ] **Step 10: Commit**

```bash
git add .github/workflows/release.yml packaging/homebrew/skills-manager-home-depot.rb README.md
git commit -m "release: build, notarize and publish the Home Depot flavor alongside the general app

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: Full verification and local install

**Files:** none new.

- [ ] **Step 1: Run the whole Core suite**

Run: `cd SkillsManagerCore && swift test`
Expected: all tests pass, including the 19 new ones from Tasks 1 to 3.

- [ ] **Step 2: Run the script tests**

Run: `scripts/tests/test-make-appcast.sh && scripts/tests/test-verify-signature.sh`
Expected: both pass.

- [ ] **Step 3: Release-configuration build of both schemes**

```bash
xcodegen generate
for S in SkillsManager SkillsManagerHomeDepot; do xcodebuild -project SkillsManager.xcodeproj -scheme "$S" -configuration Release -derivedDataPath build build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"; done
```

Expected: `BUILD SUCCEEDED` twice.

- [ ] **Step 4: Install the general build locally (owner rule)**

Run: `scripts/install-local.sh`
Expected: ends with `▸ Running`. The general app shows no Recommended sheet and no menu item. Per the owner's rule, only one copy lives in `/Applications`; do not also install the Home Depot flavor there unless asked.

- [ ] **Step 5: Final commit check**

Run: `git status --short`
Expected: clean. If anything is left, commit it with a message that names the task it belongs to.
