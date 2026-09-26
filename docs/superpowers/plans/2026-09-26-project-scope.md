# Project Scope Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user pick a project (or Cowork, or Everywhere) in the sidebar and see only the skills and plugins usable there, with usage numbers scoped to that project.

**Architecture:** A pure `LibraryScope` value in `SkillsManagerCore` decides membership from the location data every library row already carries, and filters usage events for scoped stats. `InventoryStore` owns the chosen scope (persisted by root path, falling back to Everywhere when the project disappears) and tells `UsageStore` to rebuild its stats for that scope. `LibraryView` filters its sections through the scope, shows a `Showing` popup in the existing bar under search, and adds a footer count with a way back.

**Tech Stack:** Swift 6 / SwiftUI, macOS 14+, Swift Testing, XcodeGen. Spec: `docs/superpowers/specs/2026-09-26-project-scope-design.md`.

## Global Constraints

- Membership is decided ONLY from existing location data (`SkillEntry.locations[].skill.source`, `PluginEntry.locations[].plugin.scope`, `Skill.source`). No new discovery.
- Membership matches by project ROOT (`Canonical` URL path), never by display name (spec §3).
- Membership table (spec §3): everywhere → all; project(root) → rows with a `.personal`/`.shared`-sourced copy, a `.plugin`-sourced copy, an `.account` copy, a user-scope plugin, or a copy/plugin whose root equals the scope root; cowork → rows with a Cowork-scope plugin or an `.account` copy. Unconnected shared skills (`Inventory.sharedSkills`) and notes: shared skills only in everywhere; notes in every scope.
- Scoped usage (spec §4): project → events with `projectRoot?.path == root.path`; cowork → events with `source == .cowork`; everywhere → all events. The Usage card's By project list is never filtered.
- Exact copy: popup label `Showing`; scope names `Everywhere`, the project's display name, `Cowork`; footer `N items not available in <name>` (singular `1 item`) plus link `Show Everywhere`; card caption `Counts from Claude Code and Cowork sessions in <name>` when scoped.
- The scope popup shows even when usage tracking is off; the sort popups still hide then.
- Persisted scope key `libraryScope` in `UserDefaults`: `"everywhere"`, `"cowork"`, or `"project:<canonical root path>"`. Unknown or missing project → `everywhere`, silently.
- Removing a hand-added project that is the current scope resets the scope to `everywhere`.
- Spacing uses only the `Spacing` scale in `App/DesignSystem.swift`. Plain-English copy.
- **UI task (3) MUST invoke the design skills** `apple-design`, `better-ui`, `better-layout`, `better-writing` before editing views.
- Core tests: `cd SkillsManagerCore && swift test`. App build: `xcodegen generate && xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -derivedDataPath build build`. After app changes the owner will see: `scripts/install-local.sh`. If `SkillsManagerCore/Package.resolved` shows as modified after an app build, `git checkout -- SkillsManagerCore/Package.resolved`.
- Commit after every task; last line of every commit message: `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## File structure

| File | Responsibility |
|---|---|
| `SkillsManagerCore/Sources/SkillsManagerCore/LibraryScope.swift` | `LibraryScope` enum, membership for entries/skills/events, persistence string, hidden count |
| `SkillsManagerCore/Tests/SkillsManagerCoreTests/LibraryScopeTests.swift` | membership, event filter, persistence round trip |
| `App/InventoryStore.swift` | owns `scope`, persists it, validates it after each load, resets on project removal, notifies `onScopeChange` |
| `App/UsageStore.swift` | `scope` mirror; stats rebuilt from scoped events |
| `App/SkillsManagerApp.swift` | wires `onScopeChange` |
| `App/LibraryView.swift` | `Showing` popup in the bar, scoped section filtering, footer note |
| `App/UsageSection.swift`, `App/SkillDetailView.swift` | scoped caption |

---

### Task 1: LibraryScope in core

**Files:**
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/LibraryScope.swift`
- Test: `SkillsManagerCore/Tests/SkillsManagerCoreTests/LibraryScopeTests.swift`

