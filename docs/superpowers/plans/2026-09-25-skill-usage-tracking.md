# Skill Usage Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show, for every skill, when it was last used, how often (last 30 days and all time), and in which projects, by reading the skill-invocation records Claude Code and Cowork already write to session logs.

**Architecture:** `SkillsManagerCore` gains a pure pipeline: a line parser that turns one JSONL line into a `SkillUsageEvent` (or nil), an incremental scanner that walks the log roots with per-file byte cursors, a JSON store file, and a stats layer that aggregates events per skill and attributes them to library rows by the same invocation name the cheat sheet already computes. The app wraps that in one `@Observable` `UsageStore` (on/off flag, refresh, clear) that reloads alongside the inventory; the sidebar, detail page, and a new Settings window read only `UsageSummary` values.

**Tech Stack:** Swift 6 / SwiftUI, macOS 14+, Swift Testing (`@Test`, `#expect`), XcodeGen. Spec: `docs/superpowers/specs/2026-09-25-skill-usage-tracking-design.md`.

## Global Constraints

- Read-only on Claude's files. The only file the feature writes is its own store at `~/Library/Application Support/Skills Manager/usage-events.json`.
- From session logs decode **only** `type`, `timestamp`, `cwd`, `sessionId`, and `message.content[].{type,name,input.skill}` via `Decodable` structs that declare nothing else. Never `JSONSerialization` on a log line. The `Skill` tool's `args` is never decoded or stored (spec §5).
- "Used" means an explicit `Skill` tool invocation. Reads of `SKILL.md` are never counted (spec §2 non-goals).
- Timestamps come from the log line's `timestamp`, parsed with the existing `ISODate.parse`, never from file dates (spec §9).
- Paths stored and compared as canonical paths via `Canonical.path(_:)`.
- Every reader is isolated: a missing root is silently empty; a malformed line is skipped and its cursor still advances; a file that cannot be opened is retried next scan from its last cursor; a file that shrank is rescanned from byte 0 with its old events dropped; a store that fails to decode is discarded and rebuilt (spec §9).
- The 30-day window is `now - 30 * 86_400` seconds; an event exactly at the cutoff counts.
- Copy is plain English. Exact strings: `Not used yet`, `Usage in claude.ai isn't tracked.`, sort labels `Name`, `Last used`, `Most used`, window labels `Last 30 days`, `All time`, Settings copy in Task 6.
- Spacing uses only the `Spacing` scale in `App/DesignSystem.swift`.
- **Design session held 2026-09-25**; owner approved the canvas at https://claude.ai/artifact/UeGJ62YwzCpdQ2MEKMu9a4 with no changes. Each UI task carries a "Design decisions" block that overrides its code sketch.
- **UI tasks (6, 7, 8) MUST invoke the design skills** `apple-design`, `make-interfaces-feel-better`, `better-ui`, `better-layout`, `better-typography`, `better-accessibility`, and `better-writing` before editing views.
- Core tests: `cd SkillsManagerCore && swift test`. App build: from repo root, `xcodegen generate && xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -derivedDataPath build build`.
- After any app change the owner will look at: run `scripts/install-local.sh` (one copy in /Applications).
- Commit after every task; last line of every commit message: `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## Deliberate refinements of the spec (flag to owner at handoff)

1. **Each event records its log file path.** Spec §5 lists five fields; a sixth, `logFile`, is needed so a shrunken file's old events can be dropped before it is rescanned (spec §9). It is a path, not transcript content.
2. **Bare-name attribution is by library entry, not by scope precedence.** `Library.build` already merges personal and project copies of one folder name into a single `SkillEntry`, so a bare logged name maps to that entry whichever copy ran. Spec §6's personal → shared → project order collapses to: entry `skill:<name>` first, then an unconnected shared skill named `<name>`. Same result, less code.
3. **Sort lives in the sidebar toolbar as a menu,** next to Install, because the sort should be visible where the list is. The design session may move it.

## File structure

| File | Responsibility |
|---|---|
| `SkillsManagerCore/Sources/SkillsManagerCore/Usage/UsageModels.swift` | `SkillUsageEvent`, `UsageSource`, `UsageFileCursor`, `UsageStoreData` (events + cursors) |
| `SkillsManagerCore/Sources/SkillsManagerCore/Usage/UsageLogParser.swift` | one JSONL line → `SkillUsageEvent?` |
| `SkillsManagerCore/Sources/SkillsManagerCore/Usage/UsageScanner.swift` | walk roots, incremental read by cursor, produce updated `UsageStoreData` |
| `SkillsManagerCore/Sources/SkillsManagerCore/Usage/UsageStoreFile.swift` | load/save `UsageStoreData` as JSON; discard on decode failure |
| `SkillsManagerCore/Sources/SkillsManagerCore/Usage/UsageStats.swift` | `UsageWindow`, `UsageSummary`, `ProjectUsage`, `UsageKey`, aggregation and sorting |
| `SkillsManagerCore/Sources/SkillsManagerCore/ClaudePaths.swift` | add `claudeCodeLogsDir` |
| `App/UsageStore.swift` | `@Observable` on/off flag, refresh, clear; store URL |
| `App/InventoryStore.swift` | trigger usage refresh on reload; watch `~/.claude/projects` |
| `App/SettingsView.swift` | Settings window with the Usage switch |
| `App/SkillsManagerApp.swift` | add `Settings` scene, inject `UsageStore` |
| `App/LibraryView.swift`, `App/LibraryRows.swift` | sort menu, window picker, row hint |
| `App/UsageSection.swift`, `App/SkillDetailView.swift` | Usage section in detail |
| Tests in `SkillsManagerCore/Tests/SkillsManagerCoreTests/Usage*Tests.swift` | one file per core unit |

---

### Task 1: Usage models and store file

**Files:**
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/Usage/UsageModels.swift`
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/Usage/UsageStoreFile.swift`
- Test: `SkillsManagerCore/Tests/SkillsManagerCoreTests/UsageStoreFileTests.swift`

**Interfaces:**
- Produces: `SkillUsageEvent`, `UsageSource`, `UsageFileCursor`, `UsageStoreData`, `UsageStoreFile.load(at:) -> UsageStoreData`, `UsageStoreFile.save(_:to:) throws`, `UsageStoreFile.delete(at:)`.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import SkillsManagerCore

@Test func storeRoundTripsEventsAndCursors() throws {
    let t = try TempTree(); defer { t.remove() }
    let file = t.url("usage-events.json")
    let event = SkillUsageEvent(skillName: "superpowers:brainstorming",
                                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                                projectRoot: URL(fileURLWithPath: "/Users/x/proj", isDirectory: true),
                                sessionID: "s1", source: .claudeCode, logFile: "/logs/a.jsonl")
    let data = UsageStoreData(events: [event],
                              cursors: ["/logs/a.jsonl": UsageFileCursor(byteOffset: 120, fileSize: 120)])
    try UsageStoreFile.save(data, to: file)
    let loaded = UsageStoreFile.load(at: file)
    #expect(loaded == data)
}

@Test func missingStoreIsEmpty() throws {
    let t = try TempTree(); defer { t.remove() }
    #expect(UsageStoreFile.load(at: t.url("nope.json")) == UsageStoreData())
}

@Test func corruptStoreIsDiscarded() throws {
    let t = try TempTree(); defer { t.remove() }
    let file = try t.write("{not json", to: "usage-events.json")
    #expect(UsageStoreFile.load(at: file) == UsageStoreData())
}

@Test func deleteRemovesFile() throws {
    let t = try TempTree(); defer { t.remove() }
    let file = try t.write("{}", to: "usage-events.json")
    UsageStoreFile.delete(at: file)
    #expect(!FileManager.default.fileExists(atPath: file.path))
    UsageStoreFile.delete(at: file)   // second delete is a no-op
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SkillsManagerCore && swift test --filter UsageStoreFileTests 2>&1 | tail -5`
Expected: compile error, `SkillUsageEvent` not found.

