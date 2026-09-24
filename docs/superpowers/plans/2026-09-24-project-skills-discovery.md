# Project Skills Discovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show every skill and plugin Claude can use on this Mac — global, per project (terminal, desktop Code tab, Cowork), Cowork's own plugins, and the user's Claude-account skills — each tagged with where it works, plus user-added markdown note folders.

**Architecture:** New single-purpose readers in `SkillsManagerCore` (project sources, project scanner, Cowork plugins, Claude-account skills, note folders, markdown blocks) feed `Inventory.load`, which then runs a pure merge step (`Library.build`) that turns raw skills/plugins into rows carrying location tags. The SwiftUI app reads only `Library` rows for the sidebar and detail pages, persists user-added folders in `UserDefaults`, and gains a second slow-debounced file watcher for Claude's busy session files.

**Tech Stack:** Swift 6 / SwiftUI, macOS 14+, Swift Testing (`@Test`, `#expect`), XcodeGen, Yams (existing). Spec: `docs/superpowers/specs/2026-09-24-project-skills-discovery-design.md`.

## Global Constraints

- Read-only: the app never writes to any file it reads. The only thing it persists is the added-folder list, in its own `UserDefaults`.
- Every reader is isolated: a missing file is normal (empty result, no issue); an unreadable/undecodable file yields exactly one plain-English `ParseIssue` for that source and never stops other sources from loading (spec §6.2).
- From desktop-app session files decode **only** `cwd`, `originCwd`, `userSelectedFolders` via `Decodable` structs that declare nothing else. Never use `JSONSerialization` on session files (spec §4.1 privacy).
- All paths compared/stored as canonical paths via `Canonical.path(_:)` (realpath(3)). Never `resolvingSymlinksInPath()` for comparisons (it strips `/private`).
- New `Skill` / `Plugin` fields are defaulted initializer parameters so existing call sites and tests keep compiling.
- Copy is plain English for someone who has never opened a terminal. Tag labels exactly: `Global`, `Claude account`, `Cowork`, the project display name, `Not a skill`, `+N`.
- Spacing uses only the `Spacing` scale in `App/DesignSystem.swift`.
- **UI tasks (9, 10, 11) MUST invoke the design skills** `apple-design`, `make-interfaces-feel-better`, `emil-design-eng`, `better-ui`, `better-layout`, `better-typography`, `better-accessibility`, and `better-writing` before editing views.
- Core tests: `cd SkillsManagerCore && swift test`. App build: from repo root, `xcodegen generate && xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -derivedDataPath build build`.
- After any app change that the owner will look at: run `scripts/install-local.sh` (one copy in /Applications).
- Commit after every task; last line of every commit message: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Deliberate refinements of the spec (flag to owner at handoff)

1. **Claude-account skills are their own rows, not merged with same-named personal/project skills.** They run as `/anthropic-skills:<name>` (namespaced, like plugin skills), so they're a different command — spec §4.5's "plugin skills never merge" rule applies to them too.
2. **"Add folder…" only treats a folder as a project if it has a `.claude` folder with `skills/` or `settings.json`.** A bare folder of `SKILL.md` folders isn't loaded by Claude Code, so tagging it with a project name would be a false claim; such a folder is classified by its top-level `.md` files instead.
3. **Hover on `+N` shows the native macOS tooltip; click opens the popover.** A hover-triggered popover inside a `List` row flickers (the popover steals the hover). Tooltip + click is the native, accessible equivalent of the approved behavior.
4. **Tags sit on their own line under the row's summary** rather than right-aligned, because the sidebar is 260–300 pt wide and a name + two project tags + `+N` doesn't fit on one line. Owner checkpoint confirms.

---

## File map

| File | Change |
|---|---|
| `SkillsManagerCore/Sources/SkillsManagerCore/Canonical.swift` | **new** — realpath helper |
| `SkillsManagerCore/Sources/SkillsManagerCore/ClaudePaths.swift` | add `claudeJSON`, `desktopSupportDir`, `codeSessionsDir`, `coworkSessionsDir`, `accountSkillsDir`, `userPluginStore` |
| `SkillsManagerCore/Sources/SkillsManagerCore/Models.swift` | `SkillSource.project`, `.account`; `Skill.isEnabled` |
| `SkillsManagerCore/Sources/SkillsManagerCore/PluginModels.swift` | `PluginScope`, `Plugin.scope`, `PluginStore` |
| `SkillsManagerCore/Sources/SkillsManagerCore/PluginRegistry.swift` | `loadPlugins(store:enabledPlugins:scope:only:)` |
| `SkillsManagerCore/Sources/SkillsManagerCore/SkillScanner.swift` | extract `scanOne`; `skipOnlineOnly` |
| `SkillsManagerCore/Sources/SkillsManagerCore/LocalFile.swift` | **new** — online-only check |
| `SkillsManagerCore/Sources/SkillsManagerCore/Invocation.swift` | new source cases |
| `SkillsManagerCore/Sources/SkillsManagerCore/ProjectSources.swift` | **new** |
| `SkillsManagerCore/Sources/SkillsManagerCore/ProjectScanner.swift` | **new** |
| `SkillsManagerCore/Sources/SkillsManagerCore/CoworkPlugins.swift` | **new** |
| `SkillsManagerCore/Sources/SkillsManagerCore/AccountSkills.swift` | **new** |
| `SkillsManagerCore/Sources/SkillsManagerCore/NoteFolders.swift` | **new** |
| `SkillsManagerCore/Sources/SkillsManagerCore/MarkdownBlocks.swift` | **new** |
| `SkillsManagerCore/Sources/SkillsManagerCore/Library.swift` | **new** — merge, tags, overflow |
| `SkillsManagerCore/Sources/SkillsManagerCore/WhereItWorks.swift` | **new** — detail-page lines |
| `SkillsManagerCore/Sources/SkillsManagerCore/Inventory.swift` | compose everything |
| `SkillsManagerCore/Sources/SkillsManagerCore/Version.swift` | `0.4.0` |
| `SkillsManagerCore/Tests/SkillsManagerCoreTests/TempTree.swift` | **new** — test helper |
| `SkillsManagerCore/Tests/SkillsManagerCoreTests/*Tests.swift` | new test files per reader |
| `App/FileWatcher.swift` | `delay:` param, `setTargets(_:)` |
| `App/InventoryStore.swift` | added folders, access flag, two watchers |
| `App/LibraryView.swift` | new sidebar sections, selection cases, Add Folder |
| `App/LibraryRows.swift` | `SkillEntryRow`, `PluginRow(entry:)`, `NoteRow` |
| `App/LocationTags.swift` | **new** — tag pills + `+N` |
| `App/WhereItWorksSection.swift` | **new** |
| `App/NoteDetailView.swift` | **new** |
| `App/ProjectAccessSheet.swift` | **new** — first-run note |
| `App/SkillDetailView.swift`, `App/PluginDetailView.swift` | where-it-works section, new source cases |
| `App/SkillsManagerApp.swift` | File ▸ Add Folder… |

---

### Task 1: Foundations — paths, models, plugin store, single-skill scan

**Files:**
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/Canonical.swift`
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/LocalFile.swift`
- Create: `SkillsManagerCore/Tests/SkillsManagerCoreTests/TempTree.swift`
- Create: `SkillsManagerCore/Tests/SkillsManagerCoreTests/FoundationsTests.swift`
- Modify: `ClaudePaths.swift`, `Models.swift`, `PluginModels.swift`, `PluginRegistry.swift`, `SkillScanner.swift`, `Invocation.swift`
- Modify (compile only): `App/SkillDetailView.swift` (exhaustive switches)

**Interfaces:**
- Produces:
  - `Canonical.path(_ path: String) -> String`, `Canonical.url(_ url: URL) -> URL`
  - `LocalFile.isDownloaded(_ url: URL) -> Bool`
  - `ClaudePaths.claudeJSON / desktopSupportDir / codeSessionsDir / coworkSessionsDir / accountSkillsDir: URL`, `ClaudePaths.userPluginStore: PluginStore`
  - `SkillSource.project(root: URL, subpath: String?)`, `SkillSource.account(userMade: Bool)`
  - `Skill.isEnabled: Bool` (init param `isEnabled: Bool = true`)
  - `PluginScope { user, project(root: URL), cowork }`, `Plugin.scope` (init param `scope: PluginScope = .user`)
  - `PluginStore(root: URL)` with `installedPluginsFile`, `knownMarketplacesFile`, `cacheDir`
  - `PluginRegistry.loadPlugins(store:enabledPlugins:scope:only:) -> PluginLoadResult`
  - `SkillScanner.scanOne(folder:source:isEnabled:skipOnlineOnly:) -> SkillScanner.One` where `enum One { case skill(Skill), issue(ParseIssue), notASkill }`
  - `SkillScanner.scan(directory:source:lock:lockScope:skipOnlineOnly:)` (new param defaults `false`)

- [ ] **Step 1: Write the test helper**

`SkillsManagerCore/Tests/SkillsManagerCoreTests/TempTree.swift`:

```swift
import Foundation
@testable import SkillsManagerCore

/// Builds throwaway directory trees for reader tests. Root is canonical
/// (realpath) so it compares equal to what the readers produce.
struct TempTree {
    let root: URL

    init() throws {
        let raw = FileManager.default.temporaryDirectory.appending(path: "temptree-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        root = Canonical.url(raw)
    }

    func url(_ path: String) -> URL { root.appending(path: path) }

    @discardableResult
    func mkdir(_ path: String) throws -> URL {
        let u = url(path)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    @discardableResult
    func write(_ text: String, to path: String) throws -> URL {
        let u = url(path)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: u, atomically: true, encoding: .utf8)
        return u
    }

    /// Writes `<dir>/<name>/SKILL.md` with valid frontmatter.
    @discardableResult
    func skill(_ name: String, in dir: String, body: String = "Body") throws -> URL {
        try write("---\nname: \(name)\ndescription: Test skill \(name)\n---\n\(body)\n",
                  to: "\(dir)/\(name)/SKILL.md")
        return url("\(dir)/\(name)")
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
```

- [ ] **Step 2: Write the failing tests**

`SkillsManagerCore/Tests/SkillsManagerCoreTests/FoundationsTests.swift`:

```swift
import Foundation
import Testing
@testable import SkillsManagerCore

@Test func canonicalResolvesPrivatePrefix() {
    // /tmp is a symlink to /private/tmp on macOS.
    #expect(Canonical.path("/tmp") == "/private/tmp")
    // Nonexistent tail canonicalizes its existing ancestor.
    #expect(Canonical.path("/tmp/does-not-exist-xyz") == "/private/tmp/does-not-exist-xyz")
}

@Test func newPathsHangOffHome() {
    let paths = ClaudePaths(home: URL(fileURLWithPath: "/Users/test", isDirectory: true))
    #expect(paths.claudeJSON.path == "/Users/test/.claude.json")
    #expect(paths.codeSessionsDir.path == "/Users/test/Library/Application Support/Claude/claude-code-sessions")
    #expect(paths.coworkSessionsDir.path == "/Users/test/Library/Application Support/Claude/local-agent-mode-sessions")
    #expect(paths.accountSkillsDir.path == "/Users/test/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin")
    #expect(paths.userPluginStore.installedPluginsFile == paths.installedPluginsFile)
    #expect(paths.userPluginStore.cacheDir == paths.pluginsCacheDir)
}

@Test func scanOneReturnsSkillIssueOrNotASkill() throws {
    let t = try TempTree(); defer { t.remove() }
    let good = try t.skill("alpha", in: "skills")
    try t.write("no frontmatter", to: "skills/broken/SKILL.md")
    try t.mkdir("skills/empty")

    guard case .skill(let s) = SkillScanner.scanOne(folder: good, source: .account(userMade: true), isEnabled: false)
    else { Issue.record("expected skill"); return }
    #expect(s.folderName == "alpha")
    #expect(s.isEnabled == false)
    #expect(s.source == .account(userMade: true))

    guard case .issue = SkillScanner.scanOne(folder: t.url("skills/broken"), source: .personal) else {
        Issue.record("expected issue"); return
    }
    // A folder without SKILL.md is reported by scan() as an issue; scanOne says notASkill
    // so callers decide.
    guard case .notASkill = SkillScanner.scanOne(folder: t.url("skills/empty"), source: .personal) else {
        Issue.record("expected notASkill"); return
    }
}

@Test func loadPluginsFromStoreWithScopeAndOnlyFilter() throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let paths = ClaudePaths(home: home)
    let root = URL(fileURLWithPath: "/proj", isDirectory: true)

    let result = PluginRegistry.loadPlugins(
        store: paths.userPluginStore,
        enabledPlugins: ["demo-plugin@test-market": true, "ghost@nowhere": true],
        scope: .project(root: root),
        only: ["demo-plugin@test-market", "ghost@nowhere"])

    #expect(result.plugins.map(\.pluginID) == ["demo-plugin@test-market"])
    #expect(result.plugins[0].scope == .project(root: root))
    // Turned on for the project but not installed: reported, never silently dropped.
    #expect(result.issues.contains { $0.detail.contains("ghost@nowhere") })
}

@Test func invocationForNewSources() {
    func make(_ source: SkillSource) -> Skill {
        Skill(folderName: "thing", displayName: "thing", summary: nil, argumentHint: nil,
              userInvocable: true, modelInvocable: true, whenToUse: nil,
              source: source, directory: URL(fileURLWithPath: "/tmp/thing"), lastModified: nil)
    }
    #expect(Invocation.string(for: make(.project(root: URL(fileURLWithPath: "/p"), subpath: nil))) == "/thing")
    #expect(Invocation.string(for: make(.account(userMade: true))) == "/anthropic-skills:thing")
}

@Test func disabledAccountSkillSaysWhereToTurnItOn() {
    let s = Skill(folderName: "x", displayName: "x", summary: nil, argumentHint: nil,
                  userInvocable: true, modelInvocable: true, whenToUse: nil,
                  source: .account(userMade: true), directory: URL(fileURLWithPath: "/tmp/x"),
                  lastModified: nil, isEnabled: false)
    #expect(Invocation.availabilityLabel(for: s).contains("Claude → Settings → Skills"))
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd SkillsManagerCore && swift test 2>&1 | tail -20`
Expected: compile errors — `Canonical`, `claudeJSON`, `scanOne`, `.account`, `PluginStore` not defined.