**Interfaces:**
- Consumes: `SkillEntry`, `PluginEntry`, `Skill`, `SkillSource`, `PluginScope`, `SkillUsageEvent`, `UsageSource`, `Project`, `Canonical`.
- Produces:
  - `public enum LibraryScope: Sendable, Hashable { case everywhere, project(root: URL), cowork }`
  - `func contains(_ entry: SkillEntry) -> Bool`, `func contains(_ entry: PluginEntry) -> Bool`, `func containsSharedSkill() -> Bool`, `func includes(_ event: SkillUsageEvent) -> Bool`
  - `func label(projects: [Project]) -> String`
  - `var persistenceKey: String`, `static func from(persistenceKey: String?, projects: [Project]) -> LibraryScope`
  - `static func hiddenCount(in library: Library, sharedSkills: [Skill], scope: LibraryScope) -> Int`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import SkillsManagerCore

private func skill(_ folder: String, _ source: SkillSource) -> Skill {
    Skill(folderName: folder, displayName: folder, summary: nil, argumentHint: nil,
          userInvocable: true, modelInvocable: true, whenToUse: nil,
          source: source, directory: URL(fileURLWithPath: "/s/\(folder)/\(UUID().uuidString)"), lastModified: nil)
}
private func entry(_ copies: [Skill]) -> SkillEntry {
    SkillEntry(id: "skill:\(copies[0].folderName)", skill: copies[0],
               locations: copies.map { SkillLocation(skill: $0, tag: .global, isIgnored: false, differsFromPrimary: false) },
               copiesDiffer: false)
}
private func plugin(_ id: String, _ scope: PluginScope) -> Plugin {
    Plugin(pluginID: id, name: String(id.split(separator: "@")[0]), marketplace: "m", summary: nil,
           provenance: nil, version: "1", contentDirectory: URL(fileURLWithPath: "/tmp/\(id)"),
           lastUpdated: nil, isEnabled: true, skills: [], commands: [], scope: scope)
}
private func pentry(_ copies: [Plugin]) -> PluginEntry {
    PluginEntry(id: copies[0].pluginID, plugin: copies[0],
                locations: copies.map { PluginLocation(plugin: $0, tag: .global) })
}
private let a = URL(fileURLWithPath: "/Users/x/A", isDirectory: true)
private let b = URL(fileURLWithPath: "/Users/y/A", isDirectory: true)   // same folder name, different root
private let projects = [Project(root: a, displayName: "A"), Project(root: b, displayName: "A")]

@Test func projectScopeKeepsGlobalAccountAndOwnProjectOnly() {
    let scope = LibraryScope.project(root: a)
    #expect(scope.contains(entry([skill("g", .personal)])))
    #expect(scope.contains(entry([skill("acct", .account(userMade: true))])))
    #expect(scope.contains(entry([skill("pa", .project(root: a, subpath: nil))])))
    #expect(!scope.contains(entry([skill("pb", .project(root: b, subpath: nil))])))   // same name, other root
    #expect(scope.contains(entry([skill("ps", .plugin(pluginID: "p@m"))])))
    #expect(scope.contains(pentry([plugin("u@m", .user)])))
    #expect(scope.contains(pentry([plugin("pa@m", .project(root: a))])))
    #expect(!scope.contains(pentry([plugin("pb@m", .project(root: b))])))
    #expect(!scope.contains(pentry([plugin("cw@m", .cowork)])))
    #expect(!scope.containsSharedSkill())
}

@Test func coworkScopeKeepsCoworkPluginsAndAccountSkills() {
    let scope = LibraryScope.cowork
    #expect(scope.contains(pentry([plugin("cw@m", .cowork)])))
    #expect(!scope.contains(pentry([plugin("u@m", .user)])))
    #expect(scope.contains(entry([skill("acct", .account(userMade: false))])))
    #expect(!scope.contains(entry([skill("g", .personal)])))
    #expect(!scope.containsSharedSkill())
}