- [ ] **Step 3: Write the models**

`UsageModels.swift`:

```swift
import Foundation

public enum UsageSource: String, Codable, Sendable, Hashable {
    case claudeCode, cowork
}

/// One explicit skill invocation, as recorded in a session log (spec §5).
/// Never carries message text or the invocation's arguments.
public struct SkillUsageEvent: Codable, Sendable, Hashable {
    public let skillName: String      // exactly as logged, e.g. "superpowers:brainstorming"
    public let timestamp: Date        // from the log line, never from file dates
    public let projectRoot: URL?      // canonical `cwd`; nil for Cowork sandbox paths
    public let sessionID: String
    public let source: UsageSource
    public let logFile: String        // canonical path of the log that produced it

    public init(skillName: String, timestamp: Date, projectRoot: URL?, sessionID: String,
                source: UsageSource, logFile: String) {
        self.skillName = skillName
        self.timestamp = timestamp
        self.projectRoot = projectRoot
        self.sessionID = sessionID
        self.source = source
        self.logFile = logFile
    }
}

/// Where the last scan stopped in one log file.
public struct UsageFileCursor: Codable, Sendable, Hashable {
    public let byteOffset: Int
    public let fileSize: Int

    public init(byteOffset: Int, fileSize: Int) {
        self.byteOffset = byteOffset
        self.fileSize = fileSize
    }
}

/// Everything the store file holds. Keys of `cursors` are canonical log paths.
public struct UsageStoreData: Codable, Sendable, Hashable {
    public var events: [SkillUsageEvent]
    public var cursors: [String: UsageFileCursor]

    public init(events: [SkillUsageEvent] = [], cursors: [String: UsageFileCursor] = [:]) {
        self.events = events
        self.cursors = cursors
    }
}
```

`UsageStoreFile.swift`:

```swift
import Foundation

/// The one file this feature writes (spec §5). A store that fails to decode
/// is treated as empty so the next scan rebuilds it (spec §9).
public enum UsageStoreFile {
    public static func load(at url: URL) -> UsageStoreData {
        guard let data = try? Data(contentsOf: url) else { return UsageStoreData() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(UsageStoreData.self, from: data)) ?? UsageStoreData()
    }

    public static func save(_ store: UsageStoreData, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(store).write(to: url, options: .atomic)
    }

    public static func delete(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SkillsManagerCore && swift test --filter UsageStoreFileTests 2>&1 | tail -5`
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add SkillsManagerCore/Sources/SkillsManagerCore/Usage SkillsManagerCore/Tests/SkillsManagerCoreTests/UsageStoreFileTests.swift
git commit -m "feat(usage): event models and store file

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Log line parser

**Files:**
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/Usage/UsageLogParser.swift`
- Test: `SkillsManagerCore/Tests/SkillsManagerCoreTests/UsageLogParserTests.swift`

**Interfaces:**
- Consumes: `SkillUsageEvent`, `UsageSource`, `ISODate.parse`, `Canonical.path`.
- Produces: `UsageLogParser.events(inLine: Data, source: UsageSource, logFile: String) -> [SkillUsageEvent]` (one line can hold several `Skill` blocks, so it returns an array; empty for anything else).

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import SkillsManagerCore

private let skillLine = #"""
{"type":"assistant","timestamp":"2026-08-04T03:16:57.855Z","cwd":"/Users/x/proj","sessionId":"d95d","version":"2.1.219","message":{"role":"assistant","content":[{"type":"text","text":"hi"},{"type":"tool_use","id":"toolu_1","name":"Skill","input":{"skill":"superpowers:brainstorming","args":"secret args"}}]}}
"""#

@Test func parsesSkillInvocation() {
    let events = UsageLogParser.events(inLine: Data(skillLine.utf8), source: .claudeCode, logFile: "/l/a.jsonl")
    #expect(events.count == 1)
    let e = events[0]
    #expect(e.skillName == "superpowers:brainstorming")
    #expect(e.timestamp == ISODate.parse("2026-08-04T03:16:57.855Z"))
    #expect(e.projectRoot?.path == "/Users/x/proj")
    #expect(e.sessionID == "d95d")
    #expect(e.source == .claudeCode)
    #expect(e.logFile == "/l/a.jsonl")
}

@Test func ignoresOtherToolsAndUserLines() {
    let bash = #"{"type":"assistant","timestamp":"2026-08-04T03:16:57Z","cwd":"/p","sessionId":"s","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}"#
    let user = #"{"type":"user","timestamp":"2026-08-04T03:16:57Z","cwd":"/p","sessionId":"s","message":{"role":"user","content":"plain string content"}}"#
    let read = #"{"type":"assistant","timestamp":"2026-08-04T03:16:57Z","cwd":"/p","sessionId":"s","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/x/SKILL.md"}}]}}"#
    for line in [bash, user, read] {
        #expect(UsageLogParser.events(inLine: Data(line.utf8), source: .claudeCode, logFile: "/l").isEmpty)
    }
}

@Test func malformedOrIncompleteLinesYieldNothing() {
    let broken = "{not json"
    let noTimestamp = #"{"type":"assistant","cwd":"/p","sessionId":"s","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"x"}}]}}"#
    let noSkill = #"{"type":"assistant","timestamp":"2026-08-04T03:16:57Z","cwd":"/p","sessionId":"s","message":{"content":[{"type":"tool_use","name":"Skill","input":{}}]}}"#
    for line in [broken, noTimestamp, noSkill, ""] {
        #expect(UsageLogParser.events(inLine: Data(line.utf8), source: .claudeCode, logFile: "/l").isEmpty)
    }
}

@Test func coworkLinesDropSandboxProject() {
    let line = #"{"type":"assistant","timestamp":"2026-08-04T03:16:57Z","cwd":"/sessions/loving-feynman","sessionId":"s","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"x"}}]}}"#
    let events = UsageLogParser.events(inLine: Data(line.utf8), source: .cowork, logFile: "/l")
    #expect(events.count == 1)
    #expect(events[0].projectRoot == nil)
    #expect(events[0].source == .cowork)
}

@Test func twoSkillBlocksInOneLineGiveTwoEvents() {
    let line = #"{"type":"assistant","timestamp":"2026-08-04T03:16:57Z","cwd":"/p","sessionId":"s","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"a"}},{"type":"tool_use","name":"Skill","input":{"skill":"b"}}]}}"#
    #expect(UsageLogParser.events(inLine: Data(line.utf8), source: .claudeCode, logFile: "/l").map(\.skillName) == ["a", "b"])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SkillsManagerCore && swift test --filter UsageLogParserTests 2>&1 | tail -5`
