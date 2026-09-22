# Detail Provenance & Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move "Updated" dates out of the sidebar into the detail headers, remove the visible Refresh button, and turn plugin/skill provenance into real clickable Author / Source / Marketplace links backed by data already on disk.

**Architecture:** Two read-only data additions in `SkillsManagerCore` (plugin manifest + marketplace URLs; the skills.sh lock file at `~/.agents/.skill-lock.json`) flow into new optional fields on `Plugin` and `Skill`. The SwiftUI app gains one shared `SourceLink` component and reworks the two detail views and the sidebar rows. No new dependencies, no writes to disk.

**Tech Stack:** Swift 6 / SwiftUI, macOS 14+, Swift Testing (`@Test`, `#expect`), XcodeGen. Spec: `docs/superpowers/specs/2026-09-21-detail-provenance-design.md`.

## Global Constraints

- Every reader is lenient: a missing or malformed file yields `nil` fields, never a `ParseIssue`, never a crash (spec §3).
- The app never writes to any file it reads. Read-only in v1.
- All new `Skill` / `Plugin` fields are optional with defaulted initializer parameters so existing call sites (`InvocationTests.makeSkill`) keep compiling.
- Copy is sentence case, plain English, written for someone who has never opened a terminal.
- Spacing uses only the `Spacing` scale in `App/DesignSystem.swift`. Motion is critically damped only.
- **UI tasks (5, 6, 7) MUST invoke the design skills** `apple-design`, `make-interfaces-feel-better`, `emil-design-eng`, and `better-ui` before editing views, and apply: tabular figures on dates/versions, optical alignment of dot + badge to the title, comfortable link hit areas, no layout shift when optional rows are absent (spec §4).
- Sidebar navigation model is out of scope: `DisclosureGroup` chevrons and sticky expansion stay exactly as they are.
- Core tests: `cd SkillsManagerCore && swift test`. App build: from repo root, `xcodegen generate && xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -derivedDataPath build build`.
- Commit after every task with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` as the last line.

---

## File map

| File | Change |
|---|---|
| `SkillsManagerCore/Sources/SkillsManagerCore/ClaudePaths.swift` | add `agentsLockFile` |
| `SkillsManagerCore/Sources/SkillsManagerCore/SkillLock.swift` | **new** — lock-file model + reader |
| `SkillsManagerCore/Sources/SkillsManagerCore/Models.swift` | `Skill` gains `sourceURL`, `sourceLabel`, `installedAt`, `updatedAt` |
| `SkillsManagerCore/Sources/SkillsManagerCore/SkillScanner.swift` | accepts a `SkillLock`, fills the new fields |
| `SkillsManagerCore/Sources/SkillsManagerCore/Inventory.swift` | loads the lock once, passes it to both scans |
| `SkillsManagerCore/Sources/SkillsManagerCore/PluginModels.swift` | `Plugin` gains `authorName`, `authorURL`, `homepageURL`, `marketplaceURL`, `installedAt` |
| `SkillsManagerCore/Sources/SkillsManagerCore/PluginRegistry.swift` | reads manifest author/homepage/repository, marketplace URL, `installedAt` |
| `SkillsManagerCore/Sources/SkillsManagerCore/Version.swift` | bump `coreVersion` to `0.2.0` |
| `SkillsManagerCore/Tests/SkillsManagerCoreTests/FixtureHome.swift` | writes a lock file and a richer demo-plugin manifest |
| `SkillsManagerCore/Tests/SkillsManagerCoreTests/SkillLockTests.swift` | **new** |
| `SkillsManagerCore/Tests/SkillsManagerCoreTests/PluginRegistryTests.swift` | new provenance assertions |
| `SkillsManagerCore/Tests/SkillsManagerCoreTests/InventoryTests.swift` | lock wiring assertions |
| `SkillsManagerCore/Tests/SkillsManagerCoreTests/SmokeTests.swift` | version bump |
| `App/DesignSystem.swift` | **new** `SourceLink`, `UpdatedLabel` |
| `App/LibraryRows.swift` | drop "Updated" captions |
| `App/LibraryView.swift` | hide Refresh, keep ⌘R; pass parent plugin to skill detail |
| `App/PluginDetailView.swift` | header + Details rework |
| `App/SkillDetailView.swift` | header + Details rework |
| `README.md` | note that reload is automatic and ⌘R is a manual fallback |

---

### Task 1: Skill lock reader

**Files:**
- Modify: `SkillsManagerCore/Sources/SkillsManagerCore/ClaudePaths.swift`
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/SkillLock.swift`
- Create: `SkillsManagerCore/Tests/SkillsManagerCoreTests/SkillLockTests.swift`

**Interfaces:**
- Consumes: `ISODate.parse(_:)` (internal, `ISODate.swift`), `ClaudePaths`.
- Produces:
  ```swift
  public struct SkillLockEntry: Sendable, Equatable {
      public let sourceLabel: String?   // "owner/repo"
      public let sourceURL: URL?        // sourceUrl with trailing ".git" removed
      public let installedAt: Date?
      public let updatedAt: Date?
  }
  public struct SkillLock: Sendable {
      public static let empty: SkillLock
      public subscript(folderName: String) -> SkillLockEntry?
      public static func load(file: URL) -> SkillLock   // lenient
  }
  extension ClaudePaths { public var agentsLockFile: URL }  // ~/.agents/.skill-lock.json
  ```

- [ ] **Step 1: Write the failing tests**

Create `SkillsManagerCore/Tests/SkillsManagerCoreTests/SkillLockTests.swift`:

```swift
import Foundation
import Testing
@testable import SkillsManagerCore

private func writeTemp(_ contents: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "skill-lock-\(UUID().uuidString).json")
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}

@Test func parsesObservedLockSchema() throws {
    let file = try writeTemp(#"""
    { "version": 1,
      "skills": {
        "make-interfaces-feel-better": {
          "source": "jakubkrehel/make-interfaces-feel-better",
          "sourceType": "github",
          "sourceUrl": "https://github.com/jakubkrehel/make-interfaces-feel-better.git",
          "skillPath": "skills/make-interfaces-feel-better/SKILL.md",
          "skillFolderHash": "320672d0",
          "installedAt": "2026-05-16T20:41:54.277Z",
          "updatedAt": "2026-06-22T18:32:26.017Z"
        }
      },
      "dismissed": [], "lastSelectedAgents": [] }
    """#)
    defer { try? FileManager.default.removeItem(at: file) }

    let lock = SkillLock.load(file: file)
    let entry = try #require(lock["make-interfaces-feel-better"])
    #expect(entry.sourceLabel == "jakubkrehel/make-interfaces-feel-better")
    #expect(entry.sourceURL == URL(string: "https://github.com/jakubkrehel/make-interfaces-feel-better"))
    #expect(entry.installedAt != nil)
    #expect(entry.updatedAt != nil)
    #expect(entry.updatedAt! > entry.installedAt!)
    #expect(lock["not-there"] == nil)
}

@Test func missingLockFileIsEmpty() {
    let lock = SkillLock.load(file: URL(fileURLWithPath: "/definitely/not/real/.skill-lock.json"))
    #expect(lock["anything"] == nil)
}

@Test func malformedLockFileIsEmpty() throws {
    let file = try writeTemp("{ this is not json")
    defer { try? FileManager.default.removeItem(at: file) }
    #expect(SkillLock.load(file: file)["anything"] == nil)
}

@Test func lockEntryWithoutUrlStillCarriesDates() throws {
    let file = try writeTemp(#"{ "version": 1, "skills": { "local-only": { "installedAt": "2026-01-01T00:00:00Z" } } }"#)
    defer { try? FileManager.default.removeItem(at: file) }
    let entry = try #require(SkillLock.load(file: file)["local-only"])
    #expect(entry.sourceURL == nil)
    #expect(entry.sourceLabel == nil)
    #expect(entry.installedAt != nil)
}

@Test func agentsLockFilePath() {
    let paths = ClaudePaths(home: URL(fileURLWithPath: "/tmp/fakehome"))
    #expect(paths.agentsLockFile.path == "/tmp/fakehome/.agents/.skill-lock.json")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SkillsManagerCore && swift test --filter SkillLock`
Expected: compile error — `SkillLock` and `agentsLockFile` do not exist.

- [ ] **Step 3: Add the path**

In `ClaudePaths.swift`, after `sharedSkillsDir`:

```swift
    /// Written by the `npx skills` installer; records where each shared skill came from.
    public var agentsLockFile: URL { agentsDir.appending(path: ".skill-lock.json") }
```

- [ ] **Step 4: Write the reader**

Create `SkillsManagerCore/Sources/SkillsManagerCore/SkillLock.swift`:

```swift
import Foundation

/// One record from ~/.agents/.skill-lock.json — provenance the skills.sh
/// installer wrote when it added a shared skill.
public struct SkillLockEntry: Sendable, Equatable {
    public let sourceLabel: String?   // "owner/repo"
    public let sourceURL: URL?        // cloneable URL with a trailing ".git" removed
    public let installedAt: Date?
    public let updatedAt: Date?

    public init(sourceLabel: String?, sourceURL: URL?, installedAt: Date?, updatedAt: Date?) {
        self.sourceLabel = sourceLabel
        self.sourceURL = sourceURL
        self.installedAt = installedAt
        self.updatedAt = updatedAt
    }
}

/// Lookup keyed by skill folder name. Lenient: any problem reading the file
/// means an empty lock — the skills themselves are still perfectly valid.
public struct SkillLock: Sendable {
    private let entries: [String: SkillLockEntry]

    public static let empty = SkillLock(entries: [:])

    public init(entries: [String: SkillLockEntry]) {
        self.entries = entries
    }

    public subscript(folderName: String) -> SkillLockEntry? { entries[folderName] }

    public static func load(file: URL) -> SkillLock {
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let skills = json["skills"] as? [String: Any] else {
            return .empty
        }
        var entries: [String: SkillLockEntry] = [:]
        for (folder, value) in skills {
            guard let record = value as? [String: Any] else { continue }
            entries[folder] = SkillLockEntry(
                sourceLabel: record["source"] as? String,
                sourceURL: GitURL.browsable(record["sourceUrl"] as? String),
                installedAt: ISODate.parse(record["installedAt"] as? String),
                updatedAt: ISODate.parse(record["updatedAt"] as? String))
        }
        return SkillLock(entries: entries)
    }
}

/// Turns the URLs Claude Code and skills.sh store into something a browser can open.
enum GitURL {
    /// "https://github.com/o/r.git" → https://github.com/o/r ; nil/empty → nil.
    static func browsable(_ raw: String?) -> URL? {
        guard var string = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else {
            return nil
        }
        if string.hasSuffix(".git") { string.removeLast(4) }
        guard let url = URL(string: string), url.scheme == "https" || url.scheme == "http" else {
            return nil
        }
        return url
    }

    /// "owner/repo" (GitHub shorthand) → https://github.com/owner/repo
    static func github(repo: String?) -> URL? {
        guard let repo, repo.split(separator: "/").count == 2 else { return nil }
        return URL(string: "https://github.com/\(repo)")
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd SkillsManagerCore && swift test`
Expected: all previous 30 tests plus 5 new pass.

- [ ] **Step 6: Commit**