@Test func everywhereContainsAll() {
    #expect(LibraryScope.everywhere.contains(entry([skill("pb", .project(root: b, subpath: nil))])))
    #expect(LibraryScope.everywhere.contains(pentry([plugin("cw@m", .cowork)])))
    #expect(LibraryScope.everywhere.containsSharedSkill())
}

@Test func eventFilterFollowsScope() {
    let ea = SkillUsageEvent(skillName: "x", timestamp: Date(), projectRoot: a, sessionID: "1", source: .claudeCode, logFile: "/l")
    let eb = SkillUsageEvent(skillName: "x", timestamp: Date(), projectRoot: b, sessionID: "2", source: .claudeCode, logFile: "/l")
    let ec = SkillUsageEvent(skillName: "x", timestamp: Date(), projectRoot: nil, sessionID: "3", source: .cowork, logFile: "/l")
    #expect(LibraryScope.project(root: a).includes(ea) && !LibraryScope.project(root: a).includes(eb) && !LibraryScope.project(root: a).includes(ec))
    #expect(LibraryScope.cowork.includes(ec) && !LibraryScope.cowork.includes(ea))
    #expect([ea, eb, ec].allSatisfy { LibraryScope.everywhere.includes($0) })
}

@Test func labelsAndPersistence() {
    #expect(LibraryScope.everywhere.label(projects: projects) == "Everywhere")
    #expect(LibraryScope.cowork.label(projects: projects) == "Cowork")
    #expect(LibraryScope.project(root: b).label(projects: projects) == "A")
    #expect(LibraryScope.project(root: URL(fileURLWithPath: "/gone", isDirectory: true)).label(projects: projects) == "gone")
    #expect(LibraryScope.project(root: a).persistenceKey == "project:/Users/x/A")
    #expect(LibraryScope.from(persistenceKey: "project:/Users/x/A", projects: projects) == .project(root: a))
    #expect(LibraryScope.from(persistenceKey: "project:/gone", projects: projects) == .everywhere)   // vanished project
    #expect(LibraryScope.from(persistenceKey: "cowork", projects: projects) == .cowork)
    #expect(LibraryScope.from(persistenceKey: nil, projects: projects) == .everywhere)
    #expect(LibraryScope.from(persistenceKey: "garbage", projects: projects) == .everywhere)
}