Expected: compile error, `UsageLogParser` not found.

- [ ] **Step 3: Write the parser**

```swift
import Foundation

/// Turns one session-log line into skill-invocation events. Decodes only the
/// fields named here (spec §5 privacy); anything else on the line is never read.
public enum UsageLogParser {
    // Declares nothing but what we need. `content` is a string on user lines
    // and an array on assistant lines, so it is decoded leniently.
    private struct Line: Decodable {
        let type: String?
        let timestamp: String?
        let cwd: String?
        let sessionId: String?
        let message: Message?
    }
    private struct Message: Decodable { let content: Blocks? }
    private struct Blocks: Decodable {
        let blocks: [Block]
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            blocks = (try? c.decode([Block].self)) ?? []
        }
    }
    private struct Block: Decodable {
        let type: String?
        let name: String?
        let input: Input?
    }
    private struct Input: Decodable { let skill: String? }

    private static let decoder = JSONDecoder()

    public static func events(inLine data: Data, source: UsageSource, logFile: String) -> [SkillUsageEvent] {
        guard !data.isEmpty, let line = try? decoder.decode(Line.self, from: data) else { return [] }
        guard line.type == "assistant",
              let timestamp = ISODate.parse(line.timestamp),
              let sessionID = line.sessionId,
              let blocks = line.message?.content?.blocks else { return [] }
        let projectRoot: URL? = switch source {
        case .claudeCode: line.cwd.map { URL(fileURLWithPath: Canonical.path($0), isDirectory: true) }
        case .cowork: nil   // sandbox path, not a user folder (spec §3)
        }
        return blocks.compactMap { block in
            guard block.type == "tool_use", block.name == "Skill",
                  let skill = block.input?.skill, !skill.isEmpty else { return nil }
            return SkillUsageEvent(skillName: skill, timestamp: timestamp, projectRoot: projectRoot,
                                   sessionID: sessionID, source: source, logFile: logFile)
        }
    }
}
```

Note: `Canonical.path` on a folder that no longer exists returns the input unchanged (check `Canonical.swift`; if it does not, guard with `FileManager.default.fileExists` and fall back to the raw path). The test uses `/Users/x/proj`, which does not exist, and expects the path back verbatim.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SkillsManagerCore && swift test --filter UsageLogParserTests 2>&1 | tail -5`
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add SkillsManagerCore/Sources/SkillsManagerCore/Usage/UsageLogParser.swift SkillsManagerCore/Tests/SkillsManagerCoreTests/UsageLogParserTests.swift
git commit -m "feat(usage): parse Skill tool invocations from session log lines

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Incremental scanner

**Files:**
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/Usage/UsageScanner.swift`
- Modify: `SkillsManagerCore/Sources/SkillsManagerCore/ClaudePaths.swift` (add `claudeCodeLogsDir`)
- Test: `SkillsManagerCore/Tests/SkillsManagerCoreTests/UsageScannerTests.swift`

**Interfaces:**
- Consumes: `UsageLogParser.events(inLine:source:logFile:)`, `UsageStoreData`, `UsageFileCursor`.
- Produces: `UsageScanner.scan(claudeCodeLogs: URL, coworkSessions: URL, previous: UsageStoreData) -> UsageStoreData` and `ClaudePaths.claudeCodeLogsDir` (`~/.claude/projects`).

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import SkillsManagerCore

private func skillLine(_ name: String, at ts: String = "2026-08-04T03:16:57Z", cwd: String = "/p") -> String {
    #"{"type":"assistant","timestamp":"\#(ts)","cwd":"\#(cwd)","sessionId":"s","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"\#(name)"}}]}}"#
}

@Test func scansClaudeCodeAndCoworkRoots() throws {
    let t = try TempTree(); defer { t.remove() }
    try t.write(skillLine("a") + "\n", to: "logs/-Users-x-p/s1.jsonl")
    try t.write(skillLine("b") + "\n", to: "cowork/acct/org/local_1/.claude/projects/-sessions-x/s2.jsonl")
    try t.write(skillLine("ignored") + "\n", to: "cowork/skills-plugin/acct/org/manifest.jsonl")   // not under .claude/projects
    let store = UsageScanner.scan(claudeCodeLogs: t.url("logs"), coworkSessions: t.url("cowork"), previous: UsageStoreData())
    let byName = Dictionary(grouping: store.events, by: \.skillName)
    #expect(byName["a"]?.first?.source == .claudeCode)
    #expect(byName["b"]?.first?.source == .cowork)
    #expect(byName["ignored"] == nil)
    #expect(store.cursors.count == 2)
}

@Test func missingRootsAreEmpty() throws {
    let t = try TempTree(); defer { t.remove() }
    let store = UsageScanner.scan(claudeCodeLogs: t.url("none"), coworkSessions: t.url("none2"), previous: UsageStoreData())
    #expect(store == UsageStoreData())
}

@Test func secondScanReadsOnlyNewBytes() throws {
    let t = try TempTree(); defer { t.remove() }
    let file = try t.write(skillLine("a") + "\n", to: "logs/x/s1.jsonl")
    let first = UsageScanner.scan(claudeCodeLogs: t.url("logs"), coworkSessions: t.url("none"), previous: UsageStoreData())
    #expect(first.events.count == 1)
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data((skillLine("b") + "\n").utf8))
    try handle.close()
    let second = UsageScanner.scan(claudeCodeLogs: t.url("logs"), coworkSessions: t.url("none"), previous: first)
    #expect(second.events.map(\.skillName) == ["a", "b"])
    // Unchanged file: third scan adds nothing.
    let third = UsageScanner.scan(claudeCodeLogs: t.url("logs"), coworkSessions: t.url("none"), previous: second)
    #expect(third == second)
}

