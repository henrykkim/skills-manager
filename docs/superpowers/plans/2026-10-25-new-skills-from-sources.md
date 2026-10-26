# New Skills From Your Sources Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Once a day and on manual Refresh, find skills that exist in GitHub repos the user already installed from but are not installed locally, surface them in a toolbar "What's new" button with a popover that installs each in one click, and post a macOS notification the first time a skill is seen.

**Architecture:** Core gains `SourceCheck` (pure network diff: lock file + local folders + `GitHubClient` → findings) and `SourceUpdatesRules` (pure scheduling/notification arithmetic with injected dates), both unit-tested with stubs. The app gains `SourceUpdatesModel` (owns persistence, the hourly timer, the single install queue, and notifications), a `SourceUpdatesButton` + `SourceUpdatesPopover` in `LibraryView`'s toolbar, and a `refresh()` entry point on `InventoryStore` so manual Refresh can be told apart from FSEvents reloads.

**Tech Stack:** Swift 6, SwiftUI, Observation, UserNotifications, Swift Testing (`@Test`/`#expect`), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-25-new-skills-from-sources-design.md`

## Global Constraints

- macOS deployment target `14.0`; Swift tools version `6.0`; everything public in Core is `Sendable`.
- Core tests run with `cd SkillsManagerCore && swift test`. The app has no test target; app work is verified by `xcodegen generate && xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug build`.
- GitHub reads go through the existing `GitHubClient` protocol, branch `"HEAD"`, so one tree request per repo and one raw request per genuinely new skill. Never download `SKILL.md` for a folder that is installed or in the lock.
- Daily rule: a check is due when the last *completed* check is not on today's local calendar day. Manual cooldown: a Refresh does not check if a check started less than `600` seconds ago.
- UserDefaults keys, exactly: `sourceCheckLastCompleted` (Date), `sourceCheckLastStarted` (Date), `sourceCheckLastFindings` (Data, JSON), `sourceCheckNotifiedSkills` ([String]), `sourceCheckDismissedUntilNew` (Bool). Skill key format: `"owner/repo#folder"`.
- No ignore list. No new menu item. The `+` button and `InstallSheet` are not touched.
- One installer process at a time across the whole popover.
- Error sentences come from `FailureCopy.sentence(for:marketplace:)` and `InstallSheetModel.sentence(for:)`; don't invent new ones.
- Spacing uses the `Spacing` enum from `App/DesignSystem.swift`.
- Commit messages end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## Review Focus

1. A lock entry whose `source` is not `owner/repo` (empty, three segments, a full URL): it must be skipped, never crash, and never produce a bogus request. Pinned by `SkillLockTests.sourcesSkipsMalformedLabels` (Task 1).
2. A repo that returns 404 while another repo is fine: the good repo's findings still appear and `completed` is true. Pinned by `SourceCheckTests.notFoundRepoIsSkippedOthersContinue` (Task 2).
3. Rate limit mid-run: findings gathered so far are discarded, `completed` is false, and nothing later treats the run as done. Pinned by `SourceCheckTests.rateLimitAbortsRunIncomplete` (Task 2) and `SourceUpdatesRulesTests.incompleteRunDoesNotAdvanceLastCompleted` (Task 3).
4. An app left open across midnight: the hourly tick must trigger exactly one check on the new day. Pinned by `SourceUpdatesRulesTests.dailyDueAcrossMidnightNotWithinSameDay` (Task 3).
5. A skill folder that exists on disk but is missing from the lock (installed by hand): it is installed, not new. Pinned by `SourceCheckTests.folderOnDiskIsNotNewEvenWhenNotInLock` (Task 2).

---

### Task 1: Enumerate sources from the lock file (Core)

**Files:**
- Modify: `SkillsManagerCore/Sources/SkillsManagerCore/SkillLock.swift`
- Test: `SkillsManagerCore/Tests/SkillsManagerCoreTests/SkillLockTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct SkillSource: Sendable, Hashable, Comparable {
      public let owner: String
      public let repo: String
      public var label: String { "\(owner)/\(repo)" }           // "owner/repo"
      public var htmlURL: URL { URL(string: "https://github.com/\(owner)/\(repo)")! }
      public init?(label: String?)                               // nil unless exactly two non-empty "/"-separated segments
  }
  extension SkillLock {
      public var sources: [SkillSource]                           // distinct, sorted
      public var folderNames: Set<String>                         // every key in "skills"
  }
  ```
  `Comparable` orders by owner then repo, case-insensitively.

- [ ] **Step 1: Write the failing tests** in `SkillLockTests.swift`

```swift
@Test func sourcesAreDistinctAndSorted() throws {
    let file = try writeTemp(#"""
    { "skills": {
        "b": { "source": "zed/skills" },
        "a": { "source": "Alpha/tools" },
        "c": { "source": "zed/skills" } } }
    """#)
    defer { try? FileManager.default.removeItem(at: file) }
    let lock = SkillLock.load(file: file)
    #expect(lock.sources.map(\.label) == ["Alpha/tools", "zed/skills"])
    #expect(lock.folderNames == ["a", "b", "c"])
}

@Test func sourcesSkipsMalformedLabels() throws {
    let file = try writeTemp(#"""
    { "skills": {
        "a": { "source": "" },
        "b": { },
        "c": { "source": "one/two/three" },
        "d": { "source": "https://github.com/o/r" },
        "e": { "source": "ok/repo" } } }
    """#)
    defer { try? FileManager.default.removeItem(at: file) }
    #expect(SkillLock.load(file: file).sources.map(\.label) == ["ok/repo"])
    #expect(SkillSource(label: "o/r")?.htmlURL == URL(string: "https://github.com/o/r"))
    #expect(SkillSource(label: "/r") == nil)
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd SkillsManagerCore && swift test --filter SkillLockTests`
Expected: compile error, `sources` and `SkillSource` undefined.

- [ ] **Step 3: Implement `SkillSource` and the two computed properties in `SkillLock.swift`**

- [ ] **Step 4: Run to verify they pass**

Run: `cd SkillsManagerCore && swift test --filter SkillLockTests`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add SkillsManagerCore/Sources/SkillsManagerCore/SkillLock.swift SkillsManagerCore/Tests/SkillsManagerCoreTests/SkillLockTests.swift
git commit -m "feat(core): enumerate skill sources from the lock file"
```

---

### Task 2: `SourceCheck` — diff each source repo against what's installed (Core)

**Files:**
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/SourceUpdates/SourceCheck.swift`
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/SourceUpdates/InstalledSkillFolders.swift`
- Modify: `SkillsManagerCore/Sources/SkillsManagerCore/Install/InstallResolver.swift:86-96` (replace private `installedSkillFolders()` with a call to the new helper)
- Test: `SkillsManagerCore/Tests/SkillsManagerCoreTests/SourceCheckTests.swift`

**Interfaces:**
- Consumes: `SkillLock.sources`, `SkillLock.folderNames` (Task 1); `GitHubClient`, `FrontmatterParser`, `InstallError`.
- Produces:
  ```swift
  public enum InstalledSkillFolders {
      /// Folder names present in personalSkillsDir or sharedSkillsDir (symlinks count, dotfiles skipped).
      public static func names(paths: ClaudePaths) -> Set<String>
  }

  public struct NewSkill: Sendable, Codable, Equatable, Identifiable {
      public let folder: String
      public let name: String          // frontmatter name, else folder
      public let summary: String?      // frontmatter description
      public let path: String          // "skills/teardown/SKILL.md"
      public var id: String { folder }
  }
  public struct SourceFinding: Sendable, Codable, Equatable, Identifiable {
      public let owner: String
      public let repo: String
      public let skills: [NewSkill]    // sorted by folder
      public var id: String { "\(owner)/\(repo)" }
      public var htmlURL: URL
      public func skillURL(_ skill: NewSkill) -> URL   // https://github.com/o/r/tree/HEAD/<dir of path>
      public func key(_ skill: NewSkill) -> String     // "owner/repo#folder"
  }
  public struct SourceCheckResult: Sendable, Equatable {
      public let findings: [SourceFinding]  // only repos with ≥1 new skill, sorted by SkillSource order
      public let completed: Bool            // false after .rateLimited or .network
  }
  public struct SourceCheck: Sendable {
      public init(github: GitHubClient)
      public func run(lock: SkillLock, installedFolders: Set<String>) async -> SourceCheckResult
  }
  ```
  Folder derivation is the same as `InstallResolver.resolveRepo`: parent directory name of `SKILL.md`, or the repo name for a root `SKILL.md`. Branch passed to the client is always `"HEAD"`.

- [ ] **Step 1: Write the failing tests** in `SourceCheckTests.swift`, reusing `StubGitHubClient` and `skillFile` from `InstallResolverTests.swift` (make them file-internal, not private, so both files see them; keep them where they are).

```swift
private func lock(_ pairs: [(folder: String, source: String)]) -> SkillLock {
    SkillLock(entries: Dictionary(uniqueKeysWithValues: pairs.map {
        ($0.folder, SkillLockEntry(sourceLabel: $0.source, sourceURL: nil, installedAt: nil, updatedAt: nil)) }))
}

@Test func reportsOnlyUninstalledSkillsWithFrontmatter() async {
    var gh = StubGitHubClient()
    gh.trees["jakubkrehel/skills"] = ["README.md", "skills/better-ui/SKILL.md", "skills/teardown/SKILL.md", "skills/teardown/ref.md"]
    gh.files["skills/teardown/SKILL.md"] = skillFile("Teardown", "Take an interface apart")
    let result = await SourceCheck(github: gh).run(
        lock: lock([("better-ui", "jakubkrehel/skills")]), installedFolders: ["better-ui"])
    #expect(result.completed)
    #expect(result.findings.count == 1)
    let f = result.findings[0]
    #expect(f.id == "jakubkrehel/skills")
    #expect(f.skills == [NewSkill(folder: "teardown", name: "Teardown", summary: "Take an interface apart", path: "skills/teardown/SKILL.md")])
    #expect(f.key(f.skills[0]) == "jakubkrehel/skills#teardown")
    #expect(f.skillURL(f.skills[0]) == URL(string: "https://github.com/jakubkrehel/skills/tree/HEAD/skills/teardown"))
}

@Test func folderOnDiskIsNotNewEvenWhenNotInLock() async {
    var gh = StubGitHubClient()
    gh.trees["o/r"] = ["skills/a/SKILL.md", "skills/b/SKILL.md"]
    gh.files["skills/b/SKILL.md"] = skillFile("b", "B")
    let result = await SourceCheck(github: gh).run(lock: lock([("a", "o/r")]), installedFolders: ["a", "b"])
    #expect(result.findings.isEmpty)   // b is on disk, so not new; a is in lock
    #expect(result.completed)
}

@Test func reposWithNothingNewProduceNoFinding() async {
    var gh = StubGitHubClient()
    gh.trees["o/r"] = ["skills/a/SKILL.md"]
    let result = await SourceCheck(github: gh).run(lock: lock([("a", "o/r")]), installedFolders: ["a"])
    #expect(result == SourceCheckResult(findings: [], completed: true))
}

@Test func rootSkillRepoUsesRepoNameAsFolder() async {
    var gh = StubGitHubClient()
    gh.trees["o/single"] = ["SKILL.md"]
    let result = await SourceCheck(github: gh).run(lock: lock([("single", "o/single")]), installedFolders: ["single"])
    #expect(result.findings.isEmpty)
}

@Test func malformedFrontmatterStillReportedWithFolderName() async {
    var gh = StubGitHubClient()
    gh.trees["o/r"] = ["skills/a/SKILL.md", "skills/broken/SKILL.md"]
    gh.files["skills/broken/SKILL.md"] = "---\nname: broken\n"
    let result = await SourceCheck(github: gh).run(lock: lock([("a", "o/r")]), installedFolders: ["a"])
    #expect(result.findings[0].skills == [NewSkill(folder: "broken", name: "broken", summary: nil, path: "skills/broken/SKILL.md")])
}

@Test func notFoundRepoIsSkippedOthersContinue() async {
    var gh = StubGitHubClient()
    // "gone/repo" has no tree entry → stub returns []; model that as 404 by making treePaths throw when the key is absent.
    gh.trees["o/r"] = ["skills/a/SKILL.md", "skills/new/SKILL.md"]
    gh.files["skills/new/SKILL.md"] = skillFile("new", "N")
    let result = await SourceCheck(github: gh).run(
        lock: lock([("a", "o/r"), ("x", "gone/repo")]), installedFolders: ["a", "x"])
    #expect(result.completed)
    #expect(result.findings.map(\.id) == ["o/r"])
}

@Test func rateLimitAbortsRunIncomplete() async {
    var gh = StubGitHubClient()
    gh.trees["a/one"] = ["skills/new/SKILL.md"]
    gh.files["skills/new/SKILL.md"] = skillFile("new", "N")
    gh.failure = .rateLimited
    let result = await SourceCheck(github: gh).run(lock: lock([("k", "a/one"), ("j", "b/two")]), installedFolders: ["k", "j"])
    #expect(!result.completed)
    #expect(result.findings.isEmpty)
}

@Test func neverDownloadsInstalledSkills() async {
    var gh = StubGitHubClient()
    gh.trees["o/r"] = ["skills/a/SKILL.md"]           // no files entry: a raw() call would throw .other
    let result = await SourceCheck(github: gh).run(lock: lock([("a", "o/r")]), installedFolders: ["a"])
    #expect(result == SourceCheckResult(findings: [], completed: true))
}
```

Adjust `StubGitHubClient.treePaths` to `throw failure` when set and to `throw InstallError.repoNotFound` when the key is absent (currently returns `[]`); update the one existing resolver test that relied on `[]` (`InstallResolverTests` line ~109 sets an explicit `["README.md"]`, so it is unaffected; the `nobody/nothing` case already expects `.repoNotFound` from `repo()`).

- [ ] **Step 2: Run to verify they fail**

Run: `cd SkillsManagerCore && swift test --filter SourceCheckTests`
Expected: compile error, `SourceCheck` undefined.

- [ ] **Step 3: Implement `InstalledSkillFolders.names(paths:)`** by moving the body of `InstallResolver.installedSkillFolders()` there, and make the resolver call it.

- [ ] **Step 4: Implement `SourceCheck.run`**

Per source in `lock.sources`: `treePaths(owner:repo:branch:"HEAD")` filtered to `SKILL.md` paths → folder names → candidates = not in `installedFolders` and not in `lock.folderNames` → `raw(... branch: "HEAD", path:)` per candidate → `FrontmatterParser.parse`. Catch per repo: `.repoNotFound`, `.noSkills`, `.other` → skip that repo (a failed `raw` for one skill yields a `NewSkill` with `summary: nil`, `name: folder`); `.rateLimited`, `.network` → return `SourceCheckResult(findings: [], completed: false)` immediately.

- [ ] **Step 5: Run the whole suite**

Run: `cd SkillsManagerCore && swift test`
Expected: all PASS (including `InstallResolverTests` after the stub change).

- [ ] **Step 6: Commit**

```bash
git add SkillsManagerCore
git commit -m "feat(core): SourceCheck diffs source repos against installed skills"
```

---

### Task 3: `SourceUpdatesRules` — scheduling, notification and dismissal arithmetic (Core)

**Files:**
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/SourceUpdates/SourceUpdatesRules.swift`
- Test: `SkillsManagerCore/Tests/SkillsManagerCoreTests/SourceUpdatesRulesTests.swift`

**Interfaces:**
- Consumes: `SourceFinding`, `NewSkill`, `SourceCheckResult` (Task 2).
- Produces:
  ```swift
  public enum SourceUpdatesRules {
      public static let manualCooldown: TimeInterval = 600

      /// Daily rule: no completed check on `now`'s calendar day.
      public static func isDailyDue(lastCompleted: Date?, now: Date, calendar: Calendar = .current) -> Bool
      /// Manual rule: no check *started* within the cooldown.
      public static func isManualAllowed(lastStarted: Date?, now: Date) -> Bool

      /// Keys in `findings` not yet in `notified`, in findings order.
      public static func unannouncedKeys(findings: [SourceFinding], notified: Set<String>) -> [String]
      /// Notification copy. nil when nothing to announce.
      public static func notificationText(findings: [SourceFinding], unannounced: [String]) -> (title: String, body: String)?

      /// Whether the toolbar button shows.
      public static func isVisible(findings: [SourceFinding], dismissedUntilNew: Bool) -> Bool
      /// Dismissal survives a check only if it found nothing unannounced.
      public static func dismissedAfterCheck(previouslyDismissed: Bool, unannounced: [String]) -> Bool
      /// `now` when the run completed, else `previous` unchanged.
      public static func nextLastCompleted(previous: Date?, result: SourceCheckResult, now: Date) -> Date?
  }
  ```
  Notification copy (spec §8):
  - one skill: title `"New skill from <owner>"`, body `"<name> — <summary>"` (`"<name>"` alone when summary is nil);
  - several: title `"<n> new skills from your sources"`, body = up to three names joined by `", "`, then `" and <k> more"` when more remain.

- [ ] **Step 1: Write the failing tests**

```swift
private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }()
private func date(_ s: String) -> Date { ISODate.parse(s)! }   // ISODate exists in Core
private func finding(_ owner: String, _ repo: String, _ skills: [(String, String?)]) -> SourceFinding {
    SourceFinding(owner: owner, repo: repo, skills: skills.map { NewSkill(folder: $0.0, name: $0.0, summary: $0.1, path: "skills/\($0.0)/SKILL.md") })
}

@Test func dailyDueAcrossMidnightNotWithinSameDay() {
    let night = date("2026-10-25T03:30:00Z")      // Oct 24, 23:30 New York
    let later = date("2026-10-25T03:59:00Z")      // still Oct 24 NY
    let morning = date("2026-10-25T05:01:00Z")    // Oct 25, 01:01 NY
    #expect(SourceUpdatesRules.isDailyDue(lastCompleted: nil, now: night, calendar: cal))
    #expect(!SourceUpdatesRules.isDailyDue(lastCompleted: night, now: later, calendar: cal))
    #expect(SourceUpdatesRules.isDailyDue(lastCompleted: night, now: morning, calendar: cal))
}

@Test func manualCooldownIsTenMinutesFromStart() {
    let t0 = date("2026-10-25T12:00:00Z")
    #expect(SourceUpdatesRules.isManualAllowed(lastStarted: nil, now: t0))
    #expect(!SourceUpdatesRules.isManualAllowed(lastStarted: t0, now: t0.addingTimeInterval(599)))
    #expect(SourceUpdatesRules.isManualAllowed(lastStarted: t0, now: t0.addingTimeInterval(600)))
}

@Test func incompleteRunDoesNotAdvanceLastCompleted() {
    // Pure rule: the model only records lastCompleted when result.completed; encode that as a helper.
    let t0 = date("2026-10-25T12:00:00Z")
    #expect(SourceUpdatesRules.nextLastCompleted(previous: nil, result: SourceCheckResult(findings: [], completed: false), now: t0) == nil)
    #expect(SourceUpdatesRules.nextLastCompleted(previous: nil, result: SourceCheckResult(findings: [], completed: true), now: t0) == t0)
}

@Test func unannouncedAndNotificationCopy() {
    let f = [finding("jakubkrehel", "skills", [("teardown", "Take it apart")]),
             finding("emil", "skills", [("a", nil), ("b", "B"), ("c", nil), ("d", nil)])]
    let keys = SourceUpdatesRules.unannouncedKeys(findings: f, notified: ["emil/skills#a"])
    #expect(keys == ["jakubkrehel/skills#teardown", "emil/skills#b", "emil/skills#c", "emil/skills#d"])
    let many = SourceUpdatesRules.notificationText(findings: f, unannounced: keys)
    #expect(many?.title == "4 new skills from your sources")
    #expect(many?.body == "teardown, b, c and 1 more")
    let one = SourceUpdatesRules.notificationText(findings: f, unannounced: ["jakubkrehel/skills#teardown"])
    #expect(one?.title == "New skill from jakubkrehel")
    #expect(one?.body == "teardown — Take it apart")
    #expect(SourceUpdatesRules.notificationText(findings: f, unannounced: []) == nil)
}

@Test func dismissalHidesUntilSomethingNew() {
    let f = [finding("o", "r", [("x", nil)])]
    #expect(SourceUpdatesRules.isVisible(findings: f, dismissedUntilNew: false))
    #expect(!SourceUpdatesRules.isVisible(findings: f, dismissedUntilNew: true))
    #expect(!SourceUpdatesRules.isVisible(findings: [], dismissedUntilNew: false))
    #expect(SourceUpdatesRules.dismissedAfterCheck(previouslyDismissed: true, unannounced: []))
    #expect(!SourceUpdatesRules.dismissedAfterCheck(previouslyDismissed: true, unannounced: ["o/r#y"]))
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd SkillsManagerCore && swift test --filter SourceUpdatesRulesTests`
Expected: compile error.

- [ ] **Step 3: Implement `SourceUpdatesRules`**

- [ ] **Step 4: Run to verify they pass**

Run: `cd SkillsManagerCore && swift test --filter SourceUpdatesRulesTests`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add SkillsManagerCore
git commit -m "feat(core): SourceUpdatesRules for daily/cooldown scheduling and notification copy"
```

---

### Task 4: `InventoryStore.refresh()` — manual refresh distinct from FSEvents reload (App)

**Files:**
- Modify: `App/InventoryStore.swift` (add after `reload()`)
- Modify: `App/SkillsManagerApp.swift:41` (Refresh menu item calls `store.refresh()`)

**Interfaces:**
- Produces:
  ```swift
  // InventoryStore
  /// Set by the app; called only for user-initiated Refresh (menu, ⌘R), never for watcher reloads.
  var onManualRefresh: (@MainActor () -> Void)?
  func refresh()   // reload() then onManualRefresh?()
  ```

- [ ] **Step 1: Add `onManualRefresh` and `refresh()` to `InventoryStore`; change the `"Refresh"` command in `SkillsManagerApp.swift` to call `store.refresh()`.**

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug build 2>&1 | grep -E "error:|BUILD"`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add App/InventoryStore.swift App/SkillsManagerApp.swift
git commit -m "feat(app): InventoryStore.refresh() distinguishes manual Refresh from watcher reloads"
```

---

### Task 5: `SourceUpdatesModel` — persistence, scheduling, install queue (App)

**Files:**
- Create: `App/SourceUpdates/SourceUpdatesModel.swift`

**Interfaces:**
- Consumes: `SourceCheck`, `InstalledSkillFolders`, `SourceUpdatesRules`, `SkillLock.load(file:)`, `ClaudePaths.agentsLockFile`, `Installer`, `InstallPreview`, `FailureCopy`.
- Produces:
  ```swift
  @MainActor @Observable
  final class SourceUpdatesModel {
      enum RowState: Equatable { case idle, installing, failed(message: String, log: String) }
      enum Trigger { case launch, timer, manual }

      private(set) var findings: [SourceFinding]          // restored from sourceCheckLastFindings at init
      private(set) var isChecking: Bool
      private(set) var lastCompleted: Date?
      private(set) var lastRunFailed: Bool                 // last run returned completed == false
      private(set) var dismissedUntilNew: Bool
      private(set) var rowStates: [String: RowState]       // keyed by SourceFinding.key(skill)
      private(set) var isInstalling: Bool                  // any row installing → every Install button disabled

      var isVisible: Bool                                  // SourceUpdatesRules.isVisible(...)
      var newSkillCount: Int                               // sum of skills across findings
      /// Called with (title, body) when a completed check has unannounced skills. Set by the app (Task 7).
      var onAnnounce: (@MainActor (String, String) -> Void)?

      init(paths: ClaudePaths, github: GitHubClient, runner: CommandRunner,
           defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = Date.init)

      func start()                       // runs checkIfDue(.launch), starts an hourly timer that calls checkIfDue(.timer)
      func checkIfDue(_ trigger: Trigger) // .launch/.timer use isDailyDue; .manual uses isManualAllowed; no-op while isChecking
      func install(_ skill: NewSkill, from finding: SourceFinding) async
      func installAll(_ finding: SourceFinding) async
      func dismiss()                     // sets dismissedUntilNew = true and persists
  }
  ```
  Behaviour pinned by the spec:
  - A check records `sourceCheckLastStarted = now` when it begins; off the main actor it loads the lock, computes `InstalledSkillFolders.names`, runs `SourceCheck`. On return: `lastCompleted = SourceUpdatesRules.nextLastCompleted(...)`; if `completed`, replace `findings`, compute `unannounced`, update `dismissedUntilNew` via `dismissedAfterCheck`, append `unannounced` to `sourceCheckNotifiedSkills`, call `onAnnounce` with `notificationText` when non-nil. If not completed, keep the old `findings` and set `lastRunFailed = true`.
  - `install` builds `InstallPreview(kind: .skillsRepo, title: finding.id, summary: nil, authorName: finding.owner, authorURL: nil, sourceURL: finding.htmlURL, skills: [], marketplaceNote: nil, isPluginInstalled: false, owner: finding.owner, repo: finding.repo, pluginName: nil, marketplace: nil, marketplaceSource: nil)` and calls `Installer.install(preview, selectedFolders: [skill.folder])` (`installAll` passes every folder). Guarded by `!isInstalling`. On success remove the skill(s) from `findings` (drop the finding when empty) and persist; on failure set `rowStates[key] = .failed(message:log:)`.
  - Persist `findings` as JSON under `sourceCheckLastFindings` whenever they change.
  - The hourly timer is a `Task` loop with `Task.sleep(for: .seconds(3600))`, cancelled in `deinit`.

- [ ] **Step 1: Implement the model as specified.**

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug build 2>&1 | grep -E "error:|BUILD"`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add App/SourceUpdates/SourceUpdatesModel.swift
git commit -m "feat(app): SourceUpdatesModel schedules checks, persists findings, installs one at a time"
```

---

### Task 6: Toolbar button and popover (App)

**Files:**
- Create: `App/SourceUpdates/SourceUpdatesPopover.swift`
- Modify: `App/LibraryView.swift:64-69` (toolbar), `:619-623` (notification name)

**Interfaces:**
- Consumes: `SourceUpdatesModel` (Task 5) via `@Environment(SourceUpdatesModel.self)`.
- Produces:
  ```swift
  struct SourceUpdatesButton: View   // the ToolbarItem content: bell.badge + count capsule; toggles the popover
  struct SourceUpdatesPopover: View  // width 380; sections per finding; rows; footer
  extension Notification.Name { static let showSourceUpdates = Notification.Name("SkillsManager.showSourceUpdates") }
  ```

- [ ] **Step 1: Add the toolbar item** in `LibraryView.toolbar`, **before** the existing Install item, wrapped in `if sourceUpdates.isVisible { ToolbarItem { SourceUpdatesButton(...) } }`. Label `"What's new"`, `systemImage: "bell.badge"`, `.help("New skills from sources you've installed from")`. Count drawn as an overlay capsule (`Text(count).font(.caption2.bold())`, red background, top-trailing) since `.badge` is not honoured on macOS toolbar buttons at the 14.0 target. `.popover(isPresented:)` anchored to the button, `arrowEdge: .bottom`. `.onReceive(... .showSourceUpdates)` sets the presented flag.

- [ ] **Step 2: Build `SourceUpdatesPopover`** per spec §7:
  - Title "New from your sources" (`.headline`).
  - Per finding: header row = `Link(finding.id, destination: finding.htmlURL)` in `.subheadline.weight(.semibold)`, trailing "Install all" (`.buttonStyle(.link)`) when `skills.count >= 2`, disabled while `isInstalling`.
  - Per skill: `VStack(alignment: .leading)` of `Text(skill.name)` and `Text(skill.summary ?? "")` (`.secondary`, `.lineLimit(1)`), trailing: `ProgressView().controlSize(.small)` when `.installing`; else `Button("Install")` `.buttonStyle(.borderedProminent)` `.controlSize(.small)` disabled while `isInstalling`. When `.failed(message, log)`: message in `.red` `.caption` under the summary, a "Try again" `.link` button, and a `DisclosureGroup("Show Details")` with the log in `.monospaced` `.caption2`.
  - Footer `HStack`: caption text — `"Checked \(relative)"` using `RelativeDateTimeFormatter` on `lastCompleted`; `"Not checked yet"` when nil; prefix `"Couldn't reach GitHub · "` when `lastRunFailed`. Trailing `Button("Dismiss")` `.buttonStyle(.link)` → `model.dismiss()` and close.
  - Spacing from `Spacing`; `.padding(Spacing.lg)`; `.frame(width: 380)`.
  - When `findings` becomes empty while presented, set presented = false.

- [ ] **Step 3: Build**

Run: `xcodegen generate && xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug build 2>&1 | grep -E "error:|BUILD"`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add App/SourceUpdates/SourceUpdatesPopover.swift App/LibraryView.swift
git commit -m "feat(app): What's new toolbar button and popover for uninstalled source skills"
```

---

### Task 7: Wire the model into the app; notifications (App)

**Files:**
- Create: `App/SourceUpdates/SourceUpdatesNotifier.swift`
- Modify: `App/SkillsManagerApp.swift` (create model, inject, hook `onManualRefresh`, `onAnnounce`, call `start()`)

**Interfaces:**
- Consumes: `SourceUpdatesModel` (Task 5), `InventoryStore.onManualRefresh` (Task 4), `.showSourceUpdates` (Task 6).
- Produces:
  ```swift
  @MainActor final class SourceUpdatesNotifier: NSObject, UNUserNotificationCenterDelegate {
      static let shared: SourceUpdatesNotifier
      func announce(title: String, body: String)   // requests authorization on first use; skips when NSApp.isActive && NSApp.keyWindow != nil
      // delegate: didReceive → NSApp.activate(ignoringOtherApps: true); NotificationCenter.default.post(name: .showSourceUpdates, object: nil)
  }
  ```

- [ ] **Step 1: Implement `SourceUpdatesNotifier`** with `UNUserNotificationCenter.current()`, `requestAuthorization(options: [.alert, .badge])`, `UNNotificationRequest` with a fresh UUID identifier and no trigger. Set `center.delegate = self` in `init`.

- [ ] **Step 2: In `SkillsManagerApp`**, add `@State private var sourceUpdates = SourceUpdatesModel(paths: ClaudePaths(), github: URLSessionGitHubClient(), runner: ShellCommandRunner())`, `.environment(sourceUpdates)` on `LibraryView`, and in the existing `.task`: `store.onManualRefresh = { sourceUpdates.checkIfDue(.manual) }`, `sourceUpdates.onAnnounce = { SourceUpdatesNotifier.shared.announce(title: $0, body: $1) }`, `sourceUpdates.start()`.

- [ ] **Step 3: Build both schemes**

Run: `xcodegen generate && for s in SkillsManager SkillsManagerHomeDepot; do xcodebuild -project SkillsManager.xcodeproj -scheme $s -configuration Debug build 2>&1 | grep -E "error:|BUILD"; done`
Expected: two `BUILD SUCCEEDED`.

- [ ] **Step 4: Manual verification** (run the Debug app from DerivedData, not install-local yet):
  1. Clear state: `defaults delete com.henrykkim.SkillsManager sourceCheckLastCompleted sourceCheckLastStarted sourceCheckLastFindings sourceCheckNotifiedSkills sourceCheckDismissedUntilNew` (ignore "not found").
  2. Launch. Expect: a check runs; if any source repo has an uninstalled skill, the bell appears with a count and a notification arrives when the app is not frontmost (switch to another app right after launch to see it).
  3. ⌘R twice within a minute: second press must not start a check (`isChecking` stays false; footer time unchanged).
  4. Click Install on one row: spinner, then the row disappears and the skill shows in the library within a few seconds.
  5. Click Dismiss: bell hides. Relaunch same day: bell stays hidden, no check runs.
  6. Toolbar with nothing new is identical to `main`.

- [ ] **Step 5: Commit**

```bash
git add App/SourceUpdates/SourceUpdatesNotifier.swift App/SkillsManagerApp.swift
git commit -m "feat(app): daily source check on launch, hourly rollover, notification on new skills"
```

---

### Task 8: Release notes and local install

**Files:**
- Modify: `release-notes/` (add the next version's notes file following the existing naming), `project.yml` `MARKETING_VERSION` only if the owner asks for a release; otherwise notes only.

- [ ] **Step 1: Add a release-notes entry** describing: "What's new" button, daily check, one-click install from trusted sources, notification.

- [ ] **Step 2: Run `scripts/install-local.sh`** per the app-update rule so the running copy in /Applications is the new build.

- [ ] **Step 3: Commit**

```bash
git add release-notes
git commit -m "docs: release notes for New Skills From Your Sources"
```