@Test func hiddenCountSpansAllRowKinds() {
    var lib = Library()
    lib.skills = [entry([skill("g", .personal)]), entry([skill("pb", .project(root: b, subpath: nil))])]
    lib.builtIn = [entry([skill("bi", .account(userMade: false))])]
    lib.plugins = [pentry([plugin("cw@m", .cowork)]), pentry([plugin("u@m", .user)])]
    let shared = [skill("sh", .shared)]
    #expect(LibraryScope.hiddenCount(in: lib, sharedSkills: shared, scope: .project(root: a)) == 3)   // pb, cw, sh
    #expect(LibraryScope.hiddenCount(in: lib, sharedSkills: shared, scope: .everywhere) == 0)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd SkillsManagerCore && swift test --filter LibraryScopeTests 2>&1 | tail -5`
Expected: compile error, `LibraryScope` not found.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Which part of the library the sidebar shows (spec §3). Membership is
/// decided from the location data each row already carries; matching is by
/// canonical project root, never by display name.
public enum LibraryScope: Sendable, Hashable {
    case everywhere
    case project(root: URL)
    case cowork

    // MARK: Membership

    public func contains(_ entry: SkillEntry) -> Bool {
        switch self {
        case .everywhere: return true
        case .project(let root):
            return entry.locations.contains { includes(source: $0.skill.source, root: root) }
        case .cowork:
            return entry.locations.contains { if case .account = $0.skill.source { return true }; return false }
        }
    }

    public func contains(_ entry: PluginEntry) -> Bool {
        switch self {
        case .everywhere: return true
        case .project(let root):
            return entry.locations.contains {
                switch $0.plugin.scope {
                case .user: true
                case .project(let r): r.path == root.path
                case .cowork: false
                }
            }
        case .cowork:
            return entry.locations.contains { $0.plugin.scope == .cowork }
        }
    }

    /// Unconnected shared skills (~/.agents/skills) aren't usable in any project.
    public func containsSharedSkill() -> Bool { self == .everywhere }

    private func includes(source: SkillSource, root: URL) -> Bool {
        switch source {
        case .personal, .shared, .plugin, .account: true
        case .project(let r, _): r.path == root.path
        }
    }

    // MARK: Usage

    public func includes(_ event: SkillUsageEvent) -> Bool {
        switch self {
        case .everywhere: true
        case .project(let root): event.projectRoot?.path == root.path
        case .cowork: event.source == .cowork
        }
    }

    // MARK: Presentation and persistence

    public func label(projects: [Project]) -> String {
        switch self {
        case .everywhere: "Everywhere"
        case .cowork: "Cowork"
        case .project(let root):
            projects.first { $0.root.path == root.path }?.displayName ?? root.lastPathComponent
        }
    }

    public var persistenceKey: String {
        switch self {
        case .everywhere: "everywhere"
        case .cowork: "cowork"
        case .project(let root): "project:\(root.path)"
        }
    }

    /// A persisted project that the inventory no longer knows falls back to
    /// `.everywhere` (spec §6).
    public static func from(persistenceKey: String?, projects: [Project]) -> LibraryScope {
        guard let key = persistenceKey else { return .everywhere }
        if key == "cowork" { return .cowork }
        if key.hasPrefix("project:") {
            let path = String(key.dropFirst("project:".count))
            if let project = projects.first(where: { $0.root.path == path }) { return .project(root: project.root) }
        }
        return .everywhere
    }

    /// Rows the scope hides, across plugins, skills, built-in skills and
    /// unconnected shared skills (spec §5 footer note).
    public static func hiddenCount(in library: Library, sharedSkills: [Skill], scope: LibraryScope) -> Int {
        let plugins = library.plugins.filter { !scope.contains($0) }.count
        let skills = (library.skills + library.builtIn).filter { !scope.contains($0) }.count
        let shared = scope.containsSharedSkill() ? 0 : sharedSkills.count
        return plugins + skills + shared
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd SkillsManagerCore && swift test 2>&1 | tail -3`
Expected: all pass (147 + 6).

- [ ] **Step 5: Commit**

```bash
git add SkillsManagerCore/Sources/SkillsManagerCore/LibraryScope.swift SkillsManagerCore/Tests/SkillsManagerCoreTests/LibraryScopeTests.swift
git commit -m "feat(scope): LibraryScope membership, event filter, persistence

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Scope ownership in the app stores

**Files:**
- Modify: `App/InventoryStore.swift`
- Modify: `App/UsageStore.swift`
- Modify: `App/SkillsManagerApp.swift`

**Interfaces:**
- Consumes: `LibraryScope` (Task 1), `Inventory.projects`, `UsageStats(events:window:now:)`.
- Produces: `InventoryStore.scope: LibraryScope { get }`, `func setScope(_:)`, `var onScopeChange: (@MainActor (LibraryScope) -> Void)?`; `UsageStore.scope: LibraryScope { get }`, `func setScope(_:)`.

- [ ] **Step 1: InventoryStore owns the scope**

Add to `InventoryStore`:

```swift
    private(set) var scope: LibraryScope = .everywhere
    /// Set by the app so usage stats follow the scope.
    var onScopeChange: (@MainActor (LibraryScope) -> Void)?
    private static let scopeKey = "libraryScope"

    func setScope(_ new: LibraryScope) {
        guard new != scope else { return }
        scope = new
        defaults.set(new.persistenceKey, forKey: Self.scopeKey)
        onScopeChange?(new)
    }

    /// After each load: a persisted or current project scope that the inventory
    /// no longer knows falls back to Everywhere, silently (spec §6).
    private func validateScope(against projects: [Project]) {
        let wanted = defaults.string(forKey: Self.scopeKey) ?? scope.persistenceKey
        let resolved = LibraryScope.from(persistenceKey: wanted, projects: projects)
        if resolved != scope {
            scope = resolved
            onScopeChange?(resolved)
        }
    }
```

In `reload()`'s `MainActor.run` block, after `self.inventory = loaded` and before `self.onReload?()`, add `self.validateScope(against: loaded.projects)`.

In `removeFolder(_:)`, before `reload()`, add:

```swift
        if case .project(let root) = scope, root.path == canonical.path { setScope(.everywhere) }
```

- [ ] **Step 2: UsageStore rebuilds stats for the scope**

Add to `UsageStore`:

```swift
    private(set) var scope: LibraryScope = .everywhere

    func setScope(_ new: LibraryScope) {
        guard new != scope else { return }
        scope = new
        rebuildStats()
    }
```

Change `rebuildStats()` to filter:

```swift
    private func rebuildStats() {
        stats = UsageStats(events: data.events.filter { scope.includes($0) }, window: window)
    }
```

- [ ] **Step 3: Wire in the app**

In `SkillsManagerApp.swift`, inside the `.task { … }` next to `store.onReload = { usage.refresh() }`:

```swift
                    store.onScopeChange = { usage.setScope($0) }
```

- [ ] **Step 4: Build**

Run: `xcodegen generate >/dev/null && xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error:|BUILD" | tail -3`
Expected: `BUILD SUCCEEDED`. Then `git checkout -- SkillsManagerCore/Package.resolved` if modified.

- [ ] **Step 5: Commit**

```bash
git add App/InventoryStore.swift App/UsageStore.swift App/SkillsManagerApp.swift
git commit -m "feat(scope): stores own and persist the library scope; usage stats follow it

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Scope popup, filtering, footer, and card caption

**Files:**
- Modify: `App/LibraryView.swift`
- Modify: `App/UsageSection.swift`, `App/SkillDetailView.swift`

**Interfaces:**
- Consumes: `store.scope`, `store.setScope(_:)`, `store.inventory.projects`, `LibraryScope.contains/containsSharedSkill/label/hiddenCount`, `usage.isEnabled`.

- [ ] **Step 1: Invoke the design skills** listed in Global Constraints.

- [ ] **Step 2: The bar**

In `LibraryView`'s `.safeAreaInset(edge: .top)`, the bar is no longer gated on `usage.isEnabled`; only the sort popups are. Structure:

```swift
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: Spacing.sm) {
                    Text("Showing").font(.caption).foregroundStyle(.secondary)
                    Menu {
                        Picker("Scope", selection: Binding(get: { store.scope }, set: { store.setScope($0) })) {
                            Text("Everywhere").tag(LibraryScope.everywhere)
                            ForEach(store.inventory.projects.sorted {
                                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                            }) { project in
                                Text(project.displayName).tag(LibraryScope.project(root: project.root))
                            }
                            Text("Cowork").tag(LibraryScope.cowork)
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Text(store.scope.label(projects: store.inventory.projects))
                    }
                    .accessibilityLabel("Showing")
                    if usage.isEnabled {
                        Text("Sorted by").font(.caption).foregroundStyle(.secondary)
                        // …the two existing sort/window Menus, unchanged…
                    }
                    Spacer()
                }
                .menuStyle(.button)
                .controlSize(.small)
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.sm)  // the search field already carries its own inset above
                Divider()
            }
            .background(.bar)
        }