@Test func malformedLineIsSkippedAndCursorAdvances() throws {
    let t = try TempTree(); defer { t.remove() }
    let text = "{broken\n" + skillLine("a") + "\n"
    try t.write(text, to: "logs/x/s1.jsonl")
    let store = UsageScanner.scan(claudeCodeLogs: t.url("logs"), coworkSessions: t.url("none"), previous: UsageStoreData())
    #expect(store.events.map(\.skillName) == ["a"])
    #expect(store.cursors.values.first?.byteOffset == text.utf8.count)
}

@Test func shrunkFileIsRescannedWithoutDuplicates() throws {
    let t = try TempTree(); defer { t.remove() }
    let file = try t.write(skillLine("a") + "\n" + skillLine("b") + "\n", to: "logs/x/s1.jsonl")
    let first = UsageScanner.scan(claudeCodeLogs: t.url("logs"), coworkSessions: t.url("none"), previous: UsageStoreData())
    #expect(first.events.count == 2)
    try (skillLine("c") + "\n").write(to: file, atomically: true, encoding: .utf8)
    let second = UsageScanner.scan(claudeCodeLogs: t.url("logs"), coworkSessions: t.url("none"), previous: first)
    #expect(second.events.map(\.skillName) == ["c"])
}

@Test func partialTrailingLineWaitsForNextScan() throws {
    let t = try TempTree(); defer { t.remove() }
    let full = skillLine("a") + "\n"
    let partial = String(skillLine("b").prefix(40))
    let file = try t.write(full + partial, to: "logs/x/s1.jsonl")
    let first = UsageScanner.scan(claudeCodeLogs: t.url("logs"), coworkSessions: t.url("none"), previous: UsageStoreData())
    #expect(first.events.map(\.skillName) == ["a"])
    #expect(first.cursors.values.first?.byteOffset == full.utf8.count)
    let rest = String(skillLine("b").dropFirst(40)) + "\n"
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(rest.utf8))
    try handle.close()
    let second = UsageScanner.scan(claudeCodeLogs: t.url("logs"), coworkSessions: t.url("none"), previous: first)
    #expect(second.events.map(\.skillName) == ["a", "b"])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SkillsManagerCore && swift test --filter UsageScannerTests 2>&1 | tail -5`
Expected: compile error, `UsageScanner` not found.

- [ ] **Step 3: Add the path and write the scanner**

In `ClaudePaths.swift`, after `personalSkillsDir`:

```swift
    /// Claude Code session transcripts (terminal and desktop Code tab), one
    /// JSONL per session under an escaped-cwd folder.
    public var claudeCodeLogsDir: URL { claudeDir.appending(path: "projects", directoryHint: .isDirectory) }
```

`UsageScanner.swift`:

```swift
import Foundation

/// Walks the session-log roots and reads only what grew since the last scan
/// (spec §4). Pure: takes the previous store, returns the next one.
public enum UsageScanner {
    public static func scan(claudeCodeLogs: URL, coworkSessions: URL, previous: UsageStoreData) -> UsageStoreData {
        var store = previous
        for file in logFiles(under: claudeCodeLogs, requirePathComponent: nil) {
            scanFile(file, source: .claudeCode, into: &store)
        }
        // Cowork keeps the same format inside each session's own `.claude/projects`.
        for file in logFiles(under: coworkSessions, requirePathComponent: "/.claude/projects/") {
            scanFile(file, source: .cowork, into: &store)
        }
        return store
    }

    /// Every `.jsonl` under `root` (hidden folders included: `.claude` is hidden).
    private static func logFiles(under root: URL, requirePathComponent: String?) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsPackageDescendants]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            if let needle = requirePathComponent, !url.path.contains(needle) { continue }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func scanFile(_ url: URL, source: UsageSource, into store: inout UsageStoreData) {
        let key = Canonical.path(url.path)
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) else { return }
        var offset = store.cursors[key]?.byteOffset ?? 0
        if let cursor = store.cursors[key] {
            if size == cursor.fileSize { return }                       // unchanged
            if size < cursor.fileSize {                                  // rotated or rewritten (spec §9)
                store.events.removeAll { $0.logFile == key }
                offset = 0
            }
        }
        // An unopenable file is retried next scan from its last good cursor.
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: UInt64(offset))) != nil,
              let data = try? handle.readToEnd() else { return }

        // Only complete lines count; a partial trailing line is left for next time.
        var consumed = 0
        var lineStart = data.startIndex
        while let newline = data[lineStart...].firstIndex(of: UInt8(ascii: "\n")) {
            let line = data[lineStart..<newline]
            store.events.append(contentsOf: UsageLogParser.events(inLine: Data(line), source: source, logFile: key))
            consumed = newline - data.startIndex + 1
            lineStart = newline + 1
        }
        let newOffset = offset + consumed
        store.cursors[key] = UsageFileCursor(byteOffset: newOffset, fileSize: newOffset == size ? size : newOffset)
    }
}
```

Note on the cursor's `fileSize` for a partial trailing line: recording `newOffset` (not `size`) as `fileSize` makes the next scan see the file as grown once the line completes, so it re-reads from the cursor. In the plain case `newOffset == size`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SkillsManagerCore && swift test --filter UsageScannerTests 2>&1 | tail -5`
Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add SkillsManagerCore/Sources/SkillsManagerCore/Usage/UsageScanner.swift SkillsManagerCore/Sources/SkillsManagerCore/ClaudePaths.swift SkillsManagerCore/Tests/SkillsManagerCoreTests/UsageScannerTests.swift
git commit -m "feat(usage): incremental scanner over Claude Code and Cowork logs

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Stats, attribution, and sorting