```bash
git add SkillsManagerCore/Sources/SkillsManagerCore/ClaudePaths.swift SkillsManagerCore/Sources/SkillsManagerCore/SkillLock.swift SkillsManagerCore/Tests/SkillsManagerCoreTests/SkillLockTests.swift
git commit -m "feat: lenient reader for the skills.sh lock file

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Skill provenance fields wired through the scanner and inventory

**Files:**
- Modify: `SkillsManagerCore/Sources/SkillsManagerCore/Models.swift`
- Modify: `SkillsManagerCore/Sources/SkillsManagerCore/SkillScanner.swift`
- Modify: `SkillsManagerCore/Sources/SkillsManagerCore/Inventory.swift`
- Modify: `SkillsManagerCore/Sources/SkillsManagerCore/PluginRegistry.swift` (one call site)
- Modify: `SkillsManagerCore/Tests/SkillsManagerCoreTests/FixtureHome.swift`
- Modify: `SkillsManagerCore/Tests/SkillsManagerCoreTests/InventoryTests.swift`

**Interfaces:**
- Consumes: `SkillLock`, `SkillLockEntry` from Task 1.
- Produces:
  ```swift
  // Skill gains, all defaulted to nil in init:
  public let sourceURL: URL?
  public let sourceLabel: String?
  public let installedAt: Date?
  public let updatedAt: Date?       // lock updatedAt; views fall back to lastModified
  // SkillScanner.scan gains a defaulted parameter:
  public static func scan(directory: URL, source: SkillSource, lock: SkillLock = .empty) -> ScanResult
  ```

- [ ] **Step 1: Extend the fixture with a lock file**

In `FixtureHome.swift`, inside `make()` after the `createSymbolicLink` call, add:

```swift
            try writeSkillLock(home: dest)