- [ ] **Step 4: Implement**

`Canonical.swift`:

```swift
import Foundation

/// Canonical filesystem paths via realpath(3). Foundation's
/// resolvingSymlinksInPath() strips /private and is NOT canonical — never use
/// it for comparisons.
public enum Canonical {
    public static func path(_ path: String) -> String {
        if let rp = realpath(path, nil) {
            defer { free(rp) }
            return String(cString: rp)
        }
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent().path
        guard parent != path, !parent.isEmpty else { return path }
        return (self.path(parent) as NSString).appendingPathComponent(url.lastPathComponent)
    }

    public static func url(_ url: URL) -> URL {
        URL(fileURLWithPath: path(url.path), isDirectory: url.hasDirectoryPath)
    }
}
```

`LocalFile.swift`:

```swift
import Foundation

public enum LocalFile {
    /// False for a cloud-synced file (iCloud Drive, Dropbox, OneDrive…) whose
    /// contents live only online. Reading such a file would trigger a
    /// download, which the app must never do (spec §4.3). Non-cloud files → true.
    public static func isDownloaded(_ url: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isUbiquitousItem == true,
              let status = values.ubiquitousItemDownloadingStatus else { return true }
        return status == .current || status == .downloaded
    }
}
```

`ClaudePaths.swift` — add below `agentsLockFile`:

```swift
    /// Terminal Claude Code's settings, including the `projects` map of every
    /// folder it has been opened in.
    public var claudeJSON: URL { home.appending(path: ".claude.json") }
    public var desktopSupportDir: URL {
        home.appending(path: "Library/Application Support/Claude", directoryHint: .isDirectory)
    }
    /// Claude desktop app, Code tab: one JSON file per session (`cwd`, `originCwd`).
    public var codeSessionsDir: URL { desktopSupportDir.appending(path: "claude-code-sessions", directoryHint: .isDirectory) }
    /// Claude desktop app, Cowork: session files (`userSelectedFolders`) and Cowork's own plugins.
    public var coworkSessionsDir: URL { desktopSupportDir.appending(path: "local-agent-mode-sessions", directoryHint: .isDirectory) }
    /// Local copy of the skills in the user's Claude account.
    public var accountSkillsDir: URL { coworkSessionsDir.appending(path: "skills-plugin", directoryHint: .isDirectory) }
    public var userPluginStore: PluginStore { PluginStore(root: pluginsDir) }
```

`Models.swift` — replace the `SkillSource` enum and extend `Skill`:

```swift
/// Where a skill lives.
public enum SkillSource: Sendable, Hashable {
    case personal                       // ~/.claude/skills
    case shared                         // ~/.agents/skills
    case plugin(pluginID: String)       // e.g. "superpowers@claude-plugins-official"
    /// <root>/.claude/skills, or <root>/<subpath>/.claude/skills for nested ones.
    case project(root: URL, subpath: String?)
    /// Synced from the user's Claude account. userMade false = built in by Anthropic.
    case account(userMade: Bool)
}
```

In `Skill`, add the stored property after `updatedAt`:

```swift
    /// False only for Claude-account skills turned off in Claude's settings.
    public let isEnabled: Bool
```

and the init parameter `isEnabled: Bool = true` after `updatedAt: Date? = nil`, assigning `self.isEnabled = isEnabled`.

`PluginModels.swift` — add at the bottom:

```swift
public enum PluginScope: Sendable, Hashable {
    case user                   // ~/.claude/settings.json
    case project(root: URL)     // <root>/.claude/settings(.local).json
    case cowork                 // Cowork's own plugin set
}

/// A plugin installation area with Claude Code's layout: installed_plugins.json,
/// known_marketplaces.json, cache/<market>/<name>/<version>/. Claude Code's is
/// ~/.claude/plugins; Cowork keeps an identical one per account.
public struct PluginStore: Sendable, Hashable {
    public let root: URL
    public init(root: URL) { self.root = root }
    public var installedPluginsFile: URL { root.appending(path: "installed_plugins.json") }
    public var knownMarketplacesFile: URL { root.appending(path: "known_marketplaces.json") }
    public var cacheDir: URL { root.appending(path: "cache", directoryHint: .isDirectory) }
}
```

In `Plugin`, add `public let scope: PluginScope` after `installedAt`, init param `scope: PluginScope = .user` last, assign it.

`PluginRegistry.swift` — replace `loadPlugins(paths:enabledPlugins:)` and `contentDirectory(for:paths:)`:

```swift
    public static func loadPlugins(paths: ClaudePaths, enabledPlugins: [String: Bool]) -> PluginLoadResult {
        loadPlugins(store: paths.userPluginStore, enabledPlugins: enabledPlugins, scope: .user, only: nil)
    }

    /// `only`: when set, load just these plugin IDs (project scope) and report
    /// any that aren't installed.
    public static func loadPlugins(store: PluginStore, enabledPlugins: [String: Bool],
                                   scope: PluginScope, only: Set<String>?) -> PluginLoadResult {
        let fm = FileManager.default
        var result = PluginLoadResult()
        var records: [InstalledPluginRecord]
        do {
            records = try loadRecords(installedPluginsFile: store.installedPluginsFile)
        } catch {
            if fm.fileExists(atPath: store.installedPluginsFile.path) {
                result.issues.append(ParseIssue(
                    location: store.installedPluginsFile,
                    detail: "Plugin registry can't be read: \(error.localizedDescription)"))
            }
            records = []
        }
        if let only {
            records = records.filter { only.contains($0.pluginID) }
            let found = Set(records.map(\.pluginID))
            for missing in only.subtracting(found).sorted() {
                result.issues.append(ParseIssue(
                    location: store.installedPluginsFile,
                    detail: "\(missing) is turned on for a project but isn't installed"))
            }
        }

        let marketplaces = marketplaceInfo(knownMarketplacesFile: store.knownMarketplacesFile)

        for record in records.sorted(by: { $0.pluginID < $1.pluginID }) {
            guard let contentDir = contentDirectory(for: record, store: store) else {
                result.issues.append(ParseIssue(
                    location: store.cacheDir,
                    detail: "\(record.pluginID) is registered but its files are missing"))
                continue
            }
            let scan = SkillScanner.scan(
                directory: contentDir.appending(path: "skills", directoryHint: .isDirectory),
                source: .plugin(pluginID: record.pluginID))
            result.issues.append(contentsOf: scan.issues)
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
                installedAt: record.installedAt,
                scope: scope))
        }
        return result
    }
```

```swift
    private static func contentDirectory(for record: InstalledPluginRecord, store: PluginStore) -> URL? {
        let fm = FileManager.default
        if let version = record.version {
            let cacheDir = store.cacheDir
                .appending(path: record.marketplace, directoryHint: .isDirectory)
                .appending(path: record.name, directoryHint: .isDirectory)
                .appending(path: version, directoryHint: .isDirectory)
            if fm.fileExists(atPath: cacheDir.path) { return cacheDir }
        }
        if let installPath = record.installPath, fm.fileExists(atPath: installPath) {
            return URL(fileURLWithPath: installPath, isDirectory: true)
        }
        return nil
    }
```

`SkillScanner.swift` — replace the whole `SkillScanner` enum:

```swift
public enum SkillScanner {
    public enum One {
        case skill(Skill)
        case issue(ParseIssue)
        case notASkill          // folder has no SKILL.md
    }

    /// Scans a directory whose children are skill folders (each holding SKILL.md).
    /// A missing directory is normal (not every machine has every source) — empty result.
    public static func scan(directory: URL, source: SkillSource, lock: SkillLock = .empty,
                            lockScope: URL? = nil, skipOnlineOnly: Bool = false) -> ScanResult {
        let fm = FileManager.default
        var result = ScanResult()
        guard let entries = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return result }

        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            // fileExists(atPath:isDirectory:) follows symlinks — symlinked skill
            // folders (how installers connect agents) must scan like real ones.
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: entry.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            switch scanOne(folder: entry, source: source, lock: lock, lockScope: lockScope,
                           skipOnlineOnly: skipOnlineOnly) {
            case .skill(let skill): result.skills.append(skill)
            case .issue(let issue): result.issues.append(issue)
            case .notASkill:
                result.issues.append(ParseIssue(location: entry, detail: "No SKILL.md inside this folder"))
            }
        }
        return result
    }

    /// Reads one skill folder.
    public static func scanOne(folder entry: URL, source: SkillSource, isEnabled: Bool = true,
                               lock: SkillLock = .empty, lockScope: URL? = nil,
                               skipOnlineOnly: Bool = false) -> One {
        let fm = FileManager.default
        let skillFile = entry.appending(path: "SKILL.md")
        guard fm.fileExists(atPath: skillFile.path) else { return .notASkill }
        if skipOnlineOnly && !LocalFile.isDownloaded(skillFile) {
            return .issue(ParseIssue(location: skillFile,
                                     detail: "Stored online only — download it in Finder to see it here"))
        }
        guard let text = try? String(contentsOf: skillFile, encoding: .utf8) else {
            return .issue(ParseIssue(location: skillFile, detail: "File can't be read as text"))
        }
        switch FrontmatterParser.parse(text) {
        case .malformed(let reason):
            return .issue(ParseIssue(location: skillFile, detail: reason))
        case .missing:
            return .issue(ParseIssue(location: skillFile, detail: "Missing the --- name/description --- header"))
        case .parsed(let fm2, _):
            let modified = (try? skillFile.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            let resolved = URL(fileURLWithPath: entry.path).resolvingSymlinksInPath().path
            let scopeOK = lockScope.map { resolved.hasPrefix($0.resolvingSymlinksInPath().path + "/") } ?? true
            let lockEntry = scopeOK ? lock[entry.lastPathComponent] : nil
            return .skill(Skill(
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
                updatedAt: lockEntry?.updatedAt,
                isEnabled: isEnabled))
        }
    }
}
```

(The lock/lockScope comparison deliberately keeps the existing `resolvingSymlinksInPath()` logic unchanged — it compares two paths resolved the same way, and changing it is out of scope.)

`Invocation.swift` — replace `string(for:)` switch and the start of `availabilityLabel`:

```swift
    public static func string(for skill: Skill) -> String {
        switch skill.source {
        case .personal, .shared, .project:
            return "/\(skill.folderName)"
        case .plugin(let pluginID):
            let pluginName = pluginID.split(separator: "@", maxSplits: 1).first.map(String.init) ?? pluginID
            return "/\(pluginName):\(skill.folderName)"
        case .account:
            // Claude-account skills load in Claude Code (desktop) as the
            // built-in anthropic-skills plugin.
            return "/anthropic-skills:\(skill.folderName)"
        }
    }
```

At the top of `availabilityLabel(for:)`, before the `.shared` check:

```swift
        if case .account = skill.source, !skill.isEnabled {
            return "Turned off in your Claude account. Turn it back on in Claude → Settings → Skills."
        }
```

`App/SkillDetailView.swift` — make the two switches exhaustive (final design comes in Task 10):

```swift
                switch skill.source {
                case .personal: KindBadge(text: "Skill", tint: .gray)
                case .shared: KindBadge(text: "Shared", tint: .teal)
                case .plugin: KindBadge(text: "Plugin Skill", tint: .purple)
                case .project: KindBadge(text: "Project Skill", tint: .teal)
                case .account: KindBadge(text: "Claude Account", tint: .blue)
                }
```

and in `sourceView` add before `case .plugin:`:

```swift
        case .project(let root, _):
            Text("Project folder (\(root.lastPathComponent))")
        case .account:
            Text("Your Claude account")
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd SkillsManagerCore && swift test 2>&1 | tail -5`
Expected: all tests pass (76 existing + 6 new).

- [ ] **Step 6: Build the app**

Run: `xcodegen generate && xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -derivedDataPath build build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add -A SkillsManagerCore App/SkillDetailView.swift
git commit -m "core: project/account skill sources, plugin stores, single-skill scan

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Project sources — where Claude has been given folder access

**Files:**
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/ProjectSources.swift`
- Test: `SkillsManagerCore/Tests/SkillsManagerCoreTests/ProjectSourcesTests.swift`

**Interfaces:**
- Consumes: `Canonical.path`, `ClaudePaths.claudeJSON/codeSessionsDir/coworkSessionsDir`, `ParseIssue`
- Produces:
  - `struct Project: Sendable, Hashable, Identifiable { let root: URL; let displayName: String; var id: String }`
  - `struct ProjectDiscovery: Sendable { var projects: [Project]; var issues: [ParseIssue] }`
  - `ProjectSources.terminalFolders(claudeJSON: URL) throws -> [String]`
  - `ProjectSources.codeTabFolders(sessionsDir: URL) throws -> [String]`
  - `ProjectSources.coworkFolders(sessionsDir: URL) throws -> [String]`
  - `ProjectSources.sessionFiles(in: URL) -> [URL]` (`<dir>/<a>/<b>/local_*.json`)
  - `ProjectSources.normalize(_ raw: [String], home: URL) -> [Project]`
  - `ProjectSources.discover(paths: ClaudePaths, addedProjects: [URL]) -> ProjectDiscovery`

- [ ] **Step 1: Write the failing tests**

`ProjectSourcesTests.swift`:

```swift
import Foundation
import Testing
@testable import SkillsManagerCore

@Test func terminalFoldersAreProjectKeys() throws {
    let t = try TempTree(); defer { t.remove() }
    let file = try t.write(#"{"numStartups": 3, "projects": {"/a": {"allowedTools": []}, "/b": {}}}"#, to: ".claude.json")
    #expect(try ProjectSources.terminalFolders(claudeJSON: file).sorted() == ["/a", "/b"])
    // Missing file is normal.
    #expect(try ProjectSources.terminalFolders(claudeJSON: t.url("nope.json")) == [])
    // Broken file throws so discover() can report it.
    let bad = try t.write("{not json", to: "bad.json")
    #expect(throws: (any Error).self) { try ProjectSources.terminalFolders(claudeJSON: bad) }
}

@Test func codeTabFoldersReadOnlyPathFields() throws {
    let t = try TempTree(); defer { t.remove() }
    // Private fields present with odd types — must not break decoding or be read.
    try t.write(#"{"cwd": "/w1", "originCwd": "/o1", "title": {"x": 1}, "promptAppendSnapshot": [1,2]}"#,
                to: "sessions/acct/org/local_1.json")
    try t.write(#"{"cwd": "/w2"}"#, to: "sessions/acct/org/local_2.json")
    try t.write(#"{"cwd": "/ignored"}"#, to: "sessions/acct/org/other.json")          // wrong name
    try t.write(#"{"cwd": "/too-deep"}"#, to: "sessions/acct/org/sub/local_3.json")   // wrong depth
    let folders = try ProjectSources.codeTabFolders(sessionsDir: t.url("sessions"))
    #expect(Set(folders) == ["/w1", "/o1", "/w2"])
}

@Test func coworkFoldersReadUserSelectedFoldersAndSkipAccountSkills() throws {
    let t = try TempTree(); defer { t.remove() }
    try t.write(#"{"userSelectedFolders": ["/c1", "/c2"], "emailAddress": "a@b.c", "systemPrompt": "secret"}"#,
                to: "cowork/acct/org/local_9.json")
    try t.write(#"{"userSelectedFolders": ["/nope"]}"#, to: "cowork/skills-plugin/acct/local_1.json")
    let folders = try ProjectSources.coworkFolders(sessionsDir: t.url("cowork"))
    #expect(folders == ["/c1", "/c2"])
}

@Test func sessionReadersThrowOnlyWhenEveryFileIsUnreadable() throws {
    let t = try TempTree(); defer { t.remove() }
    try t.write("garbage", to: "s/a/b/local_1.json")
    #expect(throws: (any Error).self) { try ProjectSources.codeTabFolders(sessionsDir: t.url("s")) }
    try t.write(#"{"cwd": "/ok"}"#, to: "s/a/b/local_2.json")
    #expect(try ProjectSources.codeTabFolders(sessionsDir: t.url("s")) == ["/ok"])
    #expect(try ProjectSources.codeTabFolders(sessionsDir: t.url("missing")) == [])
}

@Test func normalizeDropsMissingFoldsWorktreesSkipsHomeAndDedupes() throws {
    let t = try TempTree(); defer { t.remove() }
    let home = try t.mkdir("home")
    let portfolio = try t.mkdir("home/Claude/Portfolio")
    try t.mkdir("home/Claude/Portfolio/.claude/worktrees/feature-x")
    try t.mkdir("home/Work/Portfolio")
    try t.mkdir("home/Ring")

    let projects = ProjectSources.normalize([
        portfolio.path,
        portfolio.path + "/.claude/worktrees/feature-x",   // folds into Portfolio
        t.url("home/Claude/Deleted").path,                 // missing → dropped
        home.path,                                         // home → dropped
        t.url("home/Work/Portfolio").path,                 // same name, different parent
        t.url("home/Ring").path,
        t.url("home/Ring").path,                           // duplicate
    ], home: home)

    #expect(projects.map(\.displayName) == ["Portfolio (Claude)", "Portfolio (Work)", "Ring"])
    #expect(projects[0].root.path == Canonical.path(portfolio.path))
}

@Test func discoverReportsABrokenSourceAndKeepsTheOthers() throws {
    let t = try TempTree(); defer { t.remove() }
    let home = try t.mkdir("home")
    let paths = ClaudePaths(home: home)
    try t.write("{broken", to: "home/.claude.json")
    let cowork = try t.mkdir("home/Cowork Folder")
    try t.write(#"{"userSelectedFolders": ["\#(cowork.path)"]}"#,
                to: "home/Library/Application Support/Claude/local-agent-mode-sessions/a/b/local_1.json")
    let added = try t.mkdir("home/Added")

    let d = ProjectSources.discover(paths: paths, addedProjects: [added])
    #expect(d.projects.map(\.displayName) == ["Added", "Cowork Folder"])
    #expect(d.issues.count == 1)
    #expect(d.issues[0].detail == "Couldn't read Claude Code's project list. Some projects may be missing.")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SkillsManagerCore && swift test --filter ProjectSources 2>&1 | tail -5`
Expected: compile error — `ProjectSources` not defined.

- [ ] **Step 3: Implement**

`ProjectSources.swift`:

```swift
import Foundation

public struct Project: Sendable, Hashable, Identifiable {
    public var id: String { root.path }
    public let root: URL            // canonical
    public let displayName: String  // folder name, disambiguated by parent when needed

    public init(root: URL, displayName: String) {
        self.root = root
        self.displayName = displayName
    }
}

public struct ProjectDiscovery: Sendable {
    public var projects: [Project]
    public var issues: [ParseIssue]
}

struct SourceFormatError: Error {}

/// Finds every folder Claude has been given access to (spec §4.1–4.2).
/// All three sources are internal Claude files: read leniently, decode only
/// the path fields.
public enum ProjectSources {
    public static func terminalFolders(claudeJSON: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: claudeJSON.path) else { return [] }
        let data = try Data(contentsOf: claudeJSON)
        // Top-level keys only; project values are never inspected.
        struct File: Decodable {
            let projects: [String: IgnoredValue]?
        }
        let file = try JSONDecoder().decode(File.self, from: data)
        return file.projects.map { Array($0.keys) } ?? []
    }

    public static func codeTabFolders(sessionsDir: URL) throws -> [String] {
        struct Session: Decodable { let cwd: String?; let originCwd: String? }
        return try decodeAll(sessionFiles(in: sessionsDir), as: Session.self) { [$0.cwd, $0.originCwd].compactMap { $0 } }
    }

    public static func coworkFolders(sessionsDir: URL) throws -> [String] {
        struct Session: Decodable { let userSelectedFolders: [String]? }
        let files = sessionFiles(in: sessionsDir, skipping: ["skills-plugin"])
        return try decodeAll(files, as: Session.self) { $0.userSelectedFolders ?? [] }
    }

    /// `<dir>/<account>/<org>/local_*.json` — exactly that depth, nothing deeper.
    public static func sessionFiles(in dir: URL, skipping: Set<String> = []) -> [URL] {
        let fm = FileManager.default
        func children(_ u: URL) -> [URL] {
            (try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        }
        var files: [URL] = []
        for a in children(dir) where !skipping.contains(a.lastPathComponent) {
            for b in children(a) {
                files += children(b).filter {
                    $0.lastPathComponent.hasPrefix("local_") && $0.pathExtension == "json"
                }
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    /// One bad session file is skipped; if every file fails, the source is broken.
    private static func decodeAll<T: Decodable>(_ files: [URL], as type: T.Type,
                                                 paths: (T) -> [String]) throws -> [String] {
        var result: [String] = []
        var failures = 0
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let session = try? JSONDecoder().decode(type, from: data) else {
                failures += 1
                continue
            }
            result += paths(session)
        }
        if !files.isEmpty && failures == files.count { throw SourceFormatError() }
        return result
    }

    public static func normalize(_ raw: [String], home: URL) -> [Project] {
        let fm = FileManager.default
        let homePath = Canonical.path(home.path)
        var seen = Set<String>()
        var roots: [URL] = []
        for path in raw {
            var p = path
            if let r = p.range(of: "/.claude/worktrees/") { p = String(p[..<r.lowerBound]) }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue else { continue }
            let canon = Canonical.path(p)
            guard canon != homePath, canon != "/", seen.insert(canon).inserted else { continue }
            roots.append(URL(fileURLWithPath: canon, isDirectory: true))
        }
        let nameCounts = Dictionary(grouping: roots, by: \.lastPathComponent).mapValues(\.count)
        return roots.map { root in
            let base = root.lastPathComponent
            let name = (nameCounts[base] ?? 0) > 1
                ? "\(base) (\(root.deletingLastPathComponent().lastPathComponent))"
                : base
            return Project(root: root, displayName: name)
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    public static func discover(paths: ClaudePaths, addedProjects: [URL]) -> ProjectDiscovery {
        var raw: [String] = []
        var issues: [ParseIssue] = []
        func collect(_ message: String, _ location: URL, _ read: () throws -> [String]) {
            do { raw += try read() } catch {
                issues.append(ParseIssue(location: location, detail: message))
            }
        }
        collect("Couldn't read Claude Code's project list. Some projects may be missing.", paths.claudeJSON) {
            try terminalFolders(claudeJSON: paths.claudeJSON)
        }
        collect("Couldn't read the Claude app's Code sessions. Some projects may be missing.", paths.codeSessionsDir) {
            try codeTabFolders(sessionsDir: paths.codeSessionsDir)
        }
        collect("Couldn't read Cowork's folder list. Cowork items may be missing.", paths.coworkSessionsDir) {
            try coworkFolders(sessionsDir: paths.coworkSessionsDir)
        }
        raw += addedProjects.map(\.path)
        return ProjectDiscovery(projects: normalize(raw, home: paths.home), issues: issues)
    }
}

/// Decodes any JSON value and throws it away — lets us read dictionary keys
/// without ever materializing the values.
struct IgnoredValue: Decodable {
    init(from decoder: Decoder) throws {}
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SkillsManagerCore && swift test 2>&1 | tail -5`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add SkillsManagerCore
git commit -m "core: discover project folders from terminal, Code tab, and Cowork

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Project scanner — skills (incl. nested) and project plugins

**Files:**
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/ProjectScanner.swift`
- Test: `SkillsManagerCore/Tests/SkillsManagerCoreTests/ProjectScannerTests.swift`

**Interfaces:**
- Consumes: `Project`, `SkillScanner.scan(...skipOnlineOnly:)`, `SettingsReader.enabledPlugins`, `PluginRegistry.loadPlugins(store:enabledPlugins:scope:only:)`, `ClaudePaths.userPluginStore`
- Produces:
  - `struct ProjectScanResult: Sendable { var skills: [Skill]; var plugins: [Plugin]; var issues: [ParseIssue] }`
  - `ProjectScanner.scan(_ project: Project, paths: ClaudePaths) -> ProjectScanResult`
  - `ProjectScanner.skillDirectories(in root: URL) throws -> [(dir: URL, subpath: String?)]`
  - `ProjectScanner.maxDepth = 4`, `ProjectScanner.skippedFolders`

- [ ] **Step 1: Write the failing tests**

`ProjectScannerTests.swift`:

```swift
import Foundation
import Testing
@testable import SkillsManagerCore

@Test func findsTopLevelAndNestedSkillFoldersWithinDepth() throws {
    let t = try TempTree(); defer { t.remove() }
    let root = try t.mkdir("proj")
    try t.skill("top", in: "proj/.claude/skills")
    try t.skill("web", in: "proj/apps/web/.claude/skills")
    try t.skill("deep", in: "proj/a/b/c/d/.claude/skills")         // depth 4: found
    try t.skill("toodeep", in: "proj/a/b/c/d/e/.claude/skills")    // depth 5: skipped
    try t.skill("dep", in: "proj/node_modules/pkg/.claude/skills") // skipped folder
    try t.skill("wt", in: "proj/.claude/worktrees/x/.claude/skills") // hidden → skipped

    let dirs = try ProjectScanner.skillDirectories(in: root)
    let subpaths = dirs.map { $0.subpath ?? "<root>" }.sorted()
    #expect(subpaths == ["<root>", "a/b/c/d", "apps/web"])
}

@Test func scanTagsSkillsWithProjectAndSubpath() throws {
    let t = try TempTree(); defer { t.remove() }
    let root = try t.mkdir("proj")
    try t.skill("top", in: "proj/.claude/skills")
    try t.skill("web", in: "proj/apps/web/.claude/skills")
    let project = Project(root: root, displayName: "proj")

    let r = ProjectScanner.scan(project, paths: ClaudePaths(home: t.url("home")))
    let top = try #require(r.skills.first { $0.folderName == "top" })
    #expect(top.source == .project(root: root, subpath: nil))
    let web = try #require(r.skills.first { $0.folderName == "web" })
    #expect(web.source == .project(root: root, subpath: "apps/web"))
    #expect(r.issues.isEmpty)
}

@Test func scanLoadsProjectAndLocalPlugins() throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let t = try TempTree(); defer { t.remove() }
    let root = try t.mkdir("proj")
    try t.write(#"{"enabledPlugins": {"demo-plugin@test-market": true, "off@x": false}}"#,
                to: "proj/.claude/settings.json")
    try t.write(#"{"enabledPlugins": {"disabled-plugin@test-market": true}}"#,
                to: "proj/.claude/settings.local.json")

    let r = ProjectScanner.scan(Project(root: root, displayName: "proj"), paths: ClaudePaths(home: home))
    #expect(r.plugins.map(\.pluginID).sorted() == ["demo-plugin@test-market", "disabled-plugin@test-market"])
    #expect(r.plugins.allSatisfy { $0.scope == .project(root: root) })
}

@Test func unreadableProjectBecomesOneIssue() throws {
    let t = try TempTree(); defer { t.remove() }
    let root = try t.mkdir("locked")
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }

    let r = ProjectScanner.scan(Project(root: root, displayName: "locked"), paths: ClaudePaths(home: t.url("h")))
    #expect(r.issues.count == 1)
    #expect(r.issues[0].detail.contains("System Settings"))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SkillsManagerCore && swift test --filter ProjectScanner 2>&1 | tail -5`
Expected: compile error — `ProjectScanner` not defined.

- [ ] **Step 3: Implement**

`ProjectScanner.swift`:

```swift
import Foundation

public struct ProjectScanResult: Sendable {
    public var skills: [Skill] = []
    public var plugins: [Plugin] = []
    public var issues: [ParseIssue] = []
}

/// Everything one project folder contributes (spec §4.3).
public enum ProjectScanner {
    public static let maxDepth = 4
    public static let skippedFolders: Set<String> = ["node_modules", ".git", ".build", "DerivedData", "Pods", "vendor"]

    public static func scan(_ project: Project, paths: ClaudePaths) -> ProjectScanResult {
        var result = ProjectScanResult()
        let dirs: [(dir: URL, subpath: String?)]
        do {
            dirs = try skillDirectories(in: project.root)
        } catch {
            result.issues.append(ParseIssue(
                location: project.root,
                detail: "Skills Manager can't open \(project.displayName). Allow it in System Settings → Privacy & Security → Files and Folders."))
            return result
        }
        for (dir, subpath) in dirs {
            let scan = SkillScanner.scan(directory: dir, source: .project(root: project.root, subpath: subpath),
                                         skipOnlineOnly: true)
            result.skills += scan.skills
            result.issues += scan.issues
        }

        var seenPlugins = Set<String>()
        for name in ["settings.json", "settings.local.json"] {
            let file = project.root.appending(path: ".claude/\(name)")
            guard LocalFile.isDownloaded(file) else { continue }
            let enabled = SettingsReader.enabledPlugins(settingsFile: file).filter(\.value)
            let wanted = Set(enabled.keys).subtracting(seenPlugins)
            guard !wanted.isEmpty else { continue }
            let loaded = PluginRegistry.loadPlugins(store: paths.userPluginStore, enabledPlugins: enabled,
                                                    scope: .project(root: project.root), only: wanted)
            result.plugins += loaded.plugins
            result.issues += loaded.issues
            seenPlugins.formUnion(loaded.plugins.map(\.pluginID))
        }
        return result
    }

    /// `.claude/skills` folders in the project root and in subfolders up to
    /// `maxDepth` levels down. Only folder names are checked; nothing is read.
    /// Throws only when the project root itself can't be listed.
    public static func skillDirectories(in root: URL) throws -> [(dir: URL, subpath: String?)] {
        let fm = FileManager.default
        func skillsDir(_ folder: URL) -> URL? {
            let d = folder.appending(path: ".claude/skills", directoryHint: .isDirectory)
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: d.path, isDirectory: &isDir) && isDir.boolValue ? d : nil
        }
        func subfolders(_ folder: URL) throws -> [URL] {
            try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                       options: [.skipsHiddenFiles])
                .filter { url in
                    guard !skippedFolders.contains(url.lastPathComponent),
                          let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
                    return v.isDirectory == true && v.isSymbolicLink != true   // no symlink loops
                }
                .sorted { $0.path < $1.path }
        }

        var found: [(dir: URL, subpath: String?)] = []
        if let d = skillsDir(root) { found.append((d, nil)) }
        var frontier = try subfolders(root)          // throws if root is unreadable
        var depth = 1
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        while !frontier.isEmpty && depth <= maxDepth {
            var next: [URL] = []
            for folder in frontier {
                if let d = skillsDir(folder) {
                    found.append((d, String(folder.path.dropFirst(rootPrefix.count))))
                }
                if depth < maxDepth { next += (try? subfolders(folder)) ?? [] }
            }
            frontier = next
            depth += 1
        }
        return found
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SkillsManagerCore && swift test 2>&1 | tail -5`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add SkillsManagerCore
git commit -m "core: scan projects for skills, nested skills, and project plugins

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Cowork plugins and Claude-account skills

**Files:**
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/CoworkPlugins.swift`
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/AccountSkills.swift`
- Test: `SkillsManagerCore/Tests/SkillsManagerCoreTests/DesktopSourcesTests.swift`

**Interfaces:**
- Consumes: `PluginStore`, `PluginRegistry.loadPlugins(store:...)`, `SettingsReader.enabledPlugins`, `SkillScanner.scanOne`
- Produces:
  - `CoworkPlugins.load(sessionsDir: URL) -> PluginLoadResult` (every plugin has `scope == .cowork`)
  - `struct AccountSkillsResult: Sendable { var skills: [Skill]; var lastSynced: Date?; var issues: [ParseIssue] }`
  - `AccountSkills.load(dir: URL) -> AccountSkillsResult`

- [ ] **Step 1: Write the failing tests**

`DesktopSourcesTests.swift`:

```swift
import Foundation
import Testing
@testable import SkillsManagerCore

@Test func coworkPluginsLoadFromEachAccountStore() throws {
    let t = try TempTree(); defer { t.remove() }
    let store = "cowork/acct/org/cowork_plugins"
    try t.write(#"""
    {"version": 2, "plugins": {"helper@kw": [{"scope": "user", "version": "0.2.2"}]}}
    """#, to: "\(store)/installed_plugins.json")
    try t.write(#"{"name": "helper", "description": "Cowork helper"}"#,
                to: "\(store)/cache/kw/helper/0.2.2/.claude-plugin/plugin.json")
    try t.skill("assist", in: "\(store)/cache/kw/helper/0.2.2/skills")
    try t.write(#"{"enabledPlugins": {"helper@kw": false}}"#, to: "cowork/acct/org/cowork_settings.json")

    let r = CoworkPlugins.load(sessionsDir: t.url("cowork"))
    #expect(r.issues.isEmpty)
    let p = try #require(r.plugins.first)
    #expect(p.pluginID == "helper@kw")
    #expect(p.scope == .cowork)
    #expect(p.isEnabled == false)
    #expect(p.skills.map(\.folderName) == ["assist"])
}

@Test func accountSkillsSplitByCreatorAndKeepDisabled() throws {
    let t = try TempTree(); defer { t.remove() }
    let base = "acct/one/two"
    try t.write(#"""
    {"lastUpdated": 1790273572879, "skills": [
      {"skillId": "skill_1", "name": "my-voice", "creatorType": "user", "enabled": true},
      {"skillId": "skill_2", "name": "my-old", "creatorType": "user", "enabled": false},
      {"skillId": "pdf", "name": "pdf", "creatorType": "anthropic", "enabled": true},
      {"skillId": "gone", "name": "gone", "creatorType": "user", "enabled": true}
    ]}
    """#, to: "\(base)/manifest.json")
    for n in ["my-voice", "my-old", "pdf"] { try t.skill(n, in: "\(base)/skills") }

    let r = AccountSkills.load(dir: t.url("acct"))
    let byName = Dictionary(uniqueKeysWithValues: r.skills.map { ($0.folderName, $0) })
    #expect(byName["my-voice"]?.source == .account(userMade: true))
    #expect(byName["my-old"]?.isEnabled == false)
    #expect(byName["pdf"]?.source == .account(userMade: false))
    #expect(byName["gone"] == nil)                       // listed but no files: skipped quietly
    #expect(abs((r.lastSynced?.timeIntervalSince1970 ?? 0) - 1790273572.879) < 0.001)
    #expect(r.issues.isEmpty)
}

@Test func brokenAccountManifestIsOneIssue() throws {
    let t = try TempTree(); defer { t.remove() }
    try t.write("{nope", to: "acct/a/b/manifest.json")
    let r = AccountSkills.load(dir: t.url("acct"))
    #expect(r.skills.isEmpty)
    #expect(r.issues.map(\.detail) == ["Couldn't read your Claude account's skill list. Claude account skills may be missing."])
    #expect(AccountSkills.load(dir: t.url("missing")).issues.isEmpty)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SkillsManagerCore && swift test --filter DesktopSources 2>&1 | tail -5`
Expected: compile error — `CoworkPlugins`, `AccountSkills` not defined.

- [ ] **Step 3: Implement**

`CoworkPlugins.swift`:

```swift
import Foundation

/// Cowork keeps its own plugin set per account, in Claude Code's plugin layout:
/// local-agent-mode-sessions/<account>/<org>/cowork_plugins/ plus
/// cowork_settings.json (enabledPlugins).
public enum CoworkPlugins {
    public static func load(sessionsDir: URL) -> PluginLoadResult {
        let fm = FileManager.default
        func children(_ u: URL) -> [URL] {
            (try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        }
        var result = PluginLoadResult()
        var seen = Set<String>()
        for a in children(sessionsDir).sorted(by: { $0.path < $1.path }) where a.lastPathComponent != "skills-plugin" {
            for b in children(a).sorted(by: { $0.path < $1.path }) {
                let store = PluginStore(root: b.appending(path: "cowork_plugins", directoryHint: .isDirectory))
                guard fm.fileExists(atPath: store.installedPluginsFile.path) else { continue }
                let enabled = SettingsReader.enabledPlugins(settingsFile: b.appending(path: "cowork_settings.json"))
                let loaded = PluginRegistry.loadPlugins(store: store, enabledPlugins: enabled, scope: .cowork, only: nil)
                result.issues += loaded.issues
                for plugin in loaded.plugins where seen.insert(plugin.pluginID).inserted {
                    result.plugins.append(plugin)
                }
            }
        }
        return result
    }
}
```

`AccountSkills.swift`:

```swift
import Foundation

public struct AccountSkillsResult: Sendable {
    public var skills: [Skill] = []
    public var lastSynced: Date?
    public var issues: [ParseIssue] = []
}

/// The Claude desktop app's local copy of the skills in the user's Claude
/// account: skills-plugin/<account>/<org>/{manifest.json, skills/<name>/SKILL.md}.
public enum AccountSkills {
    struct Manifest: Decodable {
        let lastUpdated: Double?
        let skills: [Entry]
        struct Entry: Decodable {
            let name: String
            let creatorType: String?
            let enabled: Bool?
        }
    }

    public static func load(dir: URL) -> AccountSkillsResult {
        let fm = FileManager.default
        func children(_ u: URL) -> [URL] {
            (try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        }
        var result = AccountSkillsResult()
        var seen = Set<String>()
        for a in children(dir).sorted(by: { $0.path < $1.path }) {
            for b in children(a).sorted(by: { $0.path < $1.path }) {
                let manifestFile = b.appending(path: "manifest.json")
                guard fm.fileExists(atPath: manifestFile.path) else { continue }
                guard let data = try? Data(contentsOf: manifestFile),
                      let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
                    result.issues.append(ParseIssue(
                        location: manifestFile,
                        detail: "Couldn't read your Claude account's skill list. Claude account skills may be missing."))
                    continue
                }
                if let ms = manifest.lastUpdated {
                    let date = Date(timeIntervalSince1970: ms / 1000)
                    result.lastSynced = max(result.lastSynced ?? date, date)
                }
                for entry in manifest.skills where seen.insert(entry.name).inserted {
                    let folder = b.appending(path: "skills/\(entry.name)", directoryHint: .isDirectory)
                    let source = SkillSource.account(userMade: entry.creatorType == "user")
                    switch SkillScanner.scanOne(folder: folder, source: source, isEnabled: entry.enabled ?? true) {
                    case .skill(let skill): result.skills.append(skill)
                    case .issue(let issue): result.issues.append(issue)
                    case .notASkill: break     // listed but not synced yet — not the user's problem
                    }
                }
            }
        }
        result.skills.sort { $0.folderName < $1.folderName }
        return result
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SkillsManagerCore && swift test 2>&1 | tail -5`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add SkillsManagerCore
git commit -m "core: read Cowork plugins and Claude-account skills

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Note folders, folder classification, markdown blocks

**Files:**
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/NoteFolders.swift`
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/MarkdownBlocks.swift`
- Test: `SkillsManagerCore/Tests/SkillsManagerCoreTests/NotesTests.swift`

**Interfaces:**
- Produces:
  - `enum FolderKind: Sendable, Equatable { case project, notes, neither }`
  - `struct NoteFile: Sendable, Hashable, Identifiable { let url: URL; let name: String; let lastModified: Date?; var id: String }`
  - `struct NoteFolder: Sendable, Hashable, Identifiable { let url: URL; let name: String; let files: [NoteFile]; var id: String }`
  - `NoteFolders.classify(_ folder: URL) -> FolderKind`
  - `NoteFolders.load(_ folder: URL) -> NoteFolder?`
  - `enum MarkdownBlock: Sendable, Hashable { case heading(level: Int, text: String), paragraph(String), bullet(String), numbered(String), code(String) }`
  - `MarkdownBlocks.parse(_ text: String) -> [MarkdownBlock]`

- [ ] **Step 1: Write the failing tests**

`NotesTests.swift`:

```swift
import Foundation
import Testing
@testable import SkillsManagerCore

@Test func classifyFolders() throws {
    let t = try TempTree(); defer { t.remove() }
    try t.skill("x", in: "proj/.claude/skills")
    try t.write("{}", to: "settingsOnly/.claude/settings.json")
    try t.write("# Brief", to: "brain/skills/morning-brief.md")
    try t.skill("y", in: "bareSkills")            // not loaded by Claude → not a project
    try t.write("hi", to: "empty/readme.txt")

    #expect(NoteFolders.classify(t.url("proj")) == .project)
    #expect(NoteFolders.classify(t.url("settingsOnly")) == .project)
    #expect(NoteFolders.classify(t.url("brain/skills")) == .notes)
    #expect(NoteFolders.classify(t.url("bareSkills")) == .neither)
    #expect(NoteFolders.classify(t.url("empty")) == .neither)
}

@Test func loadListsTopLevelMarkdownOnly() throws {
    let t = try TempTree(); defer { t.remove() }
    try t.write("a", to: "brain/skills/b-note.md")
    try t.write("a", to: "brain/skills/a-note.md")
    try t.write("a", to: "brain/skills/deeper/c-note.md")
    try t.write("a", to: "brain/skills/image.png")

    let folder = try #require(NoteFolders.load(t.url("brain/skills")))
    #expect(folder.name == "skills")
    #expect(folder.files.map(\.name) == ["a-note.md", "b-note.md"])
    #expect(NoteFolders.load(t.url("missing")) == nil)
}

@Test func markdownBlocksParseCommonShapes() {
    let md = """
    ---
    name: skip-me
    ---
    # Morning brief
    Pull my calendar
    and my inbox.

    - first
    * second
    1. numbered
    ```
    code line
    ```
    ## Done
    """
    #expect(MarkdownBlocks.parse(md) == [
        .heading(level: 1, text: "Morning brief"),
        .paragraph("Pull my calendar and my inbox."),
        .bullet("first"),
        .bullet("second"),
        .numbered("numbered"),
        .code("code line"),
        .heading(level: 2, text: "Done"),
    ])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SkillsManagerCore && swift test --filter Notes 2>&1 | tail -5`