**Files:**
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/Usage/UsageStats.swift`
- Test: `SkillsManagerCore/Tests/SkillsManagerCoreTests/UsageStatsTests.swift`

**Interfaces:**
- Consumes: `SkillUsageEvent`, `Skill`, `SkillEntry`, `Invocation.string(for:)`.
- Produces:
  - `enum UsageWindow: CaseIterable { case last30Days, allTime; var label: String }`
  - `struct ProjectUsage { let projectRoot: URL?; let count: Int; let lastUsed: Date }` (nil root = Cowork)
  - `struct UsageSummary { let lastUsed: Date; let countInWindow: Int; let allTimeCount: Int; let byProject: [ProjectUsage] }`
  - `enum UsageKey { static func key(for skill: Skill) -> String }`
  - `struct UsageStats { init(events:, window:, now:); func summary(for skill: Skill) -> UsageSummary?; func summary(forKey:) -> UsageSummary? }`
  - `enum UsageSort { case name, lastUsed, mostUsed; static func sorted(_ entries: [SkillEntry], by:, stats:) -> [SkillEntry] }`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import SkillsManagerCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func day(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }
private func ev(_ name: String, _ ts: Date, root: String? = "/p", source: UsageSource = .claudeCode) -> SkillUsageEvent {
    SkillUsageEvent(skillName: name, timestamp: ts,
                    projectRoot: root.map { URL(fileURLWithPath: $0, isDirectory: true) },
                    sessionID: "s", source: source, logFile: "/l")
}
private func skill(_ folder: String, source: SkillSource = .personal) -> Skill {
    Skill(folderName: folder, displayName: folder.capitalized, summary: nil, argumentHint: nil,
          userInvocable: true, modelInvocable: true, whenToUse: nil, source: source,
          directory: URL(fileURLWithPath: "/skills/\(folder)"), lastModified: nil)
}
private func entry(_ folder: String, source: SkillSource = .personal) -> SkillEntry {
    let s = skill(folder, source: source)
    return SkillEntry(id: "skill:\(folder)", skill: s,
                      locations: [SkillLocation(skill: s, tag: .global, isIgnored: false, differsFromPrimary: false)],
                      copiesDiffer: false)
}

@Test func keysMatchLoggedNames() {
    #expect(UsageKey.key(for: skill("brainstorming", source: .plugin(pluginID: "superpowers@claude-plugins-official"))) == "superpowers:brainstorming")
    #expect(UsageKey.key(for: skill("henry-stylist", source: .account(userMade: true))) == "anthropic-skills:henry-stylist")
    #expect(UsageKey.key(for: skill("apple-design")) == "apple-design")
    #expect(UsageKey.key(for: skill("x", source: .project(root: URL(fileURLWithPath: "/p"), subpath: nil))) == "x")
}

@Test func windowBoundaryIs30Days() {
    let stats = UsageStats(events: [ev("a", day(29)), ev("a", day(31)), ev("a", day(30))], window: .last30Days, now: now)
    let s = stats.summary(forKey: "a")
    #expect(s?.countInWindow == 2)    // 29 and exactly 30 count; 31 does not
    #expect(s?.allTimeCount == 3)
    #expect(s?.lastUsed == day(29))
    #expect(UsageStats(events: [ev("a", day(31))], window: .allTime, now: now).summary(forKey: "a")?.countInWindow == 1)
}

@Test func neverUsedIsNil() {
    #expect(UsageStats(events: [ev("a", day(1))], window: .allTime, now: now).summary(forKey: "zzz") == nil)
}

@Test func byProjectGroupsAndOrdersByCountThenRecency() {
    let events = [ev("a", day(1), root: "/p1"), ev("a", day(2), root: "/p2"), ev("a", day(3), root: "/p2"),
                  ev("a", day(4), root: nil, source: .cowork)]
    let s = UsageStats(events: events, window: .allTime, now: now).summary(forKey: "a")!
    #expect(s.byProject.map { $0.projectRoot?.path } == ["/p2", "/p1", nil])
    #expect(s.byProject.map(\.count) == [2, 1, 1])
    #expect(s.byProject[0].lastUsed == day(2))
}

@Test func sortingPutsNeverUsedLast() {
    let a = entry("a"), b = entry("b"), c = entry("c")
    let stats = UsageStats(events: [ev("a", day(5)), ev("c", day(1)), ev("c", day(2))], window: .allTime, now: now)
    #expect(UsageSort.sorted([a, b, c], by: .lastUsed, stats: stats).map(\.id) == ["skill:c", "skill:a", "skill:b"])
    #expect(UsageSort.sorted([a, b, c], by: .mostUsed, stats: stats).map(\.id) == ["skill:c", "skill:a", "skill:b"])
    #expect(UsageSort.sorted([c, b, a], by: .name, stats: stats).map(\.id) == ["skill:a", "skill:b", "skill:c"])
}

@Test func mostUsedTiesBreakByRecencyThenName() {
    let a = entry("a"), b = entry("b")
    let stats = UsageStats(events: [ev("a", day(5)), ev("b", day(1))], window: .allTime, now: now)
    #expect(UsageSort.sorted([a, b], by: .mostUsed, stats: stats).map(\.id) == ["skill:b", "skill:a"])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd SkillsManagerCore && swift test --filter UsageStatsTests 2>&1 | tail -5`
Expected: compile error, `UsageKey` not found.

- [ ] **Step 3: Write the stats layer**

```swift
import Foundation

public enum UsageWindow: String, CaseIterable, Sendable, Hashable {
    case last30Days, allTime

    public var label: String {
        switch self {
        case .last30Days: "Last 30 days"
        case .allTime: "All time"
        }
    }

    func cutoff(now: Date) -> Date? {
        switch self {
        case .last30Days: now.addingTimeInterval(-30 * 86_400)
        case .allTime: nil
        }
    }
}

/// One project's share of a skill's usage. `projectRoot == nil` is Cowork.
public struct ProjectUsage: Sendable, Hashable {
    public let projectRoot: URL?
    public let count: Int
    public let lastUsed: Date
}

public struct UsageSummary: Sendable, Hashable {
    public let lastUsed: Date
    public let countInWindow: Int
    public let allTimeCount: Int
    /// Most used first, then most recent, then path; Cowork (nil root) sorts by the same rule.
    public let byProject: [ProjectUsage]
}

/// The name a skill appears under in session logs: the typed command minus
/// its slash. Same source of truth as the cheat sheet (spec §6).
public enum UsageKey {
    public static func key(for skill: Skill) -> String {
        String(Invocation.string(for: skill).dropFirst())
    }
}

/// Aggregations over the event list, computed on read (spec §5).
public struct UsageStats: Sendable {
    private let byKey: [String: [SkillUsageEvent]]
    public let window: UsageWindow
    private let cutoff: Date?

    public init(events: [SkillUsageEvent], window: UsageWindow, now: Date = Date()) {
        byKey = Dictionary(grouping: events, by: \.skillName)
        self.window = window
        cutoff = window.cutoff(now: now)
    }

    public var isEmpty: Bool { byKey.isEmpty }

    public func summary(for skill: Skill) -> UsageSummary? { summary(forKey: UsageKey.key(for: skill)) }

    public func summary(forKey key: String) -> UsageSummary? {
        guard let events = byKey[key], let last = events.map(\.timestamp).max() else { return nil }
        let inWindow = cutoff.map { c in events.filter { $0.timestamp >= c }.count } ?? events.count
        let projects = Dictionary(grouping: events, by: { $0.projectRoot?.path }).map { path, evs in
            ProjectUsage(projectRoot: path.map { URL(fileURLWithPath: $0, isDirectory: true) },
                         count: evs.count, lastUsed: evs.map(\.timestamp).max()!)
        }.sorted { a, b in
            if a.count != b.count { return a.count > b.count }
            if a.lastUsed != b.lastUsed { return a.lastUsed > b.lastUsed }
            return (a.projectRoot?.path ?? "") < (b.projectRoot?.path ?? "")
        }
        return UsageSummary(lastUsed: last, countInWindow: inWindow, allTimeCount: events.count, byProject: projects)
    }
}

public enum UsageSort: String, CaseIterable, Sendable, Hashable {
    case name, lastUsed, mostUsed

    public var label: String {
        switch self {
        case .name: "Name"
        case .lastUsed: "Last used"
        case .mostUsed: "Most used"
        }
    }

    /// `.name` keeps the library's own order. Otherwise used skills come first
    /// by the chosen measure; never-used skills keep name order after them (spec §7).
    public static func sorted(_ entries: [SkillEntry], by sort: UsageSort, stats: UsageStats) -> [SkillEntry] {
        let byName: (SkillEntry, SkillEntry) -> Bool = {
            let c = $0.skill.displayName.localizedStandardCompare($1.skill.displayName)
            return c != .orderedSame ? c == .orderedAscending : $0.id < $1.id
        }
        if sort == .name { return entries.sorted(by: byName) }
        let summaries = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, stats.summary(for: $0.skill)) })
        return entries.sorted { a, b in
            switch (summaries[a.id]!, summaries[b.id]!) {
            case (nil, nil): return byName(a, b)
            case (nil, _): return false
            case (_, nil): return true
            case (let sa?, let sb?):
                if sort == .mostUsed, sa.countInWindow != sb.countInWindow { return sa.countInWindow > sb.countInWindow }
                if sa.lastUsed != sb.lastUsed { return sa.lastUsed > sb.lastUsed }
                return byName(a, b)
            }
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd SkillsManagerCore && swift test 2>&1 | tail -5`
Expected: all tests pass (121 existing + 21 new).