```

and add this private helper at the bottom of the enum:

```swift
    /// The record `npx skills add` leaves behind. Only shared-skill is listed —
    /// shared-only-skill deliberately has no record so tests cover both cases.
    private static func writeSkillLock(home: URL) throws {
        let json = #"""
        { "version": 1,
          "skills": {
            "shared-skill": {
              "source": "test-org/shared-skill",
              "sourceType": "github",
              "sourceUrl": "https://github.com/test-org/shared-skill.git",
              "skillPath": "SKILL.md",
              "installedAt": "2026-05-01T00:00:00Z",
              "updatedAt": "2026-06-01T00:00:00Z"
            }
          },
          "dismissed": [], "lastSelectedAgents": [] }
        """#
        try json.write(to: home.appending(path: ".agents/.skill-lock.json"),
                       atomically: true, encoding: .utf8)
    }
```

- [ ] **Step 2: Write the failing tests**

Append to `InventoryTests.swift`:

```swift
@Test func sharedSkillCarriesLockProvenance() throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let inventory = Inventory.load(paths: ClaudePaths(home: home))

    // shared-skill is symlinked into ~/.claude/skills, so it is listed as personal —
    // and must still pick up its lock record by folder name.
    let connected = try #require(inventory.personalSkills.first { $0.folderName == "shared-skill" })
    #expect(connected.sourceLabel == "test-org/shared-skill")
    #expect(connected.sourceURL == URL(string: "https://github.com/test-org/shared-skill"))
    #expect(connected.installedAt != nil)
    #expect(connected.updatedAt != nil)

    // shared-only-skill has no lock record: fields stay nil, skill still listed.
    let unrecorded = try #require(inventory.sharedSkills.first { $0.folderName == "shared-only-skill" })
    #expect(unrecorded.sourceURL == nil)
    #expect(unrecorded.updatedAt == nil)
}

@Test func plainPersonalSkillHasNoLockProvenance() throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let inventory = Inventory.load(paths: ClaudePaths(home: home))
    let good = try #require(inventory.personalSkills.first { $0.folderName == "good-skill" })
    #expect(good.sourceURL == nil)
    #expect(good.sourceLabel == nil)
    #expect(good.installedAt == nil)
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd SkillsManagerCore && swift test --filter Inventory`
Expected: compile error — `Skill` has no member `sourceLabel`.

- [ ] **Step 4: Add the fields to `Skill`**

In `Models.swift`, replace the `Skill` struct with:

```swift
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
    // Provenance from ~/.agents/.skill-lock.json when the skills.sh installer wrote one.
    public let sourceURL: URL?
    public let sourceLabel: String?     // "owner/repo"
    public let installedAt: Date?
    public let updatedAt: Date?         // views fall back to lastModified when nil

    public init(folderName: String, displayName: String, summary: String?, argumentHint: String?,
                userInvocable: Bool, modelInvocable: Bool, whenToUse: String?,
                source: SkillSource, directory: URL, lastModified: Date?,
                sourceURL: URL? = nil, sourceLabel: String? = nil,
                installedAt: Date? = nil, updatedAt: Date? = nil) {
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
        self.sourceURL = sourceURL
        self.sourceLabel = sourceLabel
        self.installedAt = installedAt
        self.updatedAt = updatedAt
    }
}
```

- [ ] **Step 5: Teach the scanner about the lock**

In `SkillScanner.swift`, change the signature to:

```swift
    public static func scan(directory: URL, source: SkillSource, lock: SkillLock = .empty) -> ScanResult {
```

and replace the `result.skills.append(Skill(...))` call with:

```swift
                let lockEntry = lock[entry.lastPathComponent]
                result.skills.append(Skill(
                    folderName: entry.lastPathComponent,
                    displayName: fm2.name ?? entry.lastPathComponent,
                    summary: fm2.description,
                    argumentHint: fm2.argumentHint,
                    userInvocable: fm2.userInvocable ?? true,
                    modelInvocable: !(fm2.disableModelInvocation ?? false),
                    whenToUse: fm2.whenToUse,
                    source: source,
                    directory: entry,
                    lastModified: modified,
                    sourceURL: lockEntry?.sourceURL,
                    sourceLabel: lockEntry?.sourceLabel,
                    installedAt: lockEntry?.installedAt,
                    updatedAt: lockEntry?.updatedAt))
```

Lookup is by folder name, which is how the lock file is keyed. A personal skill that is a symlink into `~/.agents/skills` keeps the same folder name, so it resolves too (the spec's realpath rule is satisfied by construction; no extra realpath call needed).

- [ ] **Step 6: Wire the lock in `Inventory.load`**

Replace the first four lines of `Inventory.load` with:

```swift
        let enabled = SettingsReader.enabledPlugins(settingsFile: paths.settingsFile)
        let lock = SkillLock.load(file: paths.agentsLockFile)
        let personal = SkillScanner.scan(directory: paths.personalSkillsDir, source: .personal, lock: lock)
        let shared = SkillScanner.scan(directory: paths.sharedSkillsDir, source: .shared, lock: lock)
        let pluginResult = PluginRegistry.loadPlugins(paths: paths, enabledPlugins: enabled)
```

The `PluginRegistry` call to `SkillScanner.scan` keeps using the default `.empty` lock — plugin skills get provenance from their plugin in Task 3, not from the lock.

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd SkillsManagerCore && swift test`
Expected: all pass (37 tests). `fixtureHomeMaterializesDotfoldersManifestsAndSymlinks` still passes.

- [ ] **Step 8: Commit**

```bash
git add SkillsManagerCore
git commit -m "feat: skills carry source link and install dates from the skills.sh lock file

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Plugin provenance fields from manifest and marketplace

**Files:**
- Modify: `SkillsManagerCore/Sources/SkillsManagerCore/PluginModels.swift`
- Modify: `SkillsManagerCore/Sources/SkillsManagerCore/PluginRegistry.swift`
- Modify: `SkillsManagerCore/Sources/SkillsManagerCore/Version.swift`
- Modify: `SkillsManagerCore/Tests/SkillsManagerCoreTests/FixtureHome.swift`
- Modify: `SkillsManagerCore/Tests/SkillsManagerCoreTests/PluginRegistryTests.swift`
- Modify: `SkillsManagerCore/Tests/SkillsManagerCoreTests/SmokeTests.swift`

**Interfaces:**
- Consumes: `GitURL.browsable(_:)`, `GitURL.github(repo:)` from Task 1.
- Produces:
  ```swift
  // InstalledPluginRecord gains:
  public let installedAt: Date?
  // Plugin gains, all defaulted to nil in init:
  public let authorName: String?
  public let authorURL: URL?
  public let homepageURL: URL?      // manifest homepage, else repository
  public let marketplaceURL: URL?   // from known_marketplaces.json
  public let installedAt: Date?
  ```

- [ ] **Step 1: Make the fixture manifest richer**

In `FixtureHome.swift`, change `writePluginManifest` so `demo-plugin` gets author and links while `disabled-plugin` stays minimal. Replace the two `writePluginManifest` calls and the helper with:

```swift
            try writePluginManifest(home: dest, marketplace: "test-market", plugin: "demo-plugin",
                                    version: "1.2.0", description: "Demo plugin for tests",
                                    extra: #"""
                                    , "author": { "name": "Test Author", "url": "https://example.com/author" },
                                      "homepage": "https://example.com/demo",
                                      "repository": "https://github.com/test-org/demo-plugin.git"
                                    """#)
            try writePluginManifest(home: dest, marketplace: "test-market", plugin: "disabled-plugin",
                                    version: "0.1.0", description: "Disabled in settings", extra: "")
```

```swift
    private static func writePluginManifest(home: URL, marketplace: String, plugin: String,
                                            version: String, description: String, extra: String) throws {
        let dir = home.appending(
            path: ".claude/plugins/cache/\(marketplace)/\(plugin)/\(version)/.claude-plugin")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = #"{ "name": "\#(plugin)", "version": "\#(version)", "description": "\#(description)"\#(extra) }"#
        try json.write(to: dir.appending(path: "plugin.json"), atomically: true, encoding: .utf8)
    }
```

- [ ] **Step 2: Write the failing tests**

Append to `PluginRegistryTests.swift`:

```swift
@Test func pluginReadsAuthorAndLinksFromManifestAndMarketplace() throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let result = PluginRegistry.loadPlugins(paths: ClaudePaths(home: home), enabledPlugins: [:])

    let demo = try #require(result.plugins.first { $0.pluginID == "demo-plugin@test-market" })
    #expect(demo.authorName == "Test Author")
    #expect(demo.authorURL == URL(string: "https://example.com/author"))
    #expect(demo.homepageURL == URL(string: "https://example.com/demo"))          // homepage wins over repository
    #expect(demo.marketplaceURL == URL(string: "https://github.com/test-org/test-market"))
    #expect(demo.installedAt != nil)
    #expect(demo.lastUpdated! > demo.installedAt!)

    let disabled = try #require(result.plugins.first { $0.pluginID == "disabled-plugin@test-market" })
    #expect(disabled.authorName == nil)
    #expect(disabled.authorURL == nil)
    #expect(disabled.homepageURL == nil)
    #expect(disabled.marketplaceURL == URL(string: "https://github.com/test-org/test-market"))
}

@Test func repositoryIsUsedWhenHomepageMissing() throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    // Overwrite the disabled plugin's manifest with repository only.
    let manifest = home.appending(
        path: ".claude/plugins/cache/test-market/disabled-plugin/0.1.0/.claude-plugin/plugin.json")
    try #"{ "name": "disabled-plugin", "repository": "https://github.com/test-org/disabled.git" }"#
        .write(to: manifest, atomically: true, encoding: .utf8)

    let result = PluginRegistry.loadPlugins(paths: ClaudePaths(home: home), enabledPlugins: [:])
    let disabled = try #require(result.plugins.first { $0.pluginID == "disabled-plugin@test-market" })
    #expect(disabled.homepageURL == URL(string: "https://github.com/test-org/disabled"))
}

@Test func marketplaceUrlDerivesFromGitUrlForm() throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let paths = ClaudePaths(home: home)
    try #"{ "test-market": { "source": { "source": "git", "url": "https://github.com/test-org/test-market.git" } } }"#
        .write(to: paths.knownMarketplacesFile, atomically: true, encoding: .utf8)

    let result = PluginRegistry.loadPlugins(paths: paths, enabledPlugins: [:])
    let demo = try #require(result.plugins.first { $0.pluginID == "demo-plugin@test-market" })
    #expect(demo.marketplaceURL == URL(string: "https://github.com/test-org/test-market"))
    #expect(demo.provenance == "Git: https://github.com/test-org/test-market.git") // sidebar text unchanged
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd SkillsManagerCore && swift test --filter PluginRegistry`
Expected: compile error — `Plugin` has no member `authorName`.

- [ ] **Step 4: Extend the models**

In `PluginRegistry.swift`, add `installedAt` to the record:

```swift
public struct InstalledPluginRecord: Sendable, Equatable {
    public let pluginID: String
    public let name: String
    public let marketplace: String
    public let version: String?
    public let installPath: String?
    public let installedAt: Date?
    public let lastUpdated: Date?
}
```

In `loadRecords`, add `let installedAt: String?` to `Entry` and pass
`installedAt: ISODate.parse(entry.installedAt),` before `lastUpdated:`.

In `PluginModels.swift`, replace `Plugin` with:

```swift
public struct Plugin: Identifiable, Sendable, Hashable {
    public var id: String { pluginID }
    public let pluginID: String         // "name@marketplace"
    public let name: String
    public let marketplace: String
    public let summary: String?         // description from .claude-plugin/plugin.json
    public let provenance: String?      // human origin, e.g. "GitHub: owner/repo"
    public let version: String?
    public let contentDirectory: URL    // where the installed copy lives
    public let lastUpdated: Date?
    public let isEnabled: Bool
    public let skills: [Skill]
    public let commands: [PluginCommand]
    // Provenance for the detail view. All optional — manifests vary wildly.
    public let authorName: String?
    public let authorURL: URL?
    public let homepageURL: URL?        // manifest homepage, else repository
    public let marketplaceURL: URL?     // derived from known_marketplaces.json
    public let installedAt: Date?

    public init(pluginID: String, name: String, marketplace: String, summary: String?,
                provenance: String?, version: String?, contentDirectory: URL,
                lastUpdated: Date?, isEnabled: Bool, skills: [Skill], commands: [PluginCommand],
                authorName: String? = nil, authorURL: URL? = nil, homepageURL: URL? = nil,
                marketplaceURL: URL? = nil, installedAt: Date? = nil) {
        self.pluginID = pluginID
        self.name = name
        self.marketplace = marketplace
        self.summary = summary
        self.provenance = provenance
        self.version = version
        self.contentDirectory = contentDirectory
        self.lastUpdated = lastUpdated
        self.isEnabled = isEnabled
        self.skills = skills
        self.commands = commands
        self.authorName = authorName
        self.authorURL = authorURL
        self.homepageURL = homepageURL
        self.marketplaceURL = marketplaceURL
        self.installedAt = installedAt
    }
}
```

- [ ] **Step 5: Read the manifest and marketplace URL**

In `PluginRegistry.swift`, replace `pluginDescription(contentDir:)` with a manifest struct reader:

```swift
    /// The fields we show from the plugin's own manifest. Every field optional.
    struct Manifest {
        var description: String?
        var authorName: String?
        var authorURL: URL?
        var homepageURL: URL?

        static func read(contentDir: URL) -> Manifest {
            let file = contentDir.appending(path: ".claude-plugin/plugin.json")
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return Manifest()
            }
            var m = Manifest()
            m.description = json["description"] as? String
            if let author = json["author"] as? [String: Any] {
                m.authorName = author["name"] as? String
                m.authorURL = GitURL.browsable(author["url"] as? String)
            } else if let author = json["author"] as? String {
                m.authorName = author            // some manifests use a bare string
            }
            m.homepageURL = GitURL.browsable(json["homepage"] as? String)
                ?? GitURL.browsable(json["repository"] as? String)
            return m
        }
    }
```

Replace `marketplaceProvenance` with a version that returns both the text and the URL:

```swift
    struct MarketplaceInfo {
        var provenance: String?   // sidebar caption text, unchanged from plan 1
        var url: URL?
    }

    /// Per marketplace, from known_marketplaces.json. Lenient: unreadable → empty.
    private static func marketplaceInfo(knownMarketplacesFile: URL) -> [String: MarketplaceInfo] {
        guard let data = try? Data(contentsOf: knownMarketplacesFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var result: [String: MarketplaceInfo] = [:]
        for (name, value) in json {
            guard let entry = value as? [String: Any],
                  let source = entry["source"] as? [String: Any] else { continue }
            if let repo = source["repo"] as? String {
                result[name] = MarketplaceInfo(provenance: "GitHub: \(repo)", url: GitURL.github(repo: repo))
            } else if let url = source["url"] as? String {
                result[name] = MarketplaceInfo(provenance: "Git: \(url)", url: GitURL.browsable(url))
            }
        }
        return result
    }
```

Then in `loadPlugins`, replace `let provenanceByMarketplace = marketplaceProvenance(...)` with
`let marketplaces = marketplaceInfo(knownMarketplacesFile: paths.knownMarketplacesFile)` and build the plugin as:

```swift
            let manifest = Manifest.read(contentDir: contentDir)
            let market = marketplaces[record.marketplace]
            result.plugins.append(Plugin(
                pluginID: record.pluginID,
                name: record.name,
                marketplace: record.marketplace,
                summary: manifest.description,
                provenance: market?.provenance,
                version: record.version,
                contentDirectory: contentDir,
                lastUpdated: record.lastUpdated,
                isEnabled: enabledPlugins[record.pluginID] ?? true,
                skills: scan.skills,
                commands: loadCommands(
                    pluginName: record.name,
                    commandsDir: contentDir.appending(path: "commands", directoryHint: .isDirectory)),
                authorName: manifest.authorName,
                authorURL: manifest.authorURL,
                homepageURL: manifest.homepageURL,
                marketplaceURL: market?.url,
                installedAt: record.installedAt))
```

- [ ] **Step 6: Bump the core version**

In `Version.swift` set `coreVersion` to `"0.2.0"`; in `SmokeTests.swift` expect `"0.2.0"`.

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd SkillsManagerCore && swift test`
Expected: 40 tests pass, including the pre-existing `loadsPluginsWithSkillsCommandsAndEnabledState` (`summary` and `provenance` unchanged).

- [ ] **Step 8: Commit**

```bash
git add SkillsManagerCore
git commit -m "feat: plugins carry author, homepage, marketplace links and install date

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Sidebar row cleanup and hidden refresh

**Files:**
- Modify: `App/LibraryRows.swift`
- Modify: `App/LibraryView.swift:24-35`
- Modify: `README.md`

**Interfaces:**
- Consumes: nothing new.
- Produces: no API changes. Behavior: no "Updated" text in the sidebar; no visible Refresh button; ⌘R still calls `store.reload()`.

Before editing, invoke `better-ui` and `make-interfaces-feel-better` (design-skill requirement, Global Constraints) and keep their guidance on hit areas and density in mind for the rows.

- [ ] **Step 1: Remove the dates from the rows**

In `LibraryRows.swift`, delete the `if let modified = skill.lastModified { ... }` block from `SkillRow`, and delete the `if let updated = plugin.lastUpdated { ... }` lines from `PluginRow.caption`. The rest of both views stays byte-for-byte the same.

- [ ] **Step 2: Hide the refresh control but keep ⌘R**

In `LibraryView.swift`, replace the whole `.toolbar { ... }` modifier with:

```swift
        // Reload is automatic (FSEvents). ⌘R stays as a silent manual fallback —
        // the user never needs to know it exists (owner feedback 2026-09-21).
        .background {
            Button("Refresh") { store.reload() }
                .keyboardShortcut("r")
                .disabled(store.isLoading)
                .hidden()
        }
```

`Button.hidden()` keeps the keyboard shortcut active in SwiftUI on macOS 14; if the build shows the shortcut is inert (verified in Step 4), fall back to adding a `CommandGroup(replacing: .toolbar)` in `SkillsManagerApp.swift` with the same button — but only after checking.

- [ ] **Step 3: Update the README sandbox note**

In `README.md`, after the "## Sandbox mode" section, add:

```markdown
## Reloading

The library reloads itself whenever a skill or plugin folder changes. If it
ever looks stale, press ⌘R to re-scan by hand.
```

- [ ] **Step 4: Build and check**

Run from repo root:
```bash
xcodegen generate && xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -derivedDataPath build build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

Then launch against a sandbox to confirm ⌘R still works:
```bash
rm -rf /private/tmp/skills-sandbox && mkdir -p /private/tmp/skills-sandbox/.claude/skills/first && printf -- '---\nname: first\ndescription: First\n---\n' > /private/tmp/skills-sandbox/.claude/skills/first/SKILL.md
SKILLS_MANAGER_HOME=/private/tmp/skills-sandbox "build/Build/Products/Debug/Skills Manager.app/Contents/MacOS/Skills Manager" &
```
Expected: sidebar shows "first" with no "Updated" line; toolbar has no refresh icon. Add a second folder the same way, press ⌘R, and "second" appears (it will also appear on its own within ~2 s — that is fine, the point is that ⌘R does not error). Quit the app and `rm -rf /private/tmp/skills-sandbox`.

- [ ] **Step 5: Commit**

```bash
git add App/LibraryRows.swift App/LibraryView.swift README.md
git commit -m "feat: sidebar rows drop dates; refresh becomes a hidden ⌘R fallback

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: `SourceLink` and `UpdatedLabel` design-system components

**Files:**
- Modify: `App/DesignSystem.swift`

**Interfaces:**
- Consumes: `Spacing`, `Font` extensions already in the file.
- Produces:
  ```swift
  struct SourceLink: View { let label: String; let url: URL }
  struct UpdatedLabel: View { let date: Date }        // "Updated Sep 11, 2026", muted, tabular
  extension Font { static let metadata: Font }        // caption, tabular figures
  ```

**REQUIRED before editing:** invoke `apple-design`, `make-interfaces-feel-better`, `emil-design-eng`, and `better-ui`. Apply: links get a full-row hit area (not just the text), an external-link glyph that reads as "leaves the app", hover shows the destination, and the pressed state is subtle (opacity, critically damped).

- [ ] **Step 1: Add the font**

In the `extension Font` block add:

```swift
    /// Dates, versions, counts — tabular so columns of metadata align.
    static let metadata = Font.caption.monospacedDigit()
```

- [ ] **Step 2: Add `UpdatedLabel`**

Append to `DesignSystem.swift`:

```swift
/// "Updated Sep 11, 2026" — muted, tabular, with the full timestamp on hover.
struct UpdatedLabel: View {
    let date: Date

    var body: some View {
        Text("Updated \(date.formatted(date: .abbreviated, time: .omitted))")
            .font(.metadata)
            .foregroundStyle(.tertiary)
            .help(date.formatted(date: .long, time: .shortened))
            .accessibilityLabel("Updated \(date.formatted(date: .long, time: .omitted))")
    }
}
```

- [ ] **Step 3: Add `SourceLink`**

Append to `DesignSystem.swift`:

```swift
/// An outbound link. The arrow tells the user it opens their browser; the
/// tooltip shows exactly where. Whole label is the hit area.
struct SourceLink: View {
    let label: String
    let url: URL
    @State private var hovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: Spacing.xs) {
                Text(label)
                    .underline(hovering, color: .accentColor)
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(Color.accentColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.15), value: hovering)
        .help(url.absoluteString)
        .accessibilityHint("Opens \(url.host() ?? "a web page") in your browser")
    }
}
```

- [ ] **Step 4: Build**

Run: `xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -derivedDataPath build build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **` (components compile even though nothing uses them yet).

- [ ] **Step 5: Commit**

```bash
git add App/DesignSystem.swift
git commit -m "feat: SourceLink and UpdatedLabel design-system components

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Plugin detail header and provenance links

**Files:**
- Modify: `App/PluginDetailView.swift`

**Interfaces:**
- Consumes: `Plugin.authorName/authorURL/homepageURL/marketplaceURL/installedAt/lastUpdated` (Task 3), `SourceLink`, `UpdatedLabel`, `Font.metadata` (Task 5).
- Produces: nothing new.

**REQUIRED before editing:** invoke `apple-design`, `make-interfaces-feel-better`, `emil-design-eng`, and `better-ui`. Apply: badge and dot sit on the title's baseline (use `.firstTextBaseline` alignment), Details rows keep constant height whether or not they contain a link, dates and version use `Font.metadata`.

- [ ] **Step 1: Rewrite the header**

Replace the `header` computed property with:

```swift
    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(plugin.name).font(.detailTitle)
                KindBadge(text: "Plugin", tint: .purple)
                StatusDot(isEnabled: plugin.isEnabled)
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 3 }
                if let updated = plugin.lastUpdated {
                    UpdatedLabel(date: updated)
                }
            }
            if let summary = plugin.summary {
                Text(summary).foregroundStyle(.secondary)
            }
        }
    }
```

- [ ] **Step 2: Rewrite the Details card**

Replace the `SectionCard(title: "Details") { ... }` block with:

```swift
                SectionCard(title: "Details") {
                    if let author = plugin.authorName {
                        LabeledContent("Author") {
                            if let url = plugin.authorURL {
                                SourceLink(label: author, url: url)
                            } else {
                                Text(author)
                            }
                        }
                    }
                    if let source = sourceLink {
                        LabeledContent("Source") { source }
                    }
                    LabeledContent("Marketplace") {
                        if let url = plugin.marketplaceURL {
                            SourceLink(label: marketplaceName, url: url)
                        } else {
                            Text(marketplaceName)
                        }
                    }
                    if let version = plugin.version {
                        LabeledContent("Version") { Text(version).font(.metadata) }
                    }
                    if let installed = plugin.installedAt {
                        LabeledContent("Installed") {
                            Text(installed.formatted(date: .abbreviated, time: .omitted)).font(.metadata)
                        }
                    }
                }
```

and add these helpers below `header`:

```swift
    /// Homepage first, then the marketplace repo — never a dead row.
    private var sourceLink: SourceLink? {
        if let url = plugin.homepageURL {
            return SourceLink(label: displayLabel(for: url), url: url)
        }
        if let url = plugin.marketplaceURL {
            return SourceLink(label: displayLabel(for: url), url: url)
        }
        return nil
    }

    /// "Anthropic official" reads better than "claude-plugins-official"; everything else as-is.
    private var marketplaceName: String {
        plugin.marketplace == "claude-plugins-official" ? "Anthropic official" : plugin.marketplace
    }

    /// "github.com/owner/repo" — host plus path, no scheme noise.
    private func displayLabel(for url: URL) -> String {
        let host = url.host() ?? ""
        let path = url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? host : "\(host)/\(path)"
    }
```

The old `Status`, `From`, and `Last updated` rows are gone: status is the header dot, provenance is now the links, updated is in the header.

- [ ] **Step 3: Build and eyeball**

Run: `xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -derivedDataPath build build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

Launch against the real home (no env var) with
`open "build/Build/Products/Debug/Skills Manager.app"`, select the **figma** plugin. Expected: header reads `figma  Plugin  ●  Updated Sep 11, 2026`; Details shows Author "Figma" (plain text, no URL in that manifest), Source `github.com/figma/mcp-server-guide` as a link, Marketplace "Anthropic official" as a link, Version, Installed. Clicking Source opens the browser. Select **superpowers**: Author "Jesse Vincent" is plain text, Source is `github.com/obra/superpowers`. Quit.

- [ ] **Step 4: Commit**

```bash
git add App/PluginDetailView.swift
git commit -m "feat: plugin detail shows updated date in header and clickable author, source, marketplace

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Skill detail header and provenance links

**Files:**
- Modify: `App/SkillDetailView.swift`
- Modify: `App/LibraryView.swift` (the `.skill(let id)` case in `detailView`)

**Interfaces:**
- Consumes: `Skill.sourceURL/sourceLabel/installedAt/updatedAt/lastModified` (Task 2), `Plugin.homepageURL/marketplaceURL/installedAt` (Task 3), `SourceLink`, `UpdatedLabel`, `Font.metadata` (Task 5).
- Produces: `SkillDetailView(skill:parentPlugin:)` — new optional `parentPlugin: Plugin?` parameter.

**REQUIRED before editing:** invoke `apple-design`, `make-interfaces-feel-better`, `emil-design-eng`, and `better-ui`. Same expectations as Task 6.

- [ ] **Step 1: Pass the parent plugin from the library**

In `LibraryView.swift` `detailView`, change the `.skill` case to:

```swift
        case .skill(let id):
            if let skill = allSkills.first(where: { $0.id == id }) {
                SkillDetailView(skill: skill, parentPlugin: parentPlugin(of: skill))
            } else {
                missingSelection
            }
```

and add next to `allSkills`:

```swift
    private func parentPlugin(of skill: Skill) -> Plugin? {
        guard case .plugin(let pluginID) = skill.source else { return nil }
        return store.inventory.plugins.first { $0.pluginID == pluginID }
    }
```

- [ ] **Step 2: Rewrite the skill detail**

In `SkillDetailView.swift`, add the property under `let skill: Skill`:

```swift
    let parentPlugin: Plugin?
```

Replace `header` with:

```swift
    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(skill.displayName).font(.detailTitle)
                switch skill.source {
                case .personal: KindBadge(text: "Skill", tint: .blue)
                case .shared: KindBadge(text: "Shared", tint: .teal)
                case .plugin: KindBadge(text: "Plugin Skill", tint: .purple)
                }
                if let updated = skill.updatedAt ?? skill.lastModified {
                    UpdatedLabel(date: updated)
                }
            }
            if let summary = skill.summary {
                Text(summary).foregroundStyle(.secondary)
            }
        }
    }
```

Replace the `SectionCard(title: "Details") { ... }` block with:

```swift
                SectionCard(title: "Details") {
                    LabeledContent("Location") {
                        HStack(spacing: Spacing.sm) {
                            Text(skill.directory.path)
                                .truncationMode(.middle)
                                .lineLimit(1)
                                .textSelection(.enabled)
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([skill.directory])
                            }
                            .buttonStyle(.link)
                        }
                    }
                    LabeledContent("Source") { sourceView }
                    if let installed = skill.installedAt ?? parentPlugin?.installedAt {
                        LabeledContent("Installed") {
                            Text(installed.formatted(date: .abbreviated, time: .omitted)).font(.metadata)
                        }
                    }
                }
```

Replace `sourceLabel` with:

```swift
    /// A link when we know where the skill came from; honest plain text otherwise.
    @ViewBuilder
    private var sourceView: some View {
        switch skill.source {
        case .personal, .shared:
            if let url = skill.sourceURL {
                SourceLink(label: skill.sourceLabel ?? url.absoluteString, url: url)
            } else if case .personal = skill.source {
                Text("Your skills folder (~/.claude/skills)")
            } else {
                Text("Shared skills folder (~/.agents/skills)")
            }
        case .plugin:
            if let plugin = parentPlugin, let url = plugin.homepageURL ?? plugin.marketplaceURL {
                SourceLink(label: "Plugin \(plugin.name)", url: url)
            } else if let plugin = parentPlugin {
                Text("Plugin \(plugin.name)")
            } else {
                Text("Plugin")
            }
        }
    }
```

"Last modified" leaves the card: it now lives in the header as Updated.

- [ ] **Step 3: Build and eyeball**

Run: `xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -derivedDataPath build build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

Launch with `open "build/Build/Products/Debug/Skills Manager.app"`. Under **Your Skills** select `make-interfaces-feel-better`: header shows Updated (from the lock file, Jun 22, 2026); Source is a link labelled `jakubkrehel/make-interfaces-feel-better`; Installed shows May 16, 2026. Select a plugin skill such as `superpowers › brainstorming`: Source is a link labelled "Plugin superpowers". Select a skill with no lock record (any folder in `~/.claude/skills` that is not a symlink, if one exists; otherwise use the sandbox from Task 4): Source is the plain folder sentence and there is no Installed row. Quit.

- [ ] **Step 4: Commit**

```bash
git add App/SkillDetailView.swift App/LibraryView.swift
git commit -m "feat: skill detail shows updated date in header and a clickable source

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Full verification and owner checkpoint

**Files:** none modified unless a fix is needed.

- [ ] **Step 1: Core tests**

Run: `cd SkillsManagerCore && swift test 2>&1 | tail -3`
Expected: `Test run with 40 tests in 0 suites passed`.

- [ ] **Step 2: Clean app build**

Run: `rm -rf build && xcodegen generate && xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -derivedDataPath build build 2>&1 | grep -E "warning:|error:|BUILD"`
Expected: `** BUILD SUCCEEDED **` and no new warnings in `App/`.

- [ ] **Step 3: Owner-verified checkpoint**

Launch `open "build/Build/Products/Debug/Skills Manager.app"` and pause for the owner to confirm, in their own words:

1. Sidebar rows no longer show any "Updated" text; chevrons and expansion behave as before.
2. No refresh button in the toolbar; ⌘R still works.
3. Figma plugin: Updated in the header; Author, Source (link), Marketplace (link), Version, Installed at the bottom; links open the browser.
4. A shared skill: Updated in the header; Source is a GitHub link; Installed date present.
5. Nothing jumps or shifts when switching between items with and without links.

This is an owner-verified checkpoint. A non-interactive executor must stop here and report rather than assume success.

- [ ] **Step 4: Finish the branch**

Invoke `superpowers:finishing-a-development-branch`. Expected outcome: PR against `main` titled "Detail provenance links and sidebar/toolbar cleanup", body ending with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