Expected: compile error — `NoteFolders` not defined.

- [ ] **Step 3: Implement**

`NoteFolders.swift`:

```swift
import Foundation

public enum FolderKind: Sendable, Equatable {
    case project    // has .claude/skills or .claude/settings.json — Claude Code loads it
    case notes      // has top-level .md files
    case neither
}

public struct NoteFile: Sendable, Hashable, Identifiable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let lastModified: Date?
}

public struct NoteFolder: Sendable, Hashable, Identifiable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let files: [NoteFile]
}

/// User-added markdown folders (spec §5.3–5.4). Not skills; Claude doesn't
/// run them on its own.
public enum NoteFolders {
    public static func classify(_ folder: URL) -> FolderKind {
        let fm = FileManager.default
        let claude = folder.appending(path: ".claude", directoryHint: .isDirectory)
        if fm.fileExists(atPath: claude.appending(path: "skills").path)
            || fm.fileExists(atPath: claude.appending(path: "settings.json").path) {
            return .project
        }
        return markdownFiles(in: folder).isEmpty ? .neither : .notes
    }

    public static func load(_ folder: URL) -> NoteFolder? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        let files = markdownFiles(in: folder).map { url in
            NoteFile(url: url, name: url.lastPathComponent,
                     lastModified: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate)
        }
        return NoteFolder(url: folder, name: folder.lastPathComponent, files: files)
    }

    private static func markdownFiles(in folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                       options: [.skipsHiddenFiles])) ?? [])
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
```

`MarkdownBlocks.swift`:

```swift
import Foundation

public enum MarkdownBlock: Sendable, Hashable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case numbered(String)
    case code(String)
}

/// Just enough block structure to show a note as formatted text. Inline
/// styling (bold, links, `code`) is left to AttributedString in the view.
public enum MarkdownBlocks {
    public static func parse(_ text: String) -> [MarkdownBlock] {
        var lines = text.components(separatedBy: .newlines)
        // Drop a leading frontmatter block.
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            lines.removeSubrange(0...end)
        }

        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String]? = nil

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let c = code { blocks.append(.code(c.joined(separator: "\n"))); code = nil }
                else { flush(); code = [] }
                continue
            }
            if code != nil { code!.append(raw); continue }
            if line.isEmpty { flush(); continue }
            if let hashes = line.firstIndex(where: { $0 != "#" }), line.hasPrefix("#"),
               line[hashes] == " ", line.distance(from: line.startIndex, to: hashes) <= 6 {
                flush()
                blocks.append(.heading(level: line.distance(from: line.startIndex, to: hashes),
                                       text: String(line[hashes...]).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flush(); blocks.append(.bullet(String(line.dropFirst(2))))
            } else if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
                      line[line.index(after: dot)...].hasPrefix(" ") {
                flush(); blocks.append(.numbered(String(line[line.index(dot, offsetBy: 2)...])))
            } else {
                paragraph.append(line)
            }
        }
        if let c = code { blocks.append(.code(c.joined(separator: "\n"))) }
        flush()
        return blocks
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SkillsManagerCore && swift test 2>&1 | tail -5`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add SkillsManagerCore
git commit -m "core: note folders, folder classification, markdown blocks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Library merge — rows, tags, overflow, copies differ, ignored copies

**Files:**
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/Library.swift`
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/WhereItWorks.swift`
- Test: `SkillsManagerCore/Tests/SkillsManagerCoreTests/LibraryTests.swift`

**Interfaces:**
- Consumes: `Skill`, `Plugin`, `PluginScope`, `Project`
- Produces:
  - `enum LocationTag: Sendable, Hashable { case global, account, cowork, project(name: String); var label: String }` with `static func sorted(_:) -> [LocationTag]`
  - `struct SkillLocation: Sendable, Hashable, Identifiable { let skill: Skill; let tag: LocationTag; let isIgnored: Bool; let differsFromPrimary: Bool }`
  - `struct SkillEntry: Sendable, Hashable, Identifiable { let id: String; let skill: Skill; let locations: [SkillLocation]; let copiesDiffer: Bool; var tags: [LocationTag] }`
  - `struct PluginLocation: Sendable, Hashable, Identifiable { let plugin: Plugin; let tag: LocationTag }`
  - `struct PluginEntry: Sendable, Hashable, Identifiable { let id: String; let plugin: Plugin; let locations: [PluginLocation]; var tags: [LocationTag] }`
  - `struct Library: Sendable { var skills: [SkillEntry]; var plugins: [PluginEntry]; var builtIn: [SkillEntry] }` with `static func build(personal:project:account:plugins:projects:) -> Library`
  - `TagLayout.split(_ tags: [LocationTag], maxProjects: Int = 2) -> (shown: [LocationTag], overflow: [LocationTag])`
  - `struct WhereLine: Sendable, Hashable, Identifiable { let label: String; let detail: String; let revealURL: URL?; let syncedAt: Date? }`
  - `WhereItWorks.lines(for: SkillEntry, lastSynced: Date?, home: URL) -> [WhereLine]`
  - `WhereItWorks.lines(for: PluginEntry) -> [WhereLine]`

- [ ] **Step 1: Write the failing tests**

`LibraryTests.swift`:

```swift
import Foundation
import Testing
@testable import SkillsManagerCore

private func skill(_ folder: String, _ source: SkillSource, dir: URL) -> Skill {
    Skill(folderName: folder, displayName: folder, summary: nil, argumentHint: nil,
          userInvocable: true, modelInvocable: true, whenToUse: nil,
          source: source, directory: dir, lastModified: nil)
}

private func plugin(_ id: String, _ scope: PluginScope) -> Plugin {
    Plugin(pluginID: id, name: String(id.split(separator: "@")[0]), marketplace: "m", summary: nil,
           provenance: nil, version: "1", contentDirectory: URL(fileURLWithPath: "/tmp/\(id)"),
           lastUpdated: nil, isEnabled: true, skills: [], commands: [], scope: scope)
}

@Test func mergesSameFolderNameAcrossGlobalAndProjects() throws {
    let t = try TempTree(); defer { t.remove() }
    let portfolio = try t.mkdir("Portfolio"), ring = try t.mkdir("Ring")
    let g = try t.skill("review", in: "home/.claude/skills", body: "same")
    let p1 = try t.skill("review", in: "Portfolio/.claude/skills", body: "same")
    let p2 = try t.skill("review", in: "Ring/.claude/skills", body: "different")
    let projects = [Project(root: portfolio, displayName: "Portfolio"), Project(root: ring, displayName: "Ring")]

    let lib = Library.build(
        personal: [skill("review", .personal, dir: g)],
        project: [skill("review", .project(root: ring, subpath: nil), dir: p2),
                  skill("review", .project(root: portfolio, subpath: nil), dir: p1)],
        account: [], plugins: [], projects: projects)

    #expect(lib.skills.count == 1)
    let e = lib.skills[0]
    #expect(e.skill.source == .personal)                       // Global copy wins
    #expect(e.tags == [.global, .project(name: "Portfolio"), .project(name: "Ring")])
    #expect(e.copiesDiffer)
    let ringLoc = try #require(e.locations.first { $0.tag == .project(name: "Ring") })
    #expect(ringLoc.isIgnored && ringLoc.differsFromPrimary)
    let pfLoc = try #require(e.locations.first { $0.tag == .project(name: "Portfolio") })
    #expect(pfLoc.isIgnored && !pfLoc.differsFromPrimary)
}

@Test func projectOnlySkillIsNotIgnored() throws {
    let t = try TempTree(); defer { t.remove() }
    let root = try t.mkdir("P")
    let d = try t.skill("solo", in: "P/.claude/skills")
    let lib = Library.build(personal: [], project: [skill("solo", .project(root: root, subpath: nil), dir: d)],
                            account: [], plugins: [], projects: [Project(root: root, displayName: "P")])
    #expect(lib.skills[0].locations[0].isIgnored == false)
    #expect(lib.skills[0].copiesDiffer == false)
}

@Test func accountSkillsStaySeparateAndBuiltInsGoAside() {
    let d = URL(fileURLWithPath: "/tmp/x")
    let lib = Library.build(
        personal: [skill("pdf", .personal, dir: d)], project: [],
        account: [skill("pdf", .account(userMade: false), dir: d), skill("voice", .account(userMade: true), dir: d)],
        plugins: [], projects: [])
    #expect(lib.skills.map(\.id) == ["skill:pdf", "account:voice"])   // sorted by name
    #expect(lib.builtIn.map(\.id) == ["account:pdf"])
    #expect(lib.skills.first { $0.id == "account:voice" }?.tags == [.account])
}

@Test func pluginsMergeByIDWithScopeTags() {
    let root = URL(fileURLWithPath: "/w/Ring", isDirectory: true)
    let lib = Library.build(personal: [], project: [], account: [],
        plugins: [plugin("figma@m", .project(root: root)), plugin("figma@m", .user), plugin("helper@kw", .cowork)],
        projects: [Project(root: root, displayName: "Ring")])
    let figma = lib.plugins.first { $0.id == "figma@m" }
    #expect(figma?.tags == [.global, .project(name: "Ring")])
    #expect(figma?.plugin.scope == .user)
    #expect(lib.plugins.first { $0.id == "helper@kw" }?.tags == [.cowork])
}

@Test func tagOverflowKeepsNonProjectTagsAndTwoProjects() {
    let tags: [LocationTag] = [.global, .project(name: "A"), .project(name: "B"), .project(name: "C"), .project(name: "D")]
    let s = TagLayout.split(tags)
    #expect(s.shown == [.global, .project(name: "A"), .project(name: "B")])
    #expect(s.overflow == [.project(name: "C"), .project(name: "D")])
    #expect(TagLayout.split([.project(name: "A")]).overflow.isEmpty)
}

@Test func whereItWorksLinesExplainPrecedenceAndNesting() throws {
    let t = try TempTree(); defer { t.remove() }
    let home = try t.mkdir("home"), pf = try t.mkdir("Portfolio")
    let g = try t.skill("review", in: "home/.claude/skills")
    let p = try t.skill("review", in: "Portfolio/.claude/skills")
    let n = try t.skill("review", in: "Portfolio/website/.claude/skills")
    let lib = Library.build(
        personal: [skill("review", .personal, dir: g)],
        project: [skill("review", .project(root: pf, subpath: nil), dir: p),
                  skill("review", .project(root: pf, subpath: "website"), dir: n)],
        account: [], plugins: [], projects: [Project(root: pf, displayName: "Portfolio")])

    let lines = WhereItWorks.lines(for: lib.skills[0], lastSynced: nil, home: home)
    #expect(lines.map(\.label) == ["Global", "Portfolio", "Portfolio › website"])
    #expect(lines[0].detail == "~/.claude/skills/review")
    #expect(lines[1].detail == "Ignored — Claude uses the Global copy")
    #expect(lines[2].detail == "Ignored — Claude uses the Global copy")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SkillsManagerCore && swift test --filter Library 2>&1 | tail -5`
Expected: compile error — `Library` not defined.

- [ ] **Step 3: Implement**

`Library.swift`:

```swift
import Foundation

/// Where an item works, as shown on its tag (spec §4.5).
public enum LocationTag: Sendable, Hashable {
    case global
    case account
    case cowork
    case project(name: String)

    public var label: String {
        switch self {
        case .global: "Global"
        case .account: "Claude account"
        case .cowork: "Cowork"
        case .project(let name): name
        }
    }

    var rank: Int {
        switch self {
        case .global: return 0
        case .account: return 1
        case .cowork: return 2
        case .project: return 3
        }
    }

    public var isProject: Bool {
        if case .project = self { return true }
        return false
    }

    /// Global, Claude account, Cowork, then projects alphabetically; no duplicates.
    public static func sorted(_ tags: [LocationTag]) -> [LocationTag] {
        var seen = Set<LocationTag>()
        return tags.filter { seen.insert($0).inserted }.sorted { a, b in
            a.rank != b.rank ? a.rank < b.rank
                : a.label.localizedStandardCompare(b.label) == .orderedAscending
        }
    }
}

public struct SkillLocation: Sendable, Hashable, Identifiable {
    public var id: String { skill.id }
    public let skill: Skill
    public let tag: LocationTag
    /// A Global copy exists, so Claude ignores this project copy.
    public let isIgnored: Bool
    /// SKILL.md isn't byte-identical to the copy Claude uses.
    public let differsFromPrimary: Bool
}

public struct SkillEntry: Sendable, Hashable, Identifiable {
    public let id: String            // "skill:<folder>" or "account:<folder>"
    public let skill: Skill          // the copy Claude uses
    public let locations: [SkillLocation]
    public let copiesDiffer: Bool
    public var tags: [LocationTag] { LocationTag.sorted(locations.map(\.tag)) }
}

public struct PluginLocation: Sendable, Hashable, Identifiable {
    public var id: String { "\(plugin.pluginID)|\(tag.label)" }
    public let plugin: Plugin
    public let tag: LocationTag
}

public struct PluginEntry: Sendable, Hashable, Identifiable {
    public let id: String            // pluginID
    public let plugin: Plugin        // user-scope copy when there is one
    public let locations: [PluginLocation]
    public var tags: [LocationTag] { LocationTag.sorted(locations.map(\.tag)) }
}

public struct Library: Sendable {
    public var skills: [SkillEntry] = []
    public var plugins: [PluginEntry] = []
    /// Anthropic's built-in Claude-account skills (collapsed group).
    public var builtIn: [SkillEntry] = []

    public init(skills: [SkillEntry] = [], plugins: [PluginEntry] = [], builtIn: [SkillEntry] = []) {
        self.skills = skills
        self.plugins = plugins
        self.builtIn = builtIn
    }

    public static func build(personal: [Skill], project: [Skill], account: [Skill],
                             plugins: [Plugin], projects: [Project]) -> Library {
        let names = Dictionary(projects.map { ($0.root.path, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        func tag(for skill: Skill) -> LocationTag {
            switch skill.source {
            case .personal, .shared, .plugin: .global
            case .account: .account
            case .project(let root, _): .project(name: names[root.path] ?? root.lastPathComponent)
            }
        }

        var lib = Library()

        // Personal + project skills merge by folder name (= the command).
        let grouped = Dictionary(grouping: personal + project, by: \.folderName)
        for (folder, copies) in grouped {
            let primary = copies.first { $0.source == .personal }
                ?? copies.sorted { tag(for: $0).label.localizedStandardCompare(tag(for: $1).label) == .orderedAscending }[0]
            let hasGlobal = primary.source == .personal
            let primaryData = skillData(primary)
            let locations = copies.map { copy in
                SkillLocation(skill: copy, tag: tag(for: copy),
                              isIgnored: hasGlobal && copy.source != .personal,
                              differsFromPrimary: copy.id != primary.id && skillData(copy) != primaryData)
            }
            .sorted { a, b in
                let order = LocationTag.sorted([a.tag, b.tag])
                return a.tag == b.tag ? a.skill.id < b.skill.id : order.first == a.tag
            }
            lib.skills.append(SkillEntry(id: "skill:\(folder)", skill: primary, locations: locations,
                                         copiesDiffer: locations.contains(where: \.differsFromPrimary)))
        }

        // Claude-account skills are namespaced commands: never merged.
        for skill in account {
            let entry = SkillEntry(id: "account:\(skill.folderName)", skill: skill,
                                   locations: [SkillLocation(skill: skill, tag: .account, isIgnored: false,
                                                             differsFromPrimary: false)],
                                   copiesDiffer: false)
            if case .account(userMade: true) = skill.source { lib.skills.append(entry) } else { lib.builtIn.append(entry) }
        }

        // Plugins merge by ID.
        for (id, copies) in Dictionary(grouping: plugins, by: \.pluginID) {
            let locations = copies.map { p -> PluginLocation in
                let t: LocationTag = switch p.scope {
                case .user: .global
                case .cowork: .cowork
                case .project(let root): .project(name: names[root.path] ?? root.lastPathComponent)
                }
                return PluginLocation(plugin: p, tag: t)
            }
            let primary = copies.first { $0.scope == .user } ?? copies[0]
            lib.plugins.append(PluginEntry(id: id, plugin: primary, locations: locations))
        }

        let byName: (SkillEntry, SkillEntry) -> Bool = {
            $0.skill.displayName.localizedStandardCompare($1.skill.displayName) == .orderedAscending
        }
        lib.skills.sort { byName($0, $1) || ($0.skill.displayName == $1.skill.displayName && $0.id < $1.id) }
        lib.builtIn.sort(by: byName)
        lib.plugins.sort { $0.plugin.name.localizedStandardCompare($1.plugin.name) == .orderedAscending }
        return lib
    }

    private static func skillData(_ skill: Skill) -> Data? {
        try? Data(contentsOf: skill.directory.appending(path: "SKILL.md"))
    }
}

public enum TagLayout {
    /// Every non-project tag, then at most `maxProjects` project tags; the rest overflow into "+N".
    public static func split(_ tags: [LocationTag], maxProjects: Int = 2) -> (shown: [LocationTag], overflow: [LocationTag]) {
        let sorted = LocationTag.sorted(tags)
        let fixed = sorted.filter { !$0.isProject }
        let projects = sorted.filter(\.isProject)
        return (fixed + projects.prefix(maxProjects), Array(projects.dropFirst(maxProjects)))
    }
}
```

`WhereItWorks.swift`:

```swift
import Foundation

public struct WhereLine: Sendable, Hashable, Identifiable {
    public var id: String { label + "|" + detail + "|" + (revealURL?.path ?? "") }
    public let label: String
    public let detail: String
    public let revealURL: URL?
    public let syncedAt: Date?     // Claude-account line only; the view formats it relatively
}

/// The detail page's "Where it works" lines (spec §5.2).
public enum WhereItWorks {
    public static func lines(for entry: SkillEntry, lastSynced: Date?, home: URL) -> [WhereLine] {
        entry.locations.map { loc in
            switch loc.skill.source {
            case .account:
                return WhereLine(label: "Claude account", detail: "Synced from your Claude account",
                                 revealURL: nil, syncedAt: lastSynced)
            case .project(_, let subpath):
                let label = subpath.map { "\(loc.tag.label) › \($0)" } ?? loc.tag.label
                let detail: String
                if loc.isIgnored { detail = "Ignored — Claude uses the Global copy" }
                else if loc.differsFromPrimary { detail = "This copy is different from the others" }
                else if let subpath { detail = "Only when Claude is opened in the \(subpath) folder" }
                else { detail = abbreviate(loc.skill.directory, home: home) }
                return WhereLine(label: label, detail: detail, revealURL: loc.skill.directory, syncedAt: nil)
            case .personal, .shared, .plugin:
                return WhereLine(label: loc.tag.label, detail: abbreviate(loc.skill.directory, home: home),
                                 revealURL: loc.skill.directory, syncedAt: nil)
            }
        }
    }

    public static func lines(for entry: PluginEntry) -> [WhereLine] {
        entry.locations
            .sorted { LocationTag.sorted([$0.tag, $1.tag]).first == $0.tag }
            .map { loc in
                let detail = switch loc.plugin.scope {
                case .user: "On for all your projects"
                case .project: "Turned on for this project"
                case .cowork: "Installed in Cowork"
                }
                var reveal: URL? = loc.plugin.contentDirectory
                if case .project(let root) = loc.plugin.scope {
                    reveal = root.appending(path: ".claude", directoryHint: .isDirectory)
                }
                return WhereLine(label: loc.tag.label, detail: detail, revealURL: reveal, syncedAt: nil)
            }
    }

    static func abbreviate(_ url: URL, home: URL) -> String {
        let h = Canonical.path(home.path), p = Canonical.path(url.path)
        return p.hasPrefix(h + "/") ? "~" + p.dropFirst(h.count) : p
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SkillsManagerCore && swift test 2>&1 | tail -5`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add SkillsManagerCore
git commit -m "core: library merge with location tags, overflow, and where-it-works lines

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Inventory composition, failure isolation, privacy

**Files:**
- Modify: `SkillsManagerCore/Sources/SkillsManagerCore/Inventory.swift`
- Modify: `SkillsManagerCore/Sources/SkillsManagerCore/Version.swift` (`coreVersion = "0.4.0"`)
- Test: `SkillsManagerCore/Tests/SkillsManagerCoreTests/InventoryDiscoveryTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–6
- Produces:
  - `Inventory` new fields: `projects: [Project]`, `projectSkills: [Skill]`, `projectPlugins: [Plugin]`, `coworkPlugins: [Plugin]`, `accountSkills: [Skill]`, `accountLastSynced: Date?`, `notes: [NoteFolder]`, `library: Library`
  - `Inventory.load(paths: ClaudePaths, addedFolders: [URL] = [], includeProjects: Bool = true) -> Inventory`
  - `Inventory.projectWatchTargets: [URL]` (each project's `.claude` folder)

- [ ] **Step 1: Write the failing tests**

`InventoryDiscoveryTests.swift`:

```swift
import Foundation
import Testing
@testable import SkillsManagerCore