- [ ] **Step 5: Commit**

```bash
git add SkillsManagerCore/Sources/SkillsManagerCore/Usage/UsageStats.swift SkillsManagerCore/Tests/SkillsManagerCoreTests/UsageStatsTests.swift
git commit -m "feat(usage): summaries, attribution keys, and usage sort

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: App-side UsageStore wired to reload

**Files:**
- Create: `App/UsageStore.swift`
- Modify: `App/InventoryStore.swift` (call usage refresh after each load; watch the logs dir)
- Modify: `App/SkillsManagerApp.swift` (create and inject `UsageStore`)

**Interfaces:**
- Consumes: `UsageScanner.scan`, `UsageStoreFile`, `UsageStats`, `UsageWindow`, `UsageSort`, `ClaudePaths.claudeCodeLogsDir`, `ClaudePaths.coworkSessionsDir`.
- Produces: `UsageStore` (`@MainActor @Observable`) with `isEnabled: Bool { get set }`, `window: UsageWindow`, `sort: UsageSort`, `stats: UsageStats`, `func refresh()`.

- [ ] **Step 1: Write UsageStore**

```swift
import Foundation
import Observation
import SkillsManagerCore

/// Owns the usage feature's one file and its on/off switch (spec §8).
/// Everything shown in the UI comes from `stats`.
@MainActor
@Observable
final class UsageStore {
    private(set) var stats = UsageStats(events: [], window: .last30Days)
    var window: UsageWindow {
        didSet { defaults.set(window.rawValue, forKey: Self.windowKey); rebuildStats() }
    }
    var sort: UsageSort {
        didSet { defaults.set(sort.rawValue, forKey: Self.sortKey) }
    }
    /// On by default. Off deletes the store and hides every usage surface.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled { refresh() } else { clear() }
        }
    }

    private var data = UsageStoreData()
    private let paths: ClaudePaths
    private let defaults = UserDefaults.standard
    private var refreshGeneration = 0

    private static let enabledKey = "usageTrackingEnabled"
    private static let windowKey = "usageWindow"
    private static let sortKey = "usageSort"

    static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Skills Manager/usage-events.json")
    }

    init(paths: ClaudePaths = ClaudePaths()) {
        self.paths = paths
        let d = UserDefaults.standard
        isEnabled = d.object(forKey: Self.enabledKey) == nil ? true : d.bool(forKey: Self.enabledKey)
        window = UsageWindow(rawValue: d.string(forKey: Self.windowKey) ?? "") ?? .last30Days
        sort = UsageSort(rawValue: d.string(forKey: Self.sortKey) ?? "") ?? .name
    }

    /// Incremental scan off the main thread; a stale scan never overwrites a newer one.
    func refresh() {
        guard isEnabled else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        let paths = self.paths
        let url = Self.storeURL
        Task.detached(priority: .utility) {
            let previous = UsageStoreFile.load(at: url)
            let next = UsageScanner.scan(claudeCodeLogs: paths.claudeCodeLogsDir,
                                         coworkSessions: paths.coworkSessionsDir, previous: previous)
            if next != previous { try? UsageStoreFile.save(next, to: url) }
            await MainActor.run { [weak self] in
                guard let self, generation == self.refreshGeneration, self.isEnabled else { return }
                self.data = next
                self.rebuildStats()
            }
        }
    }

    private func clear() {
        refreshGeneration += 1
        UsageStoreFile.delete(at: Self.storeURL)
        data = UsageStoreData()
        rebuildStats()
    }

    private func rebuildStats() {
        stats = UsageStats(events: data.events, window: window)
    }
}
```

- [ ] **Step 2: Wire into InventoryStore and the app**

In `InventoryStore.swift`:

```swift
    /// Set by the app so usage rescans ride along with every inventory reload.
    var onReload: (@MainActor () -> Void)?
```

In `reload()`, inside the `MainActor.run` closure after `self.watcher?.setTargets(...)`, add:

```swift
                self.onReload?()
```

In `start()`, change the `sourcesWatcher` targets to include the logs folder:

```swift
            targets: [paths.claudeJSON, paths.codeSessionsDir, paths.coworkSessionsDir, paths.claudeCodeLogsDir],
```

In `SkillsManagerApp.swift`:

```swift
    @State private var store = InventoryStore()
    @State private var usage = UsageStore()
    ...
            LibraryView()
                .environment(store)
                .environment(usage)
                .task {
                    store.onReload = { usage.refresh() }
                    store.start()
                }
```

- [ ] **Step 3: Build**

Run: `xcodegen generate >/dev/null && xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error:|BUILD" | tail -5`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Smoke check the store file**