```

If four controls do not fit at the 260 pt minimum width, drop the `Sorted by` caption text and keep only the two sort popups next to the scope popup; note it in the report.

- [ ] **Step 3: Filter every section through the scope**

```swift
    private var filteredPlugins: [PluginEntry] {
        let matching = library.plugins.filter { store.scope.contains($0) && matches($0) }
        guard usage.isEnabled else { return matching }
        return UsageSort.sortedPlugins(matching, by: usage.sort, stats: usage.stats)
    }
    private var filteredSkills: [SkillEntry] {
        let matching = library.skills.filter { store.scope.contains($0) && matches($0) }
        guard usage.isEnabled else { return matching }
        return UsageSort.sorted(matching, by: usage.sort, stats: usage.stats)
    }
    private var filteredBuiltIn: [SkillEntry] { library.builtIn.filter { store.scope.contains($0) && matches($0) } }
    private var filteredShared: [Skill] {
        guard store.scope.containsSharedSkill() else { return [] }
        return store.inventory.sharedSkills.filter { matches($0) }
    }
```

Notes stay unfiltered by scope.

- [ ] **Step 4: Footer note**

At the end of the sidebar `List` content (after the Built-in and Needs Attention sections), add:

```swift
            if store.scope != .everywhere, hiddenCount > 0 {
                Section {
                    HStack(spacing: Spacing.xs) {
                        Text(hiddenCount == 1 ? "1 item not available in \(scopeName)"
                                              : "\(hiddenCount) items not available in \(scopeName)")
                        Button("Show Everywhere") { store.setScope(.everywhere) }
                            .buttonStyle(.link)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .selectionDisabled()
                }
            }
```

with

```swift
    private var scopeName: String { store.scope.label(projects: store.inventory.projects) }
    private var hiddenCount: Int {
        LibraryScope.hiddenCount(in: library, sharedSkills: store.inventory.sharedSkills, scope: store.scope)
    }
```

`isEmptyLibrary` keeps its current definition (search-filtered and scope-filtered lists), so an empty scope shows the existing empty state.

- [ ] **Step 5: Card caption**

`UsageSection` gains `var scopeName: String? = nil`. The trailing caption becomes:

```swift
            Text(scopeName.map { "Counts from Claude Code and Cowork sessions in \($0)" }
                 ?? "Counts from Claude Code and Cowork sessions")
```

`SkillDetailView` passes `scopeName: store.scope == .everywhere ? nil : store.scope.label(projects: store.inventory.projects)`; add `@Environment(InventoryStore.self) private var store` to `SkillDetailView` if it does not already have it.

- [ ] **Step 6: Build and install**

Run: `xcodegen generate >/dev/null && scripts/install-local.sh`
Expected: build succeeds. `git checkout -- SkillsManagerCore/Package.resolved` if modified.

- [ ] **Step 7: Commit**

```bash
git add App/LibraryView.swift App/UsageSection.swift App/SkillDetailView.swift
git commit -m "feat(scope): Showing popup, scoped sections, hidden-count footer, scoped card caption

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Owner checkpoints and handoff

- [ ] **Step 1:** `cd SkillsManagerCore && swift test` all green; `scripts/install-local.sh`.
- [ ] **Step 2: Owner checks** (GUI, data-dependent, owner only):
  1. Bar reads `Showing  Everywhere ▾  Sorted by  Name ▾  Last 30 days ▾` and fits at the narrowest sidebar width.
  2. Popup lists Everywhere, projects alphabetically, Cowork; current one checked.
  3. Picking a project hides rows that don't apply; tags stay visible; footer count and `Show Everywhere` link work.
  4. Usage off: scope popup stays, sort popups gone.
  5. Sort by Most used in a project scope reflects that project; the Usage card caption names the project; By project list still lists all projects.
  6. Scope survives relaunch; removing the scoped hand-added project resets to Everywhere.
- [ ] **Step 3:** Finish with `superpowers:finishing-a-development-branch`.