/// A home with a terminal project, a Cowork folder, a Claude-account manifest,
/// and an added note folder.
private func makeHome() throws -> (TempTree, ClaudePaths) {
    let t = try TempTree()
    let home = try t.mkdir("home")
    let proj = try t.mkdir("home/Code/Portfolio")
    try t.skill("brand-voice", in: "home/Code/Portfolio/.claude/skills")
    try t.skill("shared-name", in: "home/Code/Portfolio/.claude/skills")
    try t.skill("shared-name", in: "home/.claude/skills")
    try t.write(#"{"projects": {"\#(proj.path)": {}}}"#, to: "home/.claude.json")
    let cw = try t.mkdir("home/Docs/CoworkThing")
    try t.skill("cw-skill", in: "home/Docs/CoworkThing/.claude/skills")
    let support = "home/Library/Application Support/Claude"
    try t.write(#"{"userSelectedFolders": ["\#(cw.path)"], "emailAddress": "a@b.c"}"#,
                to: "\(support)/local-agent-mode-sessions/a/b/local_1.json")
    try t.write(#"{"lastUpdated": 1000, "skills": [{"name": "voice", "creatorType": "user", "enabled": true}]}"#,
                to: "\(support)/local-agent-mode-sessions/skills-plugin/a/b/manifest.json")
    try t.skill("voice", in: "\(support)/local-agent-mode-sessions/skills-plugin/a/b/skills")
    try t.write("# Brief", to: "home/brain/skills/morning-brief.md")
    return (t, ClaudePaths(home: home))
}

@Test func loadsEverySourceIntoTheLibrary() throws {
    let (t, paths) = try makeHome(); defer { t.remove() }
    let inv = Inventory.load(paths: paths, addedFolders: [t.url("home/brain/skills")])

    #expect(inv.projects.map(\.displayName) == ["CoworkThing", "Portfolio"])
    #expect(Set(inv.projectSkills.map(\.folderName)) == ["brand-voice", "shared-name", "cw-skill"])
    #expect(inv.accountSkills.map(\.folderName) == ["voice"])
    #expect(inv.notes.map(\.name) == ["skills"])
    #expect(inv.issues.isEmpty)

    let tagsByID = Dictionary(uniqueKeysWithValues: inv.library.skills.map { ($0.id, $0.tags) })
    #expect(tagsByID["skill:brand-voice"] == [.project(name: "Portfolio")])
    #expect(tagsByID["skill:shared-name"] == [.global, .project(name: "Portfolio")])
    #expect(tagsByID["account:voice"] == [.account])
    #expect(inv.projectWatchTargets.count == 2)
}

@Test func addedProjectFolderJoinsProjects() throws {
    let (t, paths) = try makeHome(); defer { t.remove() }
    try t.skill("extra", in: "elsewhere/NeverOpened/.claude/skills")
    let inv = Inventory.load(paths: paths, addedFolders: [t.url("elsewhere/NeverOpened")])
    #expect(inv.projects.contains { $0.displayName == "NeverOpened" })
    #expect(inv.library.skills.contains { $0.id == "skill:extra" })
}

@Test func addedFolderThatNoLongerFitsIsReported() throws {
    let (t, paths) = try makeHome(); defer { t.remove() }
    try t.mkdir("home/emptied")
    let inv = Inventory.load(paths: paths, addedFolders: [t.url("home/emptied")])
    #expect(inv.issues.map(\.detail) == ["This added folder no longer has Claude skills or markdown files."])
}

@Test func oneBrokenSourceLeavesTheRestLoaded() throws {
    let (t, paths) = try makeHome(); defer { t.remove() }
    try t.write("{broken", to: "home/.claude.json")
    let inv = Inventory.load(paths: paths)
    #expect(inv.projects.map(\.displayName) == ["CoworkThing"])        // Cowork still found
    #expect(inv.accountSkills.count == 1)
    #expect(inv.issues.count == 1)
}

@Test func projectsCanBeSkippedUntilTheUserAgrees() throws {
    let (t, paths) = try makeHome(); defer { t.remove() }
    let inv = Inventory.load(paths: paths, includeProjects: false)
    #expect(inv.projects.isEmpty && inv.projectSkills.isEmpty)
    #expect(inv.accountSkills.count == 1)    // account skills live in the app's own folder: no prompt
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SkillsManagerCore && swift test --filter InventoryDiscovery 2>&1 | tail -5`
Expected: compile error — `addedFolders`, `library` not members of `Inventory`.

- [ ] **Step 3: Implement**

Replace `Inventory.swift`:

```swift
import Foundation

/// Everything the app knows, loaded in one synchronous pass (callers move it
/// off the main thread). The filesystem is the source of truth — reload = re-scan.
public struct Inventory: Sendable {
    public var personalSkills: [Skill]
    public var sharedSkills: [Skill]
    public var plugins: [Plugin]                 // user scope
    public var issues: [ParseIssue]
    public var projects: [Project] = []
    public var projectSkills: [Skill] = []
    public var projectPlugins: [Plugin] = []
    public var coworkPlugins: [Plugin] = []
    public var accountSkills: [Skill] = []
    public var accountLastSynced: Date?
    public var notes: [NoteFolder] = []
    public var library = Library()

    public init(personalSkills: [Skill] = [], sharedSkills: [Skill] = [],
                plugins: [Plugin] = [], issues: [ParseIssue] = []) {
        self.personalSkills = personalSkills
        self.sharedSkills = sharedSkills
        self.plugins = plugins
        self.issues = issues
    }

    /// Each project's .claude folder, for the file watcher.
    public var projectWatchTargets: [URL] {
        projects.map { $0.root.appending(path: ".claude", directoryHint: .isDirectory) }
    }

    /// `includeProjects: false` skips everything that can trigger macOS
    /// folder-access prompts, until the user has seen the first-run note (spec §5.5).
    public static func load(paths: ClaudePaths, addedFolders: [URL] = [], includeProjects: Bool = true) -> Inventory {
        let enabled = SettingsReader.enabledPlugins(settingsFile: paths.settingsFile)
        let lock = SkillLock.load(file: paths.agentsLockFile)
        let personal = SkillScanner.scan(directory: paths.personalSkillsDir, source: .personal, lock: lock, lockScope: paths.sharedSkillsDir)
        let shared = SkillScanner.scan(directory: paths.sharedSkillsDir, source: .shared, lock: lock, lockScope: paths.sharedSkillsDir)
        let pluginResult = PluginRegistry.loadPlugins(paths: paths, enabledPlugins: enabled)

        // A shared skill symlinked into ~/.claude/skills is the same skill —
        // show it once, where Claude Code sees it (spec §6.5 duplicate rule).
        let personalResolved = Set(personal.skills.map {
            $0.directory.resolvingSymlinksInPath().path
        })
        let unconnectedShared = shared.skills.filter {
            !personalResolved.contains($0.directory.resolvingSymlinksInPath().path)
        }

        var inv = Inventory(
            personalSkills: personal.skills,
            sharedSkills: unconnectedShared,
            plugins: pluginResult.plugins,
            issues: personal.issues + shared.issues + pluginResult.issues)

        // Claude account + Cowork plugins: the desktop app's own folder, no prompts.
        let account = AccountSkills.load(dir: paths.accountSkillsDir)
        inv.accountSkills = account.skills
        inv.accountLastSynced = account.lastSynced
        inv.issues += account.issues
        let cowork = CoworkPlugins.load(sessionsDir: paths.coworkSessionsDir)
        inv.coworkPlugins = cowork.plugins
        inv.issues += cowork.issues

        // Added folders: projects vs. notes.
        var addedProjects: [URL] = []
        for folder in addedFolders {
            switch NoteFolders.classify(folder) {
            case .project: addedProjects.append(folder)
            case .notes: if let n = NoteFolders.load(folder) { inv.notes.append(n) }
            case .neither:
                inv.issues.append(ParseIssue(location: folder,
                    detail: "This added folder no longer has Claude skills or markdown files."))
            }
        }

        if includeProjects {
            let discovery = ProjectSources.discover(paths: paths, addedProjects: addedProjects)
            inv.projects = discovery.projects
            inv.issues += discovery.issues
            for project in discovery.projects {
                let scan = ProjectScanner.scan(project, paths: paths)
                inv.projectSkills += scan.skills
                inv.projectPlugins += scan.plugins
                inv.issues += scan.issues
            }
        }

        inv.library = Library.build(
            personal: inv.personalSkills, project: inv.projectSkills, account: inv.accountSkills,
            plugins: inv.plugins + inv.projectPlugins + inv.coworkPlugins, projects: inv.projects)
        return inv
    }
}
```

`Version.swift`: `public let coreVersion = "0.4.0"`.

- [ ] **Step 4: Run all tests (existing inventory tests must still pass)**

Run: `cd SkillsManagerCore && swift test 2>&1 | tail -5`
Expected: all pass. `emptyHomeLoadsEmptyInventory` still has zero issues (every new source is missing → normal).

- [ ] **Step 5: Real-machine smoke check (read-only)**

Add and run this one-off test locally **without committing it**, to confirm the readers accept the owner's real files:

```swift
@Test(.enabled(if: ProcessInfo.processInfo.environment["SM_REAL_HOME"] != nil))
func realHomeSmoke() {
    let inv = Inventory.load(paths: ClaudePaths(home: FileManager.default.homeDirectoryForCurrentUser))
    print("projects:", inv.projects.map(\.displayName))
    print("account:", inv.accountSkills.map(\.folderName))
    print("cowork plugins:", inv.coworkPlugins.map(\.pluginID))
    print("issues:", inv.issues.map(\.detail))
}
```

Run: `SM_REAL_HOME=1 swift test --filter realHomeSmoke 2>&1 | grep -E "projects:|account:|cowork|issues:"`
Expected: projects include `Portfolio`, `Skills Manager`, `Genesis Peptide`, `Ring` (no worktree names, no deleted folders); account includes `henry-portfolio-voice`, `henry-stylist`; cowork plugins include `cowork-plugin-management@knowledge-work-plugins`; no source-level "Couldn't read…" issues. Delete the test afterwards (`git status` must show it absent).

- [ ] **Step 6: Commit**

```bash
git add SkillsManagerCore
git commit -m "core: compose project, Cowork, account, and note sources into the library

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: App store — added folders, access flag, two watchers

**Files:**
- Modify: `App/FileWatcher.swift`
- Modify: `App/InventoryStore.swift`

**Interfaces:**
- Consumes: `Inventory.load(paths:addedFolders:includeProjects:)`, `Inventory.projectWatchTargets`, `NoteFolders.classify`, `FolderKind`, new `ClaudePaths` properties
- Produces (for Tasks 9–11):
  - `FileWatcher(root:targets:delay:onChange:)`, `FileWatcher.setTargets(_ targets: [URL])`
  - `InventoryStore.addedFolders: [URL]`
  - `InventoryStore.addFolder(_ url: URL) -> FolderKind` (adds only for `.project`/`.notes`; reloads)
  - `InventoryStore.removeFolder(_ url: URL)`
  - `InventoryStore.needsProjectAccessNote: Bool`
  - `InventoryStore.acknowledgeProjectAccess()`

- [ ] **Step 1: FileWatcher — delay parameter and mutable targets**

In `App/FileWatcher.swift`:

- Change `private let targetPrefixes: [String]` to `private var targetPrefixes: [String]` and add the doc line `/// Only touched on `queue` (FSEvents callbacks run there; setTargets hops there).`
- Change the init signature to `init(root: URL, targets: [URL], delay: TimeInterval = 1.0, onChange: @escaping @Sendable () -> Void)` and use `debouncer = Debouncer(delay: delay, queue: .main, action: onChange)`.
- Add below `init`:

```swift
    /// Replaces the watched targets (project folders come and go between loads).
    func setTargets(_ targets: [URL]) {
        let prefixes = targets.map(Self.canonicalize)
        queue.async { [self] in targetPrefixes = prefixes }
    }
```

- [ ] **Step 2: InventoryStore**

Replace `App/InventoryStore.swift`:

```swift
import Foundation
import Observation
import SkillsManagerCore

@MainActor
@Observable
final class InventoryStore {
    private(set) var inventory = Inventory()
    private(set) var isLoading = false
    private(set) var addedFolders: [URL]
    private(set) var needsProjectAccessNote: Bool
    private let paths = ClaudePaths()
    private let defaults = UserDefaults.standard
    private var watcher: FileWatcher?
    private var sourcesWatcher: FileWatcher?
    private var loadGeneration = 0

    private static let addedFoldersKey = "addedFolders"
    private static let projectAccessKey = "projectAccessAcknowledged"

    init() {
        addedFolders = (UserDefaults.standard.stringArray(forKey: Self.addedFoldersKey) ?? [])
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        needsProjectAccessNote = !UserDefaults.standard.bool(forKey: Self.projectAccessKey)
    }

    /// Idempotent: first call loads and starts watching; later calls are no-ops.
    func start() {
        guard watcher == nil else { return }
        reload()
        // Skills, plugins, settings, ~/.agents, Claude-account skills, and (after
        // each load) every project's .claude folder. 1 s debounce.
        watcher = FileWatcher(root: paths.home, targets: baseTargets) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        // Claude's session and project lists change on every message while
        // Claude is in use — a long debounce keeps rescans rare (spec §6.1).
        sourcesWatcher = FileWatcher(
            root: paths.home,
            targets: [paths.claudeJSON, paths.codeSessionsDir, paths.coworkSessionsDir],
            delay: 10
        ) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
    }

    private var baseTargets: [URL] {
        [paths.personalSkillsDir, paths.pluginsDir, paths.settingsFile, paths.agentsDir, paths.accountSkillsDir]
            + addedFolders
    }

    /// Generation counter (not an isLoading guard): a change landing mid-load
    /// starts a fresh scan, and a stale scan can never overwrite a newer one.
    func reload() {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        let paths = self.paths
        let added = addedFolders
        let includeProjects = !needsProjectAccessNote
        Task.detached(priority: .userInitiated) {
            let loaded = Inventory.load(paths: paths, addedFolders: added, includeProjects: includeProjects)
            await MainActor.run { [weak self] in
                guard let self, generation == self.loadGeneration else { return }
                self.inventory = loaded
                self.isLoading = false
                self.watcher?.setTargets(self.baseTargets + loaded.projectWatchTargets)
            }
        }
    }

    func acknowledgeProjectAccess() {
        defaults.set(true, forKey: Self.projectAccessKey)
        needsProjectAccessNote = false
        reload()
    }

    /// Adds a project or notes folder. Returns `.neither` (and adds nothing)
    /// for a folder with no Claude skills or markdown files.
    @discardableResult
    func addFolder(_ url: URL) -> FolderKind {
        let kind = NoteFolders.classify(url)
        guard kind != .neither else { return kind }
        let canonical = Canonical.url(url)
        guard !addedFolders.contains(canonical) else { return kind }
        addedFolders.append(canonical)
        saveAddedFolders()
        reload()
        return kind
    }

    /// Forgets the folder. Never touches the disk.
    func removeFolder(_ url: URL) {
        addedFolders.removeAll { $0.path == url.path }
        saveAddedFolders()
        reload()
    }

    private func saveAddedFolders() {
        defaults.set(addedFolders.map(\.path), forKey: Self.addedFoldersKey)
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodegen generate && xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -derivedDataPath build build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add App/FileWatcher.swift App/InventoryStore.swift
git commit -m "app: added folders, project-access flag, slow watcher for Claude session files

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Sidebar — tagged rows, new sections, Add Folder

> Invoke the design skills listed in Global Constraints before editing views.

**Files:**
- Create: `App/LocationTags.swift`
- Modify: `App/LibraryRows.swift`
- Modify: `App/LibraryView.swift`
- Modify: `App/SkillsManagerApp.swift`

**Interfaces:**
- Consumes: `Library`, `SkillEntry`, `PluginEntry`, `LocationTag`, `TagLayout.split`, `NoteFolder`, `NoteFile`, `InventoryStore.addFolder/removeFolder`, `FolderKind`
- Produces:
  - `LibrarySelection` cases: `.entry(String)` (SkillEntry.id), `.plugin(String)` (PluginEntry.id), `.skill(String)` (plugin sub-skill `Skill.id`), `.note(String)` (NoteFile.id), `.needsAttention`
  - `LocationTags(tags:)`, `TagPill(tag:)`, `NotASkillTag()`
  - `SkillEntryRow(entry:)`, `PluginRow(entry:)`, `NoteRow(file:)`
  - `Notification.Name.showAddFolder`

- [ ] **Step 1: Tag views**

`App/LocationTags.swift`:

```swift
import SwiftUI
import SkillsManagerCore

struct TagPill: View {
    let tag: LocationTag

    var body: some View {
        KindBadge(text: tag.label, tint: tint)
    }

    private var tint: Color {
        switch tag {
        case .global: .gray
        case .account: .blue
        case .cowork: .purple
        case .project: .teal
        }
    }
}

/// Dashed "Not a skill" tag for markdown notes.
struct NotASkillTag: View {
    var body: some View {
        Text("Not a skill")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2])).foregroundStyle(.secondary))
            .foregroundStyle(.secondary)
    }
}

/// Every non-project tag, two project tags, then "+N". Hover shows the rest
/// as a tooltip; click (or keyboard) opens a popover.
struct LocationTags: View {
    let tags: [LocationTag]
    @State private var showAll = false