Run: `xcodegen generate >/dev/null && scripts/install-local.sh && open "/Applications/Skills Manager.app" && sleep 5 && python3 -c "import json;d=json.load(open('$HOME/Library/Application Support/Skills Manager/usage-events.json'));print(len(d['events']),'events',len(d['cursors']),'files')"`
Expected: a non-zero event count and roughly the number of session files on this Mac (about 150). Confirm no line in the file contains `"args"`: `grep -c '"args"' "$HOME/Library/Application Support/Skills Manager/usage-events.json"` prints `0`.

- [ ] **Step 5: Commit**

```bash
git add App/UsageStore.swift App/InventoryStore.swift App/SkillsManagerApp.swift
git commit -m "feat(usage): app store that scans on reload and persists its own file

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## STOP: owner design session before Task 6

Tell the owner: "Core and data are done and the store file is populating. You asked for a separate design session for how usage looks before the UI is built. Ready when you are." Wait for the answer. If the session changes the surfaces, update Tasks 6–8 before running them.

---

### Task 6: Settings window with the Usage switch

**Design decisions (owner-approved 2026-09-25, override the code sketch below where they differ):**
The Settings › Usage card, top to bottom: (1) the switch `Show when and how often skills are used`; (2) the disclosure copy exactly: `Reads skill invocation records from Claude Code and Cowork session logs. Message text is never read or stored. Turning this off deletes the usage data Skills Manager has collected.`; (3) a divider, then a four-row facts list rendered with `LabeledContent`: `Reads` → `Claude Code sessions · Cowork sessions`; `Not covered` → `claude.ai in the browser`; `Last scanned` → relative time of the last completed scan (`Never` before the first); `Collected` → `<N> invocations across <M> sessions` (M = distinct session ids; singular forms when 1); (4) two trailing buttons right-aligned: `Show Usage File in Finder` (`NSWorkspace.shared.activateFileViewerSelecting([UsageStore.storeURL])`, disabled when the file does not exist) and `Rescan Now` (calls `usage.refresh()`, disabled while a scan is running). When the switch is off, rows 3 and 4 are hidden. To support this, `UsageStore` gains `private(set) var lastScanned: Date?` (set on the MainActor when a scan completes), `private(set) var isScanning: Bool`, `var eventCount: Int { data.events.count }`, and `var sessionCount: Int { Set(data.events.map(\.sessionID)).count }`; `clear()` resets `lastScanned` to nil. Window width 480.

**Files:**
- Create: `App/SettingsView.swift`
- Modify: `App/SkillsManagerApp.swift` (add `Settings` scene)

**Interfaces:**
- Consumes: `UsageStore.isEnabled`.

- [ ] **Step 1: Invoke the design skills** listed in Global Constraints.

- [ ] **Step 2: Write SettingsView**

```swift
import SwiftUI

struct SettingsView: View {
    @Environment(UsageStore.self) private var usage

    var body: some View {
        @Bindable var usage = usage
        Form {
            Section("Usage") {
                Toggle("Show when and how often skills are used", isOn: $usage.isEnabled)
                Text("Skills Manager reads skill invocation records from Claude Code and Cowork session logs to show when and how often each skill is used. Message text is never stored. Turning this off deletes the usage data it has collected.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding(.bottom, Spacing.sm)
    }
}
```

In `SkillsManagerApp.swift`, after the `WindowGroup { ... }.commands { ... }` scene:

```swift
        Settings {
            SettingsView().environment(usage)
        }
```

- [ ] **Step 3: Build and install**

Run: `xcodegen generate >/dev/null && scripts/install-local.sh`
Expected: build succeeds; ⌘, opens Settings with the switch on.

- [ ] **Step 4: Verify the switch clears the file**

Turn the switch off, then: `ls "$HOME/Library/Application Support/Skills Manager/"` shows no `usage-events.json`. Turn it on; within a few seconds the file is back.

- [ ] **Step 5: Commit**

```bash
git add App/SettingsView.swift App/SkillsManagerApp.swift
git commit -m "feat(usage): Settings window with usage tracking switch

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Sort menu, window picker, and row hint

**Design decisions (owner-approved 2026-09-25, override the code sketch below where they differ):**
The Sort toolbar button uses `arrow.up.arrow.down` and sits before Install. Its menu has two inline pickers with section labels `Sort by` (Name, Last used, Most used) and `Count` (Last 30 days, All time). The row hint is right-aligned on the tag line in `.metadata` font, tertiary color, tabular digits, and reads `Used today`, `Used yesterday`, `Used N days ago` up to 21 days, then `Used <abbreviated date>` (e.g. `Used Aug 12`). Never-used skills read `Not used yet` in the same style. In the two usage sorts, a thin divider row separates the used group from the never-used group (only when both groups are non-empty). Put the hint-text rule in a small pure helper `UsageHint.text(lastUsed: Date?, now: Date) -> String` in the app target so the format lives in one place.

**Files:**
- Modify: `App/LibraryView.swift` (toolbar menu; apply sort to `filteredSkills`)
- Modify: `App/LibraryRows.swift` (`SkillEntryRow` hint)

**Interfaces:**
- Consumes: `UsageStore.sort`, `.window`, `.stats`, `.isEnabled`; `UsageSort.sorted(_:by:stats:)`; `UsageStats.summary(for:)`.

- [ ] **Step 1: Invoke the design skills** listed in Global Constraints.

- [ ] **Step 2: Add the toolbar menu**

In `LibraryView`, add `@Environment(UsageStore.self) private var usage` and, inside `.toolbar { }` before the Install item:

```swift
            if usage.isEnabled {
                ToolbarItem {
                    Menu {
                        Picker("Sort by", selection: Binding(get: { usage.sort }, set: { usage.sort = $0 })) {
                            ForEach(UsageSort.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.inline)
                        Divider()
                        Picker("Count", selection: Binding(get: { usage.window }, set: { usage.window = $0 })) {
                            ForEach(UsageWindow.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                    .help("Sort skills by name or by how you use them")
                }
            }
```

Change `filteredSkills`:

```swift
    private var filteredSkills: [SkillEntry] {
        let matching = library.skills.filter { matches($0) }
        guard usage.isEnabled else { return matching }
        return UsageSort.sorted(matching, by: usage.sort, stats: usage.stats)
    }
```

- [ ] **Step 3: Add the row hint**

`SkillEntryRow` gains an optional summary. In `LibraryRows.swift`:

```swift
struct SkillEntryRow: View {
    let entry: SkillEntry
    var usage: UsageSummary? = nil
```

In the `HStack` that holds `LocationTags`, after the `Copies differ` block:

```swift
                if let usage {
                    Spacer(minLength: 0)
                    Text("Used \(usage.lastUsed.formatted(.relative(presentation: .named)))")
                        .font(.metadata)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                        .help("Last used \(usage.lastUsed.formatted(date: .abbreviated, time: .shortened)) · \(usage.countInWindow) times in the selected period")
                }
```

Import `SkillsManagerCore` is already present. In `LibraryView`'s Skills section:

```swift
                        SkillEntryRow(entry: entry, usage: usage.isEnabled ? usage.stats.summary(for: entry.skill) : nil)
```

- [ ] **Step 4: Build and install**

Run: `xcodegen generate >/dev/null && scripts/install-local.sh`
Expected: build succeeds; the Sort menu appears; choosing Last used reorders skills with a used one at the top and never-used skills at the bottom; the rows of used skills show `Used 2 days ago` style text.

- [ ] **Step 5: Commit**

```bash
git add App/LibraryView.swift App/LibraryRows.swift
git commit -m "feat(usage): sort by last used or most used; last-used hint on rows

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Usage section in skill detail

**Design decisions (owner-approved 2026-09-25, override the code sketch below where they differ):**
The Usage card header row shows the title `Usage` and a right-aligned tertiary caption `Counts from Claude Code and Cowork sessions`. Below: a three-column grid of stat tiles (white background, hairline border, 8 pt radius): `Last used` with the relative day as the big value and the time as the caption; the window label (`Last 30 days`) with `N times` and a rate caption (`about N a week` when ≥ 2 per week in the window, `once a week`/`a few times a month`/`once` otherwise, plain English, no decimals); `All time` with `N times` and `since <abbreviated date of first event>`. Then a divider, a `BY PROJECT` label, and one row per project: name (140 pt), a proportional bar (6 pt tall, 3 pt radius, filled width = count / max count, accent color; Cowork row uses gray fill and gray name), the count (tabular), and the last-used date right-aligned (92 pt). Never used: the card body is `Not used yet` plus one line `Counts start the first time you run <invocation> in Claude Code or Cowork.` with the invocation in monospace. Account skills append `Usage in claude.ai isn’t tracked. These counts cover Claude Code and Cowork only.` `UsageSummary` gains nothing; compute the first-event date from `byProject` last-used values is NOT sufficient, so add `public let firstUsed: Date` to `UsageSummary` in core (min timestamp) with a test, as the first step of this task.

**Files:**
- Create: `App/UsageSection.swift`
- Modify: `App/SkillDetailView.swift`
- Modify: `App/LibraryView.swift` (pass project names)

**Interfaces:**
- Consumes: `UsageSummary`, `ProjectUsage`, `UsageWindow.label`, `Inventory.projects` (`Project.root`, `.displayName`).

- [ ] **Step 1: Invoke the design skills** listed in Global Constraints.

- [ ] **Step 2: Write UsageSection**

```swift
import SwiftUI
import SkillsManagerCore

/// The Usage card on a skill's detail page (spec §7). `summary == nil` means never used.
struct UsageSection: View {
    let summary: UsageSummary?
    let window: UsageWindow
    let isAccountSkill: Bool
    /// Canonical project root path → display name, from the inventory.
    let projectNames: [String: String]

    var body: some View {
        SectionCard(title: "Usage") {
            if let summary {
                LabeledContent("Last used") {
                    Text(summary.lastUsed.formatted(date: .abbreviated, time: .shortened)).font(.metadata)
                }
                LabeledContent(window.label) {
                    Text("\(summary.countInWindow) \(summary.countInWindow == 1 ? "time" : "times")").font(.metadata)
                }
                if window != .allTime {
                    LabeledContent("All time") {
                        Text("\(summary.allTimeCount) \(summary.allTimeCount == 1 ? "time" : "times")").font(.metadata)
                    }
                }
                Divider()
                Text("By project").font(.cardLabel).foregroundStyle(.secondary)
                ForEach(summary.byProject, id: \.self) { p in
                    LabeledContent(name(for: p)) {
                        Text("\(p.count) · \(p.lastUsed.formatted(.relative(presentation: .named)))")
                            .font(.metadata)
                            .help(p.lastUsed.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            } else {
                Text("Not used yet").foregroundStyle(.secondary)
            }
            if isAccountSkill {
                Text("Usage in claude.ai isn't tracked.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func name(for p: ProjectUsage) -> String {
        guard let root = p.projectRoot else { return "Cowork" }
        return projectNames[root.path] ?? root.lastPathComponent
    }
}
```

- [ ] **Step 3: Show it in SkillDetailView**

Add to `SkillDetailView`:

```swift
    @Environment(UsageStore.self) private var usage
    var projectNames: [String: String] = [:]
```

After the `WhereItWorksSection` block (before "When to use"):

```swift
                if usage.isEnabled {
                    UsageSection(summary: usage.stats.summary(for: skill), window: usage.window,
                                 isAccountSkill: { if case .account = skill.source { return true }; return false }(),
                                 projectNames: projectNames)
                }
```

In `LibraryView.detailView`, both `SkillDetailView(...)` calls gain `projectNames: projectNames`, with:

```swift
    private var projectNames: [String: String] {
        Dictionary(store.inventory.projects.map { ($0.root.path, $0.displayName) }, uniquingKeysWith: { a, _ in a })
    }
```

- [ ] **Step 4: Build and install**

Run: `xcodegen generate >/dev/null && scripts/install-local.sh`
Expected: build succeeds. A used skill's detail shows the Usage card with a By project list; a never-used skill shows `Not used yet`; an account skill adds the claude.ai line.

- [ ] **Step 5: Commit**

```bash
git add App/UsageSection.swift App/SkillDetailView.swift App/LibraryView.swift
git commit -m "feat(usage): Usage section with per-project breakdown in skill detail

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: Owner checkpoints and handoff

**Files:** none (verification only).

- [ ] **Step 1: Full test run**

Run: `cd SkillsManagerCore && swift test 2>&1 | tail -3`
Expected: all pass, zero failures.

- [ ] **Step 2: Install the final build**

Run: `scripts/install-local.sh`

- [ ] **Step 3: Owner visual checkpoints** (cannot be automated on this Mac; ask the owner to confirm each)

1. Sort menu: Name, Last used, Most used; Last 30 days / All time; never-used skills always at the bottom in the two usage sorts.
2. Row hint reads naturally and does not crowd the tags at 260 pt sidebar width.
3. Detail Usage card: counts, By project names match the location tags' project names, Cowork row only when present.
4. `Not used yet` on an unused skill; `Usage in claude.ai isn't tracked.` on an account skill.
5. Settings: switch off hides the menu, hints, and card, and deletes the file; on restores them.
6. Run a skill in a terminal session, wait about ten seconds, and confirm the count ticks up without pressing ⌘R.

- [ ] **Step 4: Report the three spec refinements** listed at the top of this plan, and the open item that Cowork coverage is unverified until a Cowork-heavy user runs the build.

- [ ] **Step 5: Finish the branch** with `superpowers:finishing-a-development-branch`.