    var body: some View {
        let split = TagLayout.split(tags)
        HStack(spacing: Spacing.xs) {
            ForEach(split.shown, id: \.self) { TagPill(tag: $0) }
            if !split.overflow.isEmpty {
                let names = split.overflow.map(\.label).joined(separator: ", ")
                Button("+\(split.overflow.count)") { showAll.toggle() }
                    .buttonStyle(.plain)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(.tertiary))
                    .contentShape(Capsule())
                    .help("Also in \(names)")
                    .accessibilityLabel("Also in \(names)")
                    .popover(isPresented: $showAll, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Also in").font(.cardLabel).foregroundStyle(.secondary)
                            ForEach(split.overflow, id: \.self) { Text($0.label) }
                        }
                        .padding(Spacing.md)
                    }
            }
        }
        .accessibilityElement(children: .contain)
    }
}
```

- [ ] **Step 2: Rows**

In `App/LibraryRows.swift`, add:

```swift
struct SkillEntryRow: View {
    let entry: SkillEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text(entry.skill.displayName)
                    if !entry.skill.isEnabled {
                        Text("Off").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if let summary = entry.skill.summary {
                    Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            HStack(spacing: Spacing.sm) {
                LocationTags(tags: entry.tags)
                if entry.copiesDiffer {
                    Text("Copies differ").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct NoteRow: View {
    let file: NoteFile

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(file.name).lineLimit(1)
            Spacer(minLength: Spacing.sm)
            NotASkillTag()
        }
        .padding(.vertical, 2)
    }
}
```

Change `PluginRow` to take the entry: replace `let plugin: Plugin` with `let entry: PluginEntry` and `private var plugin: Plugin { entry.plugin }`, and after the caption `Text` inside the inner `VStack` add `LocationTags(tags: entry.tags).padding(.top, 2)`.

- [ ] **Step 3: LibraryView**

In `App/LibraryView.swift`:

Replace `LibrarySelection`:

```swift
enum LibrarySelection: Hashable {
    case entry(String)    // SkillEntry.id
    case plugin(String)   // PluginEntry.id
    case skill(String)    // Skill.id — a skill inside a plugin
    case note(String)     // NoteFile.id
    case needsAttention
}
```

Add state: `@State private var builtInExpanded = false`, `@State private var expandedNotes: Set<String> = []`, `@State private var addFolderMessage: String?`.

Replace the `sidebar` `List` body's sections (keep the Plugins `DisclosureGroup` logic, now over entries):

```swift
            if !filteredPlugins.isEmpty {
                Section("Plugins") {
                    ForEach(filteredPlugins) { entry in
                        DisclosureGroup(isExpanded: Binding(
                            get: { !searchText.isEmpty || expandedPlugins.contains(entry.id) },
                            set: { newValue in
                                guard searchText.isEmpty else { return }
                                if newValue { expandedPlugins.insert(entry.id) } else { expandedPlugins.remove(entry.id) }
                            }
                        )) {
                            ForEach(entry.plugin.skills) { skill in
                                SkillRow(skill: skill).tag(LibrarySelection.skill(skill.id))
                            }
                        } label: {
                            PluginRow(entry: entry).tag(LibrarySelection.plugin(entry.id))
                        }
                    }
                }
            }
            if !filteredSkills.isEmpty {
                Section("Skills") {
                    ForEach(filteredSkills) { entry in
                        SkillEntryRow(entry: entry).tag(LibrarySelection.entry(entry.id))
                    }
                }
            }
            if !filteredShared.isEmpty {
                Section("Shared Skills") {
                    ForEach(filteredShared) { skill in
                        SkillRow(skill: skill).tag(LibrarySelection.skill(skill.id))
                    }
                }
            }
            if !filteredNotes.isEmpty {
                Section("Your Notes") {
                    ForEach(filteredNotes) { folder in
                        DisclosureGroup(isExpanded: Binding(
                            get: { !searchText.isEmpty || expandedNotes.contains(folder.id) },
                            set: { if $0 { expandedNotes.insert(folder.id) } else { expandedNotes.remove(folder.id) } }
                        )) {
                            ForEach(folder.files) { file in
                                NoteRow(file: file).tag(LibrarySelection.note(file.id))
                            }
                        } label: {
                            Label(folder.name, systemImage: "folder")
                                .contextMenu {
                                    Button("Remove from Skills Manager") { store.removeFolder(folder.url) }
                                }
                        }
                    }
                }
            }
            if !filteredBuiltIn.isEmpty {
                Section {
                    DisclosureGroup("Built into Claude (\(filteredBuiltIn.count))",
                                    isExpanded: Binding(get: { !searchText.isEmpty || builtInExpanded },
                                                        set: { builtInExpanded = $0 })) {
                        ForEach(filteredBuiltIn) { entry in
                            SkillEntryRow(entry: entry).tag(LibrarySelection.entry(entry.id))
                        }
                    }
                }
            }
            if !store.inventory.issues.isEmpty {
                Section {
                    Label("Needs Attention (\(store.inventory.issues.count))",
                          systemImage: "exclamationmark.triangle")
                        .tag(LibrarySelection.needsAttention)
                }
            }
```

After `.overlay { … }` on the `List`, add:

```swift
        .safeAreaInset(edge: .bottom) {
            Button { pickFolder() } label: {
                Label("Add Folder…", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .help("Add a project Claude hasn't opened yet, or a folder of markdown notes")
        }
        .alert("Can't add this folder", isPresented: Binding(get: { addFolderMessage != nil },
                                                               set: { if !$0 { addFolderMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(addFolderMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAddFolder)) { _ in pickFolder() }
```

Add the picker:

```swift
    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose a project folder or a folder of markdown notes."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if store.addFolder(url) == .neither {
            addFolderMessage = "This folder doesn't have Claude skills or markdown files."
        }
    }
```

Replace `isEmptyLibrary`, the `.skill`/`.plugin` detail cases, `allSkills`, and the filtering section:

```swift
    private var isEmptyLibrary: Bool {
        filteredPlugins.isEmpty && filteredSkills.isEmpty && filteredShared.isEmpty
            && filteredNotes.isEmpty && filteredBuiltIn.isEmpty && store.inventory.issues.isEmpty
    }
```

```swift
        case .entry(let id):
            if let entry = (library.skills + library.builtIn).first(where: { $0.id == id }) {
                SkillDetailView(skill: entry.skill, parentPlugin: nil, entry: entry,
                                accountLastSynced: store.inventory.accountLastSynced)
            } else {
                missingSelection
            }
        case .skill(let id):
            if let skill = allSkills.first(where: { $0.id == id }) {
                SkillDetailView(skill: skill, parentPlugin: parentPlugin(of: skill), entry: nil,
                                accountLastSynced: nil)
            } else {
                missingSelection
            }
        case .plugin(let id):
            if let entry = library.plugins.first(where: { $0.id == id }) {
                PluginDetailView(plugin: entry.plugin, entry: entry)
            } else {
                missingSelection
            }
        case .note(let id):
            if let file = store.inventory.notes.flatMap(\.files).first(where: { $0.id == id }) {
                NoteDetailView(file: file)
            } else {
                missingSelection
            }
```

```swift
    private var library: Library { store.inventory.library }

    /// Plugin sub-skills and unconnected shared skills (selected via `.skill`).
    private var allSkills: [Skill] {
        store.inventory.sharedSkills + library.plugins.flatMap(\.plugin.skills)
    }

    private func parentPlugin(of skill: Skill) -> Plugin? {
        guard case .plugin(let pluginID) = skill.source else { return nil }
        return library.plugins.first { $0.id == pluginID }?.plugin
    }

    // MARK: Filtering

    private var filteredPlugins: [PluginEntry] { library.plugins.filter { matches($0) } }
    private var filteredSkills: [SkillEntry] { library.skills.filter { matches($0) } }
    private var filteredBuiltIn: [SkillEntry] { library.builtIn.filter { matches($0) } }
    private var filteredShared: [Skill] { store.inventory.sharedSkills.filter { matches($0) } }
    private var filteredNotes: [NoteFolder] {
        guard !searchText.isEmpty else { return store.inventory.notes }
        let q = searchText.localizedLowercase
        return store.inventory.notes.compactMap { folder in
            let files = folder.files.filter { $0.name.localizedLowercase.contains(q) }
            if folder.name.localizedLowercase.contains(q) { return folder }
            return files.isEmpty ? nil : NoteFolder(url: folder.url, name: folder.name, files: files)
        }
    }

    private func matchesTags(_ tags: [LocationTag]) -> Bool {
        let q = searchText.localizedLowercase
        return tags.contains { $0.label.localizedLowercase.contains(q) }
    }

    private func matches(_ entry: SkillEntry) -> Bool {
        guard !searchText.isEmpty else { return true }
        return matches(entry.skill) || matchesTags(entry.tags)
    }

    private func matches(_ entry: PluginEntry) -> Bool {
        guard !searchText.isEmpty else { return true }
        return matches(entry.plugin) || matchesTags(entry.tags)
    }
```

`LibraryView` is the only place that constructs `SkillDetailView`, `PluginDetailView`, `PluginRow`, or uses `LibrarySelection` (verified with grep), so no other call sites change.

(Keep the existing `matches(_ skill: Skill)` and `matches(_ plugin: Plugin)` unchanged.) Update the search prompt to `"Search skills, commands, and projects"`. Add `import AppKit` at the top. Add `static let showAddFolder = Notification.Name("SkillsManager.showAddFolder")` to the `Notification.Name` extension.

- [ ] **Step 4: File menu**

In `App/SkillsManagerApp.swift`, inside `CommandGroup(replacing: .newItem)` after the Install button:

```swift
                Button("Add Folder…") { NotificationCenter.default.post(name: .showAddFolder, object: nil) }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
```

- [ ] **Step 5: Build** (Task 10 adds `SkillDetailView(entry:accountLastSynced:)`, `PluginDetailView(entry:)`, `NoteDetailView`; to build this task alone, add those parameters as stubs now: `let entry: SkillEntry?` / `let accountLastSynced: Date?` on `SkillDetailView`, `let entry: PluginEntry?` on `PluginDetailView`, and a `NoteDetailView` with `let file: NoteFile` whose body is `Text(file.name)`.)

Run: `xcodegen generate && xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -derivedDataPath build build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add App
git commit -m "app: tagged library rows, notes and built-in sections, Add Folder

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Detail pages — Where it works, notes

> Invoke the design skills listed in Global Constraints before editing views.

**Files:**
- Create: `App/WhereItWorksSection.swift`
- Create: `App/NoteDetailView.swift` (replace the Task 9 stub)
- Modify: `App/SkillDetailView.swift`, `App/PluginDetailView.swift`

**Interfaces:**
- Consumes: `WhereItWorks.lines(for:lastSynced:home:)`, `WhereItWorks.lines(for:)`, `WhereLine`, `MarkdownBlocks.parse`, `MarkdownBlock`, `NoteFile`, `ClaudePaths().home`
- Produces: `WhereItWorksSection(lines:)`, `NoteDetailView(file:)`

- [ ] **Step 1: Where-it-works section**

`App/WhereItWorksSection.swift`:

```swift
import AppKit
import SwiftUI
import SkillsManagerCore

struct WhereItWorksSection: View {
    let lines: [WhereLine]

    var body: some View {
        SectionCard(title: "Where it works") {
            ForEach(lines) { line in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(line.label).font(.callout.weight(.medium))
                    Text(detail(line))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(detail(line))
                    Spacer(minLength: Spacing.sm)
                    if let url = line.revealURL {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            .buttonStyle(.link)
                    }
                }
            }
        }
    }

    private func detail(_ line: WhereLine) -> String {
        guard let synced = line.syncedAt else { return line.detail }
        return line.detail + " · last synced " + synced.formatted(.relative(presentation: .named))
    }
}
```

- [ ] **Step 2: Skill detail**

In `App/SkillDetailView.swift` add the stored properties (replacing the Task 9 stubs):

```swift
    let entry: SkillEntry?
    let accountLastSynced: Date?
```

Insert after the "How to use" `SectionCard`:

```swift
                if let entry {
                    WhereItWorksSection(lines: WhereItWorks.lines(
                        for: entry, lastSynced: accountLastSynced, home: ClaudePaths().home))
                }
```

- [ ] **Step 3: Plugin detail**

In `App/PluginDetailView.swift` add `let entry: PluginEntry?` and, directly after the header, insert:

```swift
                if let entry {
                    WhereItWorksSection(lines: WhereItWorks.lines(for: entry))
                }
```

- [ ] **Step 4: Note detail**

`App/NoteDetailView.swift`:

```swift
import AppKit
import SwiftUI
import SkillsManagerCore

struct NoteDetailView: View {
    let file: NoteFile
    @State private var blocks: [MarkdownBlock] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Text(file.name).font(.detailTitle)
                        NotASkillTag()
                    }
                    Text("This is a markdown file, not a Claude skill. Claude won't run it automatically.")
                        .foregroundStyle(.secondary)
                    HStack(spacing: Spacing.md) {
                        Button("Open in Editor") { NSWorkspace.shared.open(file.url) }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
                            .buttonStyle(.link)
                    }
                }
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in view(for: block) }
                }
                .textSelection(.enabled)
            }
            .padding(Spacing.xl)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .navigationTitle(file.name)
        .task(id: file.id) {
            let text = LocalFile.isDownloaded(file.url)
                ? ((try? String(contentsOf: file.url, encoding: .utf8)) ?? "")
                : "This file is stored online only. Download it in Finder to read it here."
            blocks = MarkdownBlocks.parse(text)
        }
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text)).font(level == 1 ? .title2.weight(.semibold) : level == 2 ? .title3.weight(.semibold) : .headline)
        case .paragraph(let text):
            Text(inline(text))
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) { Text("•"); Text(inline(text)) }
        case .numbered(let text):
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) { Text("–"); Text(inline(text)) }
        case .code(let text):
            Text(text).font(.system(.callout, design: .monospaced))
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
```

- [ ] **Step 5: Build**

Run: `xcodegen generate && xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -derivedDataPath build build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add App
git commit -m "app: where-it-works section on detail pages, markdown note viewer

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: First-run project-access note, install, owner checkpoints

> Invoke the design skills listed in Global Constraints before editing views.

**Files:**
- Create: `App/ProjectAccessSheet.swift`
- Modify: `App/LibraryView.swift`

**Interfaces:**
- Consumes: `InventoryStore.needsProjectAccessNote`, `InventoryStore.acknowledgeProjectAccess()`
- Produces: `ProjectAccessSheet(onContinue:onLater:)`

- [ ] **Step 1: Sheet**

`App/ProjectAccessSheet.swift`:

```swift
import SwiftUI

struct ProjectAccessSheet: View {
    let onContinue: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Label("Find skills in your projects", systemImage: "folder.badge.gearshape")
                .font(.title3.weight(.semibold))
            Text("Skills Manager looks for skills inside the folders you use with Claude — in the terminal, the Claude app, and Cowork. It only reads skill and settings files, and never changes anything.")
            Text("If a project is in Documents, Desktop, or iCloud Drive, macOS will ask once for access.")
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Not Now", action: onLater)
                Button("Continue", action: onContinue)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 440)
    }
}
```

- [ ] **Step 2: Present it once per launch until accepted**

In `App/LibraryView.swift` add `@State private var dismissedAccessNote = false` and on the `NavigationSplitView` chain:

```swift
        .sheet(isPresented: Binding(
            get: { store.needsProjectAccessNote && !dismissedAccessNote },
            set: { if !$0 { dismissedAccessNote = true } })) {
            ProjectAccessSheet(
                onContinue: { store.acknowledgeProjectAccess() },
                onLater: { dismissedAccessNote = true })
        }
```

- [ ] **Step 3: Build, install locally, run all tests**

Run:

```bash
(cd SkillsManagerCore && swift test 2>&1 | tail -2)
xcodegen generate && xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -derivedDataPath build build 2>&1 | tail -1
scripts/install-local.sh
```

Expected: all Core tests pass; `** BUILD SUCCEEDED **`; install script reports one copy in /Applications.

- [ ] **Step 4: Commit**

```bash
git add App
git commit -m "app: first-run note before scanning project folders

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Owner checkpoints (GUI — the owner verifies; report results honestly)**

Hand the owner this list:

1. First launch shows "Find skills in your projects"; Continue → projects appear; any macOS folder-access prompt matches the note.
2. Skills list: `Global` tags on personal skills; project skills tagged with project names (Portfolio, Skills Manager…) — no worktree names, no deleted folders.
3. A skill in 3+ projects shows two tags and `+N`; hover shows the tooltip, click opens the list.
4. A skill in both Global and a project: detail page "Where it works" says the project copy is ignored.
5. `henry-portfolio-voice` and `henry-stylist` tagged `Claude account`; Anthropic's are in the collapsed "Built into Claude" group.
6. Cowork plugin (`cowork-plugin-management`) tagged `Cowork`.
7. Add Folder… with a Sean-style `brain/skills` folder → "Your Notes" with `Not a skill` tags; a note opens as formatted text; right-click → Remove from Skills Manager removes it (and nothing on disk).
8. Add Folder… with a random empty folder → "This folder doesn't have Claude skills or markdown files."
9. Searching "Portfolio" filters to items tagged Portfolio.
10. Tags under the summary look right in a 300 pt sidebar (refinement 4) — or ask to move them right-aligned.
11. Coworker setup (desktop-only, OneDrive folder) when possible: nothing triggers a OneDrive download.
