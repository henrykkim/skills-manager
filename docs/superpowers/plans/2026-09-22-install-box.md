# Install Box Implementation Plan (Plan 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A toolbar "Install" button opens a sheet where the owner pastes a GitHub link, a skills.sh link or an install command, sees a verified preview, and installs into Claude Code with one click.

**Architecture:** Recognition (deterministic parser, then an optional on-device model guess) produces an `InstallIntent`; `InstallResolver` verifies it against GitHub / local plugin files and builds an `InstallPreview`; `Installer` turns the preview plus the user's selection into `npx skills add` / `claude plugin` commands run by a `CommandRunner`. All of that lives in `SkillsManagerCore` behind protocols with fakes. The app adds `InstallSheetModel` (orchestration + cancellation), `FoundationModelsGuesser` (macOS 26 gated), and the `InstallSheet` UI.

**Tech Stack:** Swift 6 / SwiftUI, macOS 14+ (FoundationModels weak-linked, `#available(macOS 26, *)`), Swift Testing, XcodeGen. Spec: `docs/superpowers/specs/2026-09-22-install-box-design.md`.

## Global Constraints

- The app never writes into skill/plugin folders or Claude Code JSON files itself. All installs go through `npx -y skills add …` or `claude plugin …` via `CommandRunner`.
- No command runs without a click on Install. Model output never triggers a command. Every intent is verified by `InstallResolver` before a preview appears.
- Target is Claude Code only: skills use `-a claude-code`; plugins use user scope.
- All copy is sentence case, plain English, for someone who has never opened a terminal. Failure sentences are exactly the ones in spec §7; diagnosis sentences exactly §4.3.
- Core readers/network helpers never throw for "normal absence"; they throw typed `InstallError`s that map to spec sentences.
- Core tests never touch the network or spawn real processes: `StubGitHubClient` and `FakeCommandRunner` only.
- Spacing only from `Spacing`; motion critically damped (`.smooth`/`.snappy`) and reduced-motion aware; reuse `KindBadge`, `SourceLink`, `InvocationChip`, `SectionCard`.
- **UI tasks (5 and 6) MUST invoke** `apple-design`, `make-interfaces-feel-better`, `emil-design-eng`, `better-ui`, `better-layout`, `better-typography`, `better-accessibility`, `better-writing` before editing views.
- Core tests: `cd SkillsManagerCore && swift test`. App build: `xcodegen generate && xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -derivedDataPath build build 2>&1 | tail -3`.
- Every commit message ends with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

---

## File map

| File | Change |
|---|---|
| `SkillsManagerCore/Sources/SkillsManagerCore/Install/InstallIntent.swift` | **new** — `InstallIntent`, `InstallError`, `InstallIntentParser` |
| `SkillsManagerCore/Sources/SkillsManagerCore/Install/GitHubClient.swift` | **new** — protocol, `URLSessionGitHubClient` |
| `SkillsManagerCore/Sources/SkillsManagerCore/Install/InstallPreview.swift` | **new** — `InstallPreview`, `PreviewSkill` |
| `SkillsManagerCore/Sources/SkillsManagerCore/Install/InstallResolver.swift` | **new** |
| `SkillsManagerCore/Sources/SkillsManagerCore/Install/CommandRunner.swift` | **new** — protocol, `CommandResult`, `ShellCommandRunner` |
| `SkillsManagerCore/Sources/SkillsManagerCore/Install/Installer.swift` | **new** — `Installer`, `InstallOutcome`, `IntentGuesser`, `NoopGuesser` |
| `SkillsManagerCore/Sources/SkillsManagerCore/Version.swift` | `0.3.0` |
| `SkillsManagerCore/Tests/SkillsManagerCoreTests/InstallIntentParserTests.swift` | **new** |
| `SkillsManagerCore/Tests/SkillsManagerCoreTests/InstallResolverTests.swift` | **new** (+ `StubGitHubClient`) |
| `SkillsManagerCore/Tests/SkillsManagerCoreTests/InstallerTests.swift` | **new** (+ `FakeCommandRunner`) |
| `SkillsManagerCore/Tests/SkillsManagerCoreTests/SmokeTests.swift` | version bump |
| `App/Install/InstallSheetModel.swift` | **new** — `@Observable` orchestration |
| `App/Install/FoundationModelsGuesser.swift` | **new** — macOS 26 gated |
| `App/Install/InstallSheet.swift` | **new** — the sheet UI |
| `App/LibraryView.swift` | toolbar Install button, sheet presentation, drop target |
| `App/SkillsManagerApp.swift` | File ▸ Install… ⌘N |
| `project.yml` | weak-link FoundationModels |
| `README.md` | Install section |

---

### Task 1: `InstallIntent` and the deterministic parser

**Files:**
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/Install/InstallIntent.swift`
- Create: `SkillsManagerCore/Tests/SkillsManagerCoreTests/InstallIntentParserTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  ```swift
  public enum InstallIntent: Sendable, Equatable {
      case skillsRepo(owner: String, repo: String, subpath: String?, onlySkills: [String]?)
      case plugin(name: String, marketplace: String, marketplaceSource: String?)
      case unrecognized(diagnosis: String)
  }
  public enum InstallError: Error, Sendable, Equatable { case repoNotFound, noSkills, rateLimited, network(String), other(String) }
  public enum InstallIntentParser { public static func parse(_ text: String) -> InstallIntent }
  public enum Diagnosis { public static let packageManager(_:), nonGitHubURL, generic }  // exact sentences
  ```

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import SkillsManagerCore

@Test func parsesSlashPluginPair() {
    let text = "/plugin marketplace add jakubkrehel/skills\n/plugin install interfaces@interfaces"
    #expect(InstallIntentParser.parse(text) ==
        .plugin(name: "interfaces", marketplace: "interfaces", marketplaceSource: "jakubkrehel/skills"))
}

@Test func parsesSlashPluginSingle() {
    #expect(InstallIntentParser.parse("/plugin install superpowers@claude-plugins-official") ==
        .plugin(name: "superpowers", marketplace: "claude-plugins-official", marketplaceSource: nil))
}

@Test func parsesCliPluginWithMarketplaceAdd() {
    let text = "claude plugin marketplace add https://github.com/obra/superpowers-marketplace\nclaude plugin install superpowers@superpowers-marketplace"
    #expect(InstallIntentParser.parse(text) ==
        .plugin(name: "superpowers", marketplace: "superpowers-marketplace",
                marketplaceSource: "https://github.com/obra/superpowers-marketplace"))
}

@Test func parsesNpxSkillsAdd() {
    #expect(InstallIntentParser.parse("npx skills add jakubkrehel/skills") ==
        .skillsRepo(owner: "jakubkrehel", repo: "skills", subpath: nil, onlySkills: nil))
}

@Test func parsesNpxSkillsAddWithSkillFlags() {
    #expect(InstallIntentParser.parse("npx skills add emilkowalski/skills --skill apple-design,emil-design-eng") ==
        .skillsRepo(owner: "emilkowalski", repo: "skills", subpath: nil, onlySkills: ["apple-design", "emil-design-eng"]))
    #expect(InstallIntentParser.parse("npx skills add emilkowalski/skills -s apple-design") ==
        .skillsRepo(owner: "emilkowalski", repo: "skills", subpath: nil, onlySkills: ["apple-design"]))
}

@Test func parsesNpxSkillsAddWithGitHubURL() {
    #expect(InstallIntentParser.parse("npx skills add https://github.com/vercel-labs/agent-skills") ==
        .skillsRepo(owner: "vercel-labs", repo: "agent-skills", subpath: nil, onlySkills: nil))
}

@Test func parsesNpxInsideReadmeSentence() {
    let text = "## Install\n\nWe recommend the CLI. Run `npx skills add emilkowalski/skills --skill apple-design` and restart Claude."
    #expect(InstallIntentParser.parse(text) ==
        .skillsRepo(owner: "emilkowalski", repo: "skills", subpath: nil, onlySkills: ["apple-design"]))
}

@Test func parsesSkillsShLinks() {
    #expect(InstallIntentParser.parse("https://skills.sh/jakubkrehel/skills") ==
        .skillsRepo(owner: "jakubkrehel", repo: "skills", subpath: nil, onlySkills: nil))
    #expect(InstallIntentParser.parse("https://www.skills.sh/jakubkrehel/skills/better-ui") ==
        .skillsRepo(owner: "jakubkrehel", repo: "skills", subpath: nil, onlySkills: ["better-ui"]))
}

@Test func parsesGitHubLinks() {
    #expect(InstallIntentParser.parse("https://github.com/jakubkrehel/skills") ==
        .skillsRepo(owner: "jakubkrehel", repo: "skills", subpath: nil, onlySkills: nil))
    #expect(InstallIntentParser.parse("https://github.com/jakubkrehel/skills.git") ==
        .skillsRepo(owner: "jakubkrehel", repo: "skills", subpath: nil, onlySkills: nil))
    #expect(InstallIntentParser.parse("https://github.com/jakubkrehel/skills/tree/main/skills/better-ui") ==
        .skillsRepo(owner: "jakubkrehel", repo: "skills", subpath: "skills/better-ui", onlySkills: ["better-ui"]))
}

@Test func parsesBareShorthandAloneOnALine() {
    #expect(InstallIntentParser.parse("  jakubkrehel/skills \n") ==
        .skillsRepo(owner: "jakubkrehel", repo: "skills", subpath: nil, onlySkills: nil))
    // Not alone on a line → not shorthand.
    #expect(InstallIntentParser.parse("check out jakubkrehel/skills sometime") == .unrecognized(diagnosis: Diagnosis.generic))
}

@Test func slashPluginWinsOverEmbeddedRepoShorthand() {
    // The marketplace-add line also contains "o/r"; plugin shape must be matched first.
    let text = "/plugin marketplace add jakubkrehel/skills\n/plugin install interfaces@interfaces"
    if case .plugin = InstallIntentParser.parse(text) {} else { Issue.record("expected plugin") }
}

@Test func rejectsPackageManagers() {
    #expect(InstallIntentParser.parse("brew install ripgrep") == .unrecognized(diagnosis: Diagnosis.packageManager("Homebrew")))
    #expect(InstallIntentParser.parse("npm install -g typescript") == .unrecognized(diagnosis: Diagnosis.packageManager("npm")))
    #expect(InstallIntentParser.parse("pip install requests") == .unrecognized(diagnosis: Diagnosis.packageManager("pip")))
}

@Test func rejectsNonGitHubURL() {
    #expect(InstallIntentParser.parse("https://notion.so/some-page") == .unrecognized(diagnosis: Diagnosis.nonGitHubURL))
}

@Test func rejectsProseAndEmpty() {
    #expect(InstallIntentParser.parse("hello there") == .unrecognized(diagnosis: Diagnosis.generic))
    #expect(InstallIntentParser.parse("   ") == .unrecognized(diagnosis: Diagnosis.generic))
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd SkillsManagerCore && swift test --filter InstallIntentParser`
Expected: compile error, `InstallIntentParser` undefined.

- [ ] **Step 3: Implement**

Create `SkillsManagerCore/Sources/SkillsManagerCore/Install/InstallIntent.swift`:

```swift
import Foundation

/// What the user pasted, once recognized. Verified by InstallResolver before
/// anything is shown; never acted on directly.
public enum InstallIntent: Sendable, Equatable {
    case skillsRepo(owner: String, repo: String, subpath: String?, onlySkills: [String]?)
    case plugin(name: String, marketplace: String, marketplaceSource: String?)
    case unrecognized(diagnosis: String)
}

/// Typed failures that map 1:1 to the plain-English sentences in spec §5/§7.
public enum InstallError: Error, Sendable, Equatable {
    case repoNotFound
    case noSkills
    case rateLimited
    case network(String)
    case other(String)
}

/// Spec §4.3 — exact sentences for unrecognized input.
public enum Diagnosis {
    public static func packageManager(_ tool: String) -> String {
        "That looks like a \(tool) command, not a skill or plugin."
    }
    public static let nonGitHubURL = "Only GitHub and skills.sh links are supported right now."
    public static let generic = "Couldn't find a skill or plugin in that. Try pasting just the link or the install command."
}

/// Tier-1 recognition (spec §4.1). Pure, deterministic, order-sensitive.
public enum InstallIntentParser {
    private static let ident = #"[A-Za-z0-9_.-]+"#

    public static func parse(_ raw: String) -> InstallIntent {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .unrecognized(diagnosis: Diagnosis.generic) }

        if let plugin = parsePlugin(text) { return plugin }
        if let npx = parseNpx(text) { return npx }
        if let site = parseSkillsSh(text) { return site }
        if let gh = parseGitHub(text) { return gh }
        if let bare = parseBareShorthand(text) { return bare }
        return .unrecognized(diagnosis: diagnose(text))
    }

    // MARK: shapes

    private static func parsePlugin(_ text: String) -> InstallIntent? {
        // "/plugin install p@m" or "claude plugin install p@m"
        let install = try! NSRegularExpression(pattern: #"(?:^|\s)(?:/plugin|claude\s+plugin)\s+install\s+(\#(ident))@(\#(ident))"#)
        guard let m = install.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let name = text[m.range(at: 1)], let market = text[m.range(at: 2)] else { return nil }
        let add = try! NSRegularExpression(pattern: #"(?:^|\s)(?:/plugin|claude\s+plugin)\s+marketplace\s+add\s+(\S+)"#)
        let source = add.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
            .flatMap { text[$0.range(at: 1)] }
        return .plugin(name: name, marketplace: market, marketplaceSource: source)
    }

    private static func parseNpx(_ text: String) -> InstallIntent? {
        let re = try! NSRegularExpression(pattern: #"npx\s+(?:-y\s+)?skills\s+add\s+(\S+)((?:\s+-[-\w]+(?:\s+[^\s`-][^\s`]*)?)*)"#)
        guard let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let ref = text[m.range(at: 1)] else { return nil }
        guard let (owner, repo) = ownerRepo(fromRef: ref.trimmingCharacters(in: CharacterSet(charactersIn: "`'\""))) else { return nil }
        var only: [String]?
        if let flags = text[m.range(at: 2)] {
            let skillRe = try! NSRegularExpression(pattern: #"(?:--skill|-s)\s+([^\s`]+)"#)
            if let sm = skillRe.firstMatch(in: flags, range: NSRange(flags.startIndex..., in: flags)),
               let list = flags[sm.range(at: 1)] {
                only = list.split(separator: ",").map { String($0) }
            }
        }
        return .skillsRepo(owner: owner, repo: repo, subpath: nil, onlySkills: only)
    }

    private static func parseSkillsSh(_ text: String) -> InstallIntent? {
        let re = try! NSRegularExpression(pattern: #"https?://(?:www\.)?skills\.sh/(\#(ident))/(\#(ident))(?:/(\#(ident)))?"#)
        guard let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let owner = text[m.range(at: 1)], let repo = text[m.range(at: 2)] else { return nil }
        let skill = text[m.range(at: 3)]
        return .skillsRepo(owner: owner, repo: repo, subpath: nil, onlySkills: skill.map { [$0] })
    }

    private static func parseGitHub(_ text: String) -> InstallIntent? {
        let re = try! NSRegularExpression(pattern: #"https?://(?:www\.)?github\.com/(\#(ident))/(\#(ident))(?:/tree/[^/\s]+/([^\s`]+))?"#)
        guard let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let owner = text[m.range(at: 1)], var repo = text[m.range(at: 2)] else { return nil }
        if repo.hasSuffix(".git") { repo.removeLast(4) }
        let path = text[m.range(at: 3)]?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let last = path?.split(separator: "/").last.map(String.init)
        return .skillsRepo(owner: owner, repo: repo, subpath: path, onlySkills: last.map { [$0] })
    }

    private static func parseBareShorthand(_ text: String) -> InstallIntent? {
        let re = try! NSRegularExpression(pattern: #"^\s*(\#(ident))/(\#(ident))\s*$"#, options: [.anchorsMatchLines])
        guard let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let owner = text[m.range(at: 1)], let repo = text[m.range(at: 2)] else { return nil }
        return .skillsRepo(owner: owner, repo: repo, subpath: nil, onlySkills: nil)
    }

    // MARK: helpers

    /// "o/r", "github.com/o/r", or a GitHub URL → (o, r)
    private static func ownerRepo(fromRef ref: String) -> (String, String)? {
        var s = ref
        for prefix in ["https://", "http://", "www.", "github.com/"] where s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
        if s.hasPrefix("github.com/") { s.removeFirst("github.com/".count) }
        if s.hasSuffix(".git") { s.removeLast(4) }
        let parts = s.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    private static func diagnose(_ text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("brew install") { return Diagnosis.packageManager("Homebrew") }
        if lower.contains("npm install") || lower.contains("npm i ") { return Diagnosis.packageManager("npm") }
        if lower.contains("pip install") || lower.contains("pip3 install") { return Diagnosis.packageManager("pip") }
        if lower.contains("http://") || lower.contains("https://") { return Diagnosis.nonGitHubURL }
        return Diagnosis.generic
    }
}

private extension String {
    subscript(_ range: NSRange) -> String? {
        guard range.location != NSNotFound, let r = Range(range, in: self) else { return nil }
        return String(self[r])
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd SkillsManagerCore && swift test`
Expected: 42 existing + 15 new = 57 passing. If any regex mis-parses, fix the regex, not the test.

- [ ] **Step 5: Commit**

```bash
git add SkillsManagerCore/Sources/SkillsManagerCore/Install/InstallIntent.swift SkillsManagerCore/Tests/SkillsManagerCoreTests/InstallIntentParserTests.swift
git commit -m "feat: InstallIntent and deterministic parser for pasted links and commands

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: GitHub client, preview types and resolver

**Files:**
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/Install/GitHubClient.swift`
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/Install/InstallPreview.swift`
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/Install/InstallResolver.swift`
- Create: `SkillsManagerCore/Tests/SkillsManagerCoreTests/InstallResolverTests.swift`

**Interfaces:**
- Consumes: `InstallIntent`, `InstallError` (Task 1); `FrontmatterParser`, `ClaudePaths`, `PluginRegistry.loadRecords` (existing).
- Produces:
  ```swift
  public struct GitHubRepo: Sendable, Equatable { public let description: String?; public let defaultBranch: String; public let htmlURL: URL; public let ownerURL: URL? }
  public protocol GitHubClient: Sendable {
      func repo(owner: String, repo: String) async throws -> GitHubRepo
      func treePaths(owner: String, repo: String, branch: String) async throws -> [String]
      func raw(owner: String, repo: String, branch: String, path: String) async throws -> String
  }
  public struct URLSessionGitHubClient: GitHubClient { public init(session: URLSession = .shared) }
  public enum PreviewKind: Sendable, Equatable { case skillsRepo, plugin }
  public struct PreviewSkill: Identifiable, Sendable, Equatable { id = folder; folder, name, summary?, body, invocation, isInstalled, isValid, isPreselected }
  public struct InstallPreview: Sendable, Equatable { kind, title, summary?, authorName?, authorURL?, sourceURL?, skills, marketplaceNote?, isPluginInstalled, pluginName?, marketplace?, marketplaceSource?, owner?, repo? }
  public struct InstallResolver: Sendable { public init(github: GitHubClient, paths: ClaudePaths); public func resolve(_ intent: InstallIntent) async throws -> InstallPreview }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import SkillsManagerCore

/// Canned GitHub. Keys: "owner/repo" → repo; tree paths; raw files by path.
struct StubGitHubClient: GitHubClient {
    var repos: [String: GitHubRepo] = [:]
    var trees: [String: [String]] = [:]
    var files: [String: String] = [:]
    var failure: InstallError?

    func repo(owner: String, repo: String) async throws -> GitHubRepo {
        if let failure { throw failure }
        guard let r = repos["\(owner)/\(repo)"] else { throw InstallError.repoNotFound }
        return r
    }
    func treePaths(owner: String, repo: String, branch: String) async throws -> [String] {
        trees["\(owner)/\(repo)"] ?? []
    }
    func raw(owner: String, repo: String, branch: String, path: String) async throws -> String {
        guard let f = files[path] else { throw InstallError.other("missing \(path)") }
        return f
    }
}

private func skillFile(_ name: String, _ desc: String) -> String {
    "---\nname: \(name)\ndescription: \(desc)\n---\n\n# \(name)\n\nBody of \(name).\n"
}

private func stub() -> StubGitHubClient {
    StubGitHubClient(
        repos: ["jakubkrehel/skills": GitHubRepo(description: "Better interfaces", defaultBranch: "main",
                                                htmlURL: URL(string: "https://github.com/jakubkrehel/skills")!,
                                                ownerURL: URL(string: "https://github.com/jakubkrehel"))],
        trees: ["jakubkrehel/skills": ["README.md", "skills/better-ui/SKILL.md", "skills/better-layout/SKILL.md",
                                       "skills/broken/SKILL.md", "skills/better-ui/notes.md"]],
        files: ["skills/better-ui/SKILL.md": skillFile("better-ui", "Polish UI"),
                "skills/better-layout/SKILL.md": skillFile("better-layout", "Layout help"),
                "skills/broken/SKILL.md": "---\nname: broken\n"])
}

@Test func resolvesSkillsRepoWithAllSkillsPreselected() async throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let resolver = InstallResolver(github: stub(), paths: ClaudePaths(home: home))
    let p = try await resolver.resolve(.skillsRepo(owner: "jakubkrehel", repo: "skills", subpath: nil, onlySkills: nil))
    #expect(p.kind == .skillsRepo)
    #expect(p.title == "jakubkrehel/skills")
    #expect(p.summary == "Better interfaces")
    #expect(p.authorName == "jakubkrehel")
    #expect(p.sourceURL == URL(string: "https://github.com/jakubkrehel/skills"))
    #expect(p.skills.map(\.folder) == ["better-layout", "better-ui", "broken"])   // sorted
    let ui = try #require(p.skills.first { $0.folder == "better-ui" })
    #expect(ui.name == "better-ui"); #expect(ui.summary == "Polish UI"); #expect(ui.invocation == "/better-ui")
    #expect(ui.isValid); #expect(ui.isPreselected); #expect(!ui.isInstalled)
    #expect(ui.body.contains("Body of better-ui"))
    let broken = try #require(p.skills.first { $0.folder == "broken" })
    #expect(!broken.isValid); #expect(!broken.isPreselected)
}

@Test func onlySkillsNarrowsPreselection() async throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let resolver = InstallResolver(github: stub(), paths: ClaudePaths(home: home))
    let p = try await resolver.resolve(.skillsRepo(owner: "jakubkrehel", repo: "skills", subpath: nil, onlySkills: ["better-ui"]))
    #expect(p.skills.filter(\.isPreselected).map(\.folder) == ["better-ui"])
}

@Test func subpathNarrowsDiscovery() async throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let resolver = InstallResolver(github: stub(), paths: ClaudePaths(home: home))
    let p = try await resolver.resolve(.skillsRepo(owner: "jakubkrehel", repo: "skills", subpath: "skills/better-layout", onlySkills: ["better-layout"]))
    #expect(p.skills.map(\.folder) == ["better-layout"])
}

@Test func alreadyInstalledSkillIsFlaggedAndNotPreselected() async throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    var s = stub()
    s.trees["jakubkrehel/skills"]?.append("skills/shared-skill/SKILL.md")   // exists in fixture ~/.agents/skills
    s.files["skills/shared-skill/SKILL.md"] = skillFile("shared-skill", "dup")
    let p = try await InstallResolver(github: s, paths: ClaudePaths(home: home))
        .resolve(.skillsRepo(owner: "jakubkrehel", repo: "skills", subpath: nil, onlySkills: nil))
    let dup = try #require(p.skills.first { $0.folder == "shared-skill" })
    #expect(dup.isInstalled); #expect(!dup.isPreselected)
}

@Test func repoNotFoundAndNoSkillsAndRateLimit() async throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let paths = ClaudePaths(home: home)
    await #expect(throws: InstallError.repoNotFound) {
        try await InstallResolver(github: StubGitHubClient(), paths: paths)
            .resolve(.skillsRepo(owner: "nobody", repo: "nothing", subpath: nil, onlySkills: nil))
    }
    var empty = stub(); empty.trees["jakubkrehel/skills"] = ["README.md"]
    await #expect(throws: InstallError.noSkills) {
        try await InstallResolver(github: empty, paths: paths)
            .resolve(.skillsRepo(owner: "jakubkrehel", repo: "skills", subpath: nil, onlySkills: nil))
    }
    var limited = stub(); limited.failure = .rateLimited
    await #expect(throws: InstallError.rateLimited) {
        try await InstallResolver(github: limited, paths: paths)
            .resolve(.skillsRepo(owner: "jakubkrehel", repo: "skills", subpath: nil, onlySkills: nil))
    }
}

@Test func resolvesPluginInKnownMarketplaceAndAlreadyInstalled() async throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    // Fixture registry knows demo-plugin@test-market; write a marketplace.json so details resolve.
    let mdir = home.appending(path: ".claude/plugins/marketplaces/test-market/.claude-plugin")
    try FileManager.default.createDirectory(at: mdir, withIntermediateDirectories: true)
    try #"{ "name": "test-market", "plugins": [ { "name": "other-plugin", "description": "Another one", "homepage": "https://example.com/other" } ] }"#
        .write(to: mdir.appending(path: "marketplace.json"), atomically: true, encoding: .utf8)
    let resolver = InstallResolver(github: StubGitHubClient(), paths: ClaudePaths(home: home))

    let fresh = try await resolver.resolve(.plugin(name: "other-plugin", marketplace: "test-market", marketplaceSource: nil))
    #expect(fresh.kind == .plugin); #expect(fresh.title == "other-plugin")
    #expect(fresh.summary == "Another one"); #expect(fresh.sourceURL == URL(string: "https://example.com/other"))
    #expect(!fresh.isPluginInstalled); #expect(fresh.marketplaceNote == nil); #expect(fresh.skills.isEmpty)

    let dup = try await resolver.resolve(.plugin(name: "demo-plugin", marketplace: "test-market", marketplaceSource: nil))
    #expect(dup.isPluginInstalled)
}

@Test func resolvesPluginInUnknownMarketplaceWithNote() async throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    let p = try await InstallResolver(github: StubGitHubClient(), paths: ClaudePaths(home: home))
        .resolve(.plugin(name: "interfaces", marketplace: "interfaces", marketplaceSource: "jakubkrehel/skills"))
    #expect(p.title == "interfaces")
    #expect(p.marketplaceNote == "Will add marketplace interfaces from jakubkrehel/skills first.")
    #expect(p.summary == nil)
}

@Test func unrecognizedIntentThrows() async throws {
    let home = try FixtureHome.make()
    defer { try? FileManager.default.removeItem(at: home) }
    await #expect(throws: InstallError.other(Diagnosis.generic)) {
        try await InstallResolver(github: StubGitHubClient(), paths: ClaudePaths(home: home))
            .resolve(.unrecognized(diagnosis: Diagnosis.generic))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd SkillsManagerCore && swift test --filter InstallResolver`
Expected: compile error.

- [ ] **Step 3: Implement `GitHubClient.swift`**

```swift
import Foundation

public struct GitHubRepo: Sendable, Equatable {
    public let description: String?
    public let defaultBranch: String
    public let htmlURL: URL
    public let ownerURL: URL?
    public init(description: String?, defaultBranch: String, htmlURL: URL, ownerURL: URL?) {
        self.description = description; self.defaultBranch = defaultBranch; self.htmlURL = htmlURL; self.ownerURL = ownerURL
    }
}

/// The three GitHub reads the resolver needs. Unauthenticated (60 req/h).
public protocol GitHubClient: Sendable {
    func repo(owner: String, repo: String) async throws -> GitHubRepo
    func treePaths(owner: String, repo: String, branch: String) async throws -> [String]
    func raw(owner: String, repo: String, branch: String, path: String) async throws -> String
}

public struct URLSessionGitHubClient: GitHubClient {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func repo(owner: String, repo: String) async throws -> GitHubRepo {
        let json = try await getJSON("https://api.github.com/repos/\(owner)/\(repo)")
        guard let branch = json["default_branch"] as? String,
              let html = (json["html_url"] as? String).flatMap(URL.init(string:)) else {
            throw InstallError.other("Unexpected reply from GitHub.")
        }
        let ownerURL = ((json["owner"] as? [String: Any])?["html_url"] as? String).flatMap(URL.init(string:))
        return GitHubRepo(description: json["description"] as? String, defaultBranch: branch, htmlURL: html, ownerURL: ownerURL)
    }

    public func treePaths(owner: String, repo: String, branch: String) async throws -> [String] {
        let json = try await getJSON("https://api.github.com/repos/\(owner)/\(repo)/git/trees/\(branch)?recursive=1")
        let tree = json["tree"] as? [[String: Any]] ?? []
        return tree.compactMap { $0["path"] as? String }
    }

    public func raw(owner: String, repo: String, branch: String, path: String) async throws -> String {
        let (data, _) = try await get("https://raw.githubusercontent.com/\(owner)/\(repo)/\(branch)/\(path)")
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: plumbing

    private func getJSON(_ url: String) async throws -> [String: Any] {
        let (data, _) = try await get(url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallError.other("Unexpected reply from GitHub.")
        }
        return json
    }

    private func get(_ urlString: String) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: urlString) else { throw InstallError.other("Bad URL.") }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SkillsManager", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw InstallError.network(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw InstallError.network("No response.") }
        switch http.statusCode {
        case 200..<300: return (data, http)
        case 404: throw InstallError.repoNotFound
        case 403, 429: throw InstallError.rateLimited
        default: throw InstallError.other("GitHub replied with status \(http.statusCode).")
        }
    }
}
```

- [ ] **Step 4: Implement `InstallPreview.swift`**

```swift
import Foundation

public enum PreviewKind: Sendable, Equatable { case skillsRepo, plugin }

/// One skill the install would add, as verified from the source.
public struct PreviewSkill: Identifiable, Sendable, Equatable {
    public var id: String { folder }
    public let folder: String
    public let name: String
    public let summary: String?
    public let body: String
    public let invocation: String
    public let isInstalled: Bool
    public let isValid: Bool          // frontmatter parsed
    public let isPreselected: Bool    // checked by default

    public init(folder: String, name: String, summary: String?, body: String, invocation: String,
                isInstalled: Bool, isValid: Bool, isPreselected: Bool) {
        self.folder = folder; self.name = name; self.summary = summary; self.body = body
        self.invocation = invocation; self.isInstalled = isInstalled; self.isValid = isValid; self.isPreselected = isPreselected
    }
}

/// Everything the sheet shows before Install, and everything Installer needs after.
public struct InstallPreview: Sendable, Equatable {
    public let kind: PreviewKind
    public let title: String
    public let summary: String?
    public let authorName: String?
    public let authorURL: URL?
    public let sourceURL: URL?
    public let skills: [PreviewSkill]
    public let marketplaceNote: String?
    public let isPluginInstalled: Bool
    // Identity carried forward to Installer.
    public let owner: String?
    public let repo: String?
    public let pluginName: String?
    public let marketplace: String?
    public let marketplaceSource: String?

    public init(kind: PreviewKind, title: String, summary: String?, authorName: String?, authorURL: URL?,
                sourceURL: URL?, skills: [PreviewSkill], marketplaceNote: String?, isPluginInstalled: Bool,
                owner: String?, repo: String?, pluginName: String?, marketplace: String?, marketplaceSource: String?) {
        self.kind = kind; self.title = title; self.summary = summary; self.authorName = authorName
        self.authorURL = authorURL; self.sourceURL = sourceURL; self.skills = skills
        self.marketplaceNote = marketplaceNote; self.isPluginInstalled = isPluginInstalled
        self.owner = owner; self.repo = repo; self.pluginName = pluginName
        self.marketplace = marketplace; self.marketplaceSource = marketplaceSource
    }
}
```

- [ ] **Step 5: Implement `InstallResolver.swift`**

```swift
import Foundation

/// Spec §5: turn a recognized intent into a verified preview. Throws InstallError.
public struct InstallResolver: Sendable {
    private let github: GitHubClient
    private let paths: ClaudePaths
    private static let maxSkills = 50

    public init(github: GitHubClient, paths: ClaudePaths) {
        self.github = github
        self.paths = paths
    }

    public func resolve(_ intent: InstallIntent) async throws -> InstallPreview {
        switch intent {
        case .unrecognized(let diagnosis):
            throw InstallError.other(diagnosis)
        case .skillsRepo(let owner, let repo, let subpath, let only):
            return try await resolveRepo(owner: owner, repo: repo, subpath: subpath, only: only)
        case .plugin(let name, let market, let source):
            return resolvePlugin(name: name, marketplace: market, source: source)
        }
    }

    // MARK: skills repo

    private func resolveRepo(owner: String, repo: String, subpath: String?, only: [String]?) async throws -> InstallPreview {
        let info = try await github.repo(owner: owner, repo: repo)
        var paths = try await github.treePaths(owner: owner, repo: repo, branch: info.defaultBranch)
            .filter { $0 == "SKILL.md" || $0.hasSuffix("/SKILL.md") }
        if let subpath {
            let prefix = subpath.hasSuffix("/") ? subpath : subpath + "/"
            paths = paths.filter { $0.hasPrefix(prefix) || $0 == subpath + "/SKILL.md" }
        }
        guard !paths.isEmpty else { throw InstallError.noSkills }

        let installed = installedSkillFolders()
        var skills: [PreviewSkill] = []
        for path in paths.prefix(Self.maxSkills) {
            let folder = path == "SKILL.md" ? repo : String(path.dropLast("/SKILL.md".count).split(separator: "/").last ?? Substring(repo))
            let text = try await github.raw(owner: owner, repo: repo, branch: info.defaultBranch, path: path)
            let isInstalled = installed.contains(folder)
            switch FrontmatterParser.parse(text) {
            case .parsed(let fm, let body):
                let wanted = only.map { $0.contains(folder) } ?? true
                skills.append(PreviewSkill(folder: folder, name: fm.name ?? folder, summary: fm.description, body: body,
                                           invocation: "/\(folder)", isInstalled: isInstalled, isValid: true,
                                           isPreselected: wanted && !isInstalled))
            case .missing(let body):
                skills.append(PreviewSkill(folder: folder, name: folder, summary: nil, body: body, invocation: "/\(folder)",
                                           isInstalled: isInstalled, isValid: false, isPreselected: false))
            case .malformed:
                skills.append(PreviewSkill(folder: folder, name: folder, summary: nil, body: text, invocation: "/\(folder)",
                                           isInstalled: isInstalled, isValid: false, isPreselected: false))
            }
        }
        skills.sort { $0.folder < $1.folder }
        return InstallPreview(kind: .skillsRepo, title: "\(owner)/\(repo)", summary: info.description,
                              authorName: owner, authorURL: info.ownerURL, sourceURL: info.htmlURL,
                              skills: skills, marketplaceNote: nil, isPluginInstalled: false,
                              owner: owner, repo: repo, pluginName: nil, marketplace: nil, marketplaceSource: nil)
    }

    /// Folder names present in either skills dir (symlinks count — that's how connected skills look).
    private func installedSkillFolders() -> Set<String> {
        let fm = FileManager.default
        var names = Set<String>()
        for dir in [paths.personalSkillsDir, paths.sharedSkillsDir] {
            for entry in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where !entry.hasPrefix(".") {
                names.insert(entry)
            }
        }
        return names
    }

    // MARK: plugin

    private func resolvePlugin(name: String, marketplace: String, source: String?) -> InstallPreview {
        let pluginID = "\(name)@\(marketplace)"
        let installed = ((try? PluginRegistry.loadRecords(installedPluginsFile: paths.installedPluginsFile)) ?? [])
            .contains { $0.pluginID == pluginID }
        let known = knownMarketplaces().contains(marketplace)
        var summary: String?
        var homepage: URL?
        if known, let entry = marketplaceEntry(marketplace: marketplace, plugin: name) {
            summary = entry["description"] as? String
            homepage = GitURL.browsable(entry["homepage"] as? String)
        }
        let note: String? = (!known && source != nil) ? "Will add marketplace \(marketplace) from \(source!) first." : nil
        return InstallPreview(kind: .plugin, title: name, summary: summary, authorName: nil, authorURL: nil,
                              sourceURL: homepage, skills: [], marketplaceNote: note, isPluginInstalled: installed,
                              owner: nil, repo: nil, pluginName: name, marketplace: marketplace, marketplaceSource: source)
    }

    private func knownMarketplaces() -> Set<String> {
        guard let data = try? Data(contentsOf: paths.knownMarketplacesFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return Set(json.keys)
    }

    private func marketplaceEntry(marketplace: String, plugin: String) -> [String: Any]? {
        let file = paths.pluginsDir.appending(path: "marketplaces/\(marketplace)/.claude-plugin/marketplace.json")
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = json["plugins"] as? [[String: Any]] else { return nil }
        return plugins.first { ($0["name"] as? String) == plugin }
    }
}
```

Note for the "known marketplace" test: the fixture's `known_marketplaces.json` lists `test-market`, so `known == true` there; the unknown-marketplace test uses `interfaces`, which is absent.

- [ ] **Step 6: Run tests**

Run: `cd SkillsManagerCore && swift test`
Expected: 57 + 8 = 65 passing.

- [ ] **Step 7: Commit**

```bash
git add SkillsManagerCore
git commit -m "feat: GitHub client and InstallResolver build a verified install preview

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Command runner, installer, guesser protocol

**Files:**
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/Install/CommandRunner.swift`
- Create: `SkillsManagerCore/Sources/SkillsManagerCore/Install/Installer.swift`
- Create: `SkillsManagerCore/Tests/SkillsManagerCoreTests/InstallerTests.swift`
- Modify: `SkillsManagerCore/Sources/SkillsManagerCore/Version.swift`, `SkillsManagerCore/Tests/SkillsManagerCoreTests/SmokeTests.swift`

**Interfaces:**
- Consumes: `InstallPreview` (Task 2), `InstallIntent` (Task 1).
- Produces:
  ```swift
  public struct CommandResult: Sendable, Equatable { status: Int32; stdout: String; stderr: String; timedOut: Bool }
  public protocol CommandRunner: Sendable { func run(_ argv: [String], timeout: TimeInterval) async -> CommandResult }
  public struct ShellCommandRunner: CommandRunner { public init() }          // /bin/zsh -lic, NO_COLOR/CI/TERM
  public enum ToolCheck { public static func resolves(_ tool: String, runner: CommandRunner) async -> Bool }
  public enum InstallOutcome: Sendable, Equatable { case success(log: String); case failure(message: String, log: String) }
  public enum FailureCopy { public static func sentence(for result: CommandResult, marketplace: String?) -> String }
  public struct Installer: Sendable {
      public init(runner: CommandRunner)
      public func plan(_ preview: InstallPreview, selectedFolders: [String]) -> [[String]]   // argv lists
      public func install(_ preview: InstallPreview, selectedFolders: [String]) async -> InstallOutcome
  }
  public protocol IntentGuesser: Sendable { func guess(_ text: String) async -> InstallIntent }
  public struct NoopGuesser: IntentGuesser { public init() }   // always .unrecognized(generic)
  ```

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import SkillsManagerCore

/// Records argv and replays canned results in order.
final class FakeCommandRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var calls: [[String]] = []
    var results: [CommandResult]
    init(results: [CommandResult]) { self.results = results }
    func run(_ argv: [String], timeout: TimeInterval) async -> CommandResult {
        lock.lock(); defer { lock.unlock() }
        calls.append(argv)
        return results.isEmpty ? CommandResult(status: 0, stdout: "", stderr: "", timedOut: false) : results.removeFirst()
    }
}

private func repoPreview(_ folders: [String]) -> InstallPreview {
    InstallPreview(kind: .skillsRepo, title: "o/r", summary: nil, authorName: "o", authorURL: nil, sourceURL: nil,
                   skills: folders.map { PreviewSkill(folder: $0, name: $0, summary: nil, body: "", invocation: "/\($0)",
                                                      isInstalled: false, isValid: true, isPreselected: true) },
                   marketplaceNote: nil, isPluginInstalled: false, owner: "o", repo: "r",
                   pluginName: nil, marketplace: nil, marketplaceSource: nil)
}

private func pluginPreview(source: String?, note: String?) -> InstallPreview {
    InstallPreview(kind: .plugin, title: "p", summary: nil, authorName: nil, authorURL: nil, sourceURL: nil, skills: [],
                   marketplaceNote: note, isPluginInstalled: false, owner: nil, repo: nil,
                   pluginName: "p", marketplace: "m", marketplaceSource: source)
}

private let ok = CommandResult(status: 0, stdout: "done", stderr: "", timedOut: false)

@Test func plansSkillsInstallWithSelectedFoldersOnly() {
    let argv = Installer(runner: FakeCommandRunner(results: [])).plan(repoPreview(["a", "b", "c"]), selectedFolders: ["a", "c"])
    #expect(argv == [["npx", "-y", "skills", "add", "o/r", "-g", "-y", "-a", "claude-code", "-s", "a,c"]])
}

@Test func plansPluginInstallAddingUnknownMarketplaceFirst() {
    let installer = Installer(runner: FakeCommandRunner(results: []))
    #expect(installer.plan(pluginPreview(source: "o/r", note: "Will add…"), selectedFolders: []) ==
        [["claude", "plugin", "marketplace", "add", "o/r"], ["claude", "plugin", "install", "p@m", "-y"]])
    #expect(installer.plan(pluginPreview(source: "o/r", note: nil), selectedFolders: []) ==
        [["claude", "plugin", "install", "p@m", "-y"]])    // marketplace already known → no add
}

@Test func installRunsPlanAndReportsSuccess() async {
    let runner = FakeCommandRunner(results: [ok])
    let outcome = await Installer(runner: runner).install(repoPreview(["a"]), selectedFolders: ["a"])
    #expect(outcome == .success(log: "done"))
    #expect(runner.calls.count == 1)
}

@Test func installStopsAtFirstFailureAndMapsCopy() async {
    let notFound = CommandResult(status: 1, stdout: "", stderr: "fatal: Repository not found", timedOut: false)
    let runner = FakeCommandRunner(results: [notFound, ok])
    let outcome = await Installer(runner: runner).install(pluginPreview(source: "o/r", note: "x"), selectedFolders: [])
    #expect(outcome == .failure(message: "That repository doesn't exist or is private.", log: "fatal: Repository not found"))
    #expect(runner.calls.count == 1)   // second command never ran
}

@Test func failureCopyCatalog() {
    func r(_ s: String, timedOut: Bool = false) -> CommandResult { CommandResult(status: 1, stdout: s, stderr: "", timedOut: timedOut) }
    #expect(FailureCopy.sentence(for: r("", timedOut: true), marketplace: nil) == "The installer didn't finish in two minutes. Check your connection and try again.")
    #expect(FailureCopy.sentence(for: r("getaddrinfo ENOTFOUND github.com"), marketplace: nil) == "Couldn't reach GitHub. Check your connection.")
    #expect(FailureCopy.sentence(for: r("Could not resolve host: github.com"), marketplace: nil) == "Couldn't reach GitHub. Check your connection.")
    #expect(FailureCopy.sentence(for: r("EACCES: permission denied"), marketplace: nil) == "macOS blocked writing to your skills folder.")
    #expect(FailureCopy.sentence(for: r("Plugin foo not found in marketplace"), marketplace: "m") == "That plugin isn't in the m marketplace.")
    #expect(FailureCopy.sentence(for: r("something odd"), marketplace: nil) == "The installer reported a problem. Show details for what it said.")
}

@Test func noopGuesserIsUnrecognized() async {
    #expect(await NoopGuesser().guess("anything") == .unrecognized(diagnosis: Diagnosis.generic))
}

@Test func toolCheckUsesCommandV() async {
    let runner = FakeCommandRunner(results: [CommandResult(status: 0, stdout: "/usr/local/bin/npx\n", stderr: "", timedOut: false),
                                             CommandResult(status: 1, stdout: "", stderr: "", timedOut: false)])
    #expect(await ToolCheck.resolves("npx", runner: runner) == true)
    #expect(await ToolCheck.resolves("claude", runner: runner) == false)
    #expect(runner.calls == [["command", "-v", "npx"], ["command", "-v", "claude"]])
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd SkillsManagerCore && swift test --filter Installer`
Expected: compile error.

- [ ] **Step 3: Implement `CommandRunner.swift`**

```swift
import Foundation

public struct CommandResult: Sendable, Equatable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool
    public init(status: Int32, stdout: String, stderr: String, timedOut: Bool) {
        self.status = status; self.stdout = stdout; self.stderr = stderr; self.timedOut = timedOut
    }
    public var combinedOutput: String { [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n") }
}

public protocol CommandRunner: Sendable {
    func run(_ argv: [String], timeout: TimeInterval) async -> CommandResult
}

/// Runs argv through the user's login shell so `npx`/`claude` resolve exactly
/// as in Terminal. Spinners suppressed via NO_COLOR/CI/TERM.
public struct ShellCommandRunner: CommandRunner {
    public init() {}

    public func run(_ argv: [String], timeout: TimeInterval) async -> CommandResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lic", argv.map(Self.quote).joined(separator: " ")]
            var env = ProcessInfo.processInfo.environment
            env["NO_COLOR"] = "1"; env["CI"] = "1"; env["TERM"] = "dumb"; env["FORCE_COLOR"] = "0"
            process.environment = env
            let out = Pipe(), err = Pipe()
            process.standardOutput = out; process.standardError = err
            process.standardInput = FileHandle.nullDevice

            let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
            var timedOut = false
            process.terminationHandler = { p in
                let didTimeout = timer.isCancelled == false && p.terminationReason == .uncaughtSignal
                timer.cancel()
                timedOut = didTimeout
                let o = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let e = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                continuation.resume(returning: CommandResult(status: p.terminationStatus, stdout: o, stderr: e, timedOut: timedOut))
            }
            do { try process.run() } catch {
                timer.cancel()
                continuation.resume(returning: CommandResult(status: 127, stdout: "", stderr: error.localizedDescription, timedOut: false))
            }
        }
    }

    static func quote(_ s: String) -> String {
        if s.range(of: #"^[A-Za-z0-9_./:@=,+-]+$"#, options: .regularExpression) != nil { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Preconditions (spec §6): is a tool on the login-shell PATH?
public enum ToolCheck {
    public static func resolves(_ tool: String, runner: CommandRunner) async -> Bool {
        await runner.run(["command", "-v", tool], timeout: 10).status == 0
    }
}
```

- [ ] **Step 4: Implement `Installer.swift`**

```swift
import Foundation

public enum InstallOutcome: Sendable, Equatable {
    case success(log: String)
    case failure(message: String, log: String)
}

/// Spec §7 — exact sentences keyed on what the tool printed.
public enum FailureCopy {
    public static func sentence(for result: CommandResult, marketplace: String?) -> String {
        if result.timedOut { return "The installer didn't finish in two minutes. Check your connection and try again." }
        let out = result.combinedOutput
        if out.contains("ENOTFOUND") || out.contains("Could not resolve host") { return "Couldn't reach GitHub. Check your connection." }
        if out.contains("Repository not found") || out.contains("404") { return "That repository doesn't exist or is private." }
        if out.contains("EACCES") || out.localizedCaseInsensitiveContains("permission denied") { return "macOS blocked writing to your skills folder." }
        if out.contains("not found in marketplace") { return "That plugin isn't in the \(marketplace ?? "") marketplace." }
        return "The installer reported a problem. Show details for what it said."
    }
}

/// Spec §6. Builds the exact commands, runs them in order, stops at the first failure.
public struct Installer: Sendable {
    public static let timeout: TimeInterval = 120
    private let runner: CommandRunner

    public init(runner: CommandRunner) { self.runner = runner }

    public func plan(_ preview: InstallPreview, selectedFolders: [String]) -> [[String]] {
        switch preview.kind {
        case .skillsRepo:
            guard let owner = preview.owner, let repo = preview.repo else { return [] }
            var argv = ["npx", "-y", "skills", "add", "\(owner)/\(repo)", "-g", "-y", "-a", "claude-code"]
            if !selectedFolders.isEmpty { argv += ["-s", selectedFolders.joined(separator: ",")] }
            return [argv]
        case .plugin:
            guard let name = preview.pluginName, let market = preview.marketplace else { return [] }
            var commands: [[String]] = []
            if preview.marketplaceNote != nil, let source = preview.marketplaceSource {
                commands.append(["claude", "plugin", "marketplace", "add", source])
            }
            commands.append(["claude", "plugin", "install", "\(name)@\(market)", "-y"])
            return commands
        }
    }

    public func install(_ preview: InstallPreview, selectedFolders: [String]) async -> InstallOutcome {
        var log = ""
        for argv in plan(preview, selectedFolders: selectedFolders) {
            let result = await runner.run(argv, timeout: Self.timeout)
            log += result.combinedOutput
            guard result.status == 0, !result.timedOut else {
                return .failure(message: FailureCopy.sentence(for: result, marketplace: preview.marketplace), log: log)
            }
        }
        return .success(log: log)
    }
}

/// Tier-2 recognition hook (spec §4.2). The FoundationModels implementation lives
/// in the app target; Core only knows the protocol and a no-op.
public protocol IntentGuesser: Sendable {
    func guess(_ text: String) async -> InstallIntent
}

public struct NoopGuesser: IntentGuesser {
    public init() {}
    public func guess(_ text: String) async -> InstallIntent { .unrecognized(diagnosis: Diagnosis.generic) }
}
```

- [ ] **Step 5: Version bump**

`Version.swift`: `coreVersion = "0.3.0"`. `SmokeTests.swift`: expect `"0.3.0"`.

- [ ] **Step 6: Run tests**

Run: `cd SkillsManagerCore && swift test`
Expected: 65 + 7 = 72 passing.

- [ ] **Step 7: Commit**

```bash
git add SkillsManagerCore
git commit -m "feat: CommandRunner and Installer drive npx skills and claude plugin

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: `InstallSheetModel` and the on-device guesser (app target)

**Files:**
- Create: `App/Install/InstallSheetModel.swift`
- Create: `App/Install/FoundationModelsGuesser.swift`
- Modify: `project.yml` (weak-link FoundationModels)

**Interfaces:**
- Consumes: everything from Tasks 1–3.
- Produces:
  ```swift
  @MainActor @Observable final class InstallSheetModel {
      enum Phase: Equatable { case idle, looking, preview(InstallPreview), unrecognized(String), installing(step: String), success(log: String, installed: [PreviewSkill]), failure(message: String, log: String) }
      var text: String { didSet { scheduleRecognition() } }
      private(set) var phase: Phase
      var selected: Set<String>            // skill folders
      private(set) var missingTool: String?  // precondition note or nil
      init(paths:, github:, guesser:, runner:)
      func checkTools() async; func install() async; func reset(); func cancel()
      var plannedCommands: [String]        // for the Command disclosure
      var canInstall: Bool
  }
  ```

- [ ] **Step 1: Weak-link the framework**

In `project.yml`, under `targets.SkillsManager` add:

```yaml
    dependencies:
      - package: SkillsManagerCore
      - sdk: FoundationModels.framework
        weak: true
```

(keep the existing `package:` line; `weak: true` lets the app launch on macOS 14 where the framework is absent).

- [ ] **Step 2: Write `FoundationModelsGuesser.swift`**

```swift
import Foundation
import SkillsManagerCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Tier-2 recognition (spec §4.2): on-device Apple model, only for text the
/// deterministic parser rejected. Output is validated before becoming an intent.
struct FoundationModelsGuesser: IntentGuesser {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    func guess(_ text: String) async -> InstallIntent {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *), Self.isAvailable else { return .unrecognized(diagnosis: Diagnosis.generic) }
        let session = LanguageModelSession(instructions: """
            You read text a user pasted into an installer for AI coding skills and extract what to install.
            skills-repo = a GitHub repository of skills installed with `npx skills add owner/repo`.
            plugin = a Claude Code plugin installed with `/plugin install name@marketplace` or `claude plugin install`.
            Anything else is unknown. Never invent names that are not in the text.
            """)
        let task = Task { try await session.respond(to: "Input:\n\(text)", generating: GuessedIntent.self).content }
        let timeout = Task { try await Task.sleep(for: .seconds(5)); task.cancel() }
        defer { timeout.cancel() }
        guard let g = try? await task.value else { return .unrecognized(diagnosis: Diagnosis.generic) }
        return Self.validate(g)
        #else
        return .unrecognized(diagnosis: Diagnosis.generic)
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    @Generable
    struct GuessedIntent {
        @Guide(description: "One of: skills-repo, plugin, unknown") var kind: String
        @Guide(description: "GitHub owner/repo exactly as written in the text, else empty") var repo: String
        @Guide(description: "Marketplace name for a plugin install, else empty") var marketplace: String
        @Guide(description: "Plugin name for a plugin install, else empty") var plugin: String
        @Guide(description: "Skill names explicitly named in the text, else empty") var skills: [String]
    }

    @available(macOS 26, *)
    static func validate(_ g: GuessedIntent) -> InstallIntent {
        let ident = #"^[A-Za-z0-9_.-]+$"#
        func ok(_ s: String) -> Bool { s.range(of: ident, options: .regularExpression) != nil }
        switch g.kind {
        case "skills-repo":
            let parts = g.repo.split(separator: "/").map(String.init)
            guard parts.count == 2, parts.allSatisfy(ok) else { return .unrecognized(diagnosis: Diagnosis.generic) }
            let only = g.skills.filter(ok)
            return .skillsRepo(owner: parts[0], repo: parts[1], subpath: nil, onlySkills: only.isEmpty ? nil : only)
        case "plugin":
            guard ok(g.plugin), ok(g.marketplace) else { return .unrecognized(diagnosis: Diagnosis.generic) }
            return .plugin(name: g.plugin, marketplace: g.marketplace, marketplaceSource: nil)
        default:
            return .unrecognized(diagnosis: Diagnosis.generic)
        }
    }
    #endif
}
```

- [ ] **Step 3: Write `InstallSheetModel.swift`**

```swift
import Foundation
import Observation
import SkillsManagerCore

/// Orchestrates paste → recognize → verify → install for the Install sheet.
/// Every network/process step is cancellable; a newer paste always wins.
@MainActor
@Observable
final class InstallSheetModel {
    enum Phase: Equatable {
        case idle
        case looking
        case preview(InstallPreview)
        case unrecognized(String)
        case installing(step: String)
        case success(log: String, installed: [PreviewSkill])
        case failure(message: String, log: String)
    }

    var text: String = "" { didSet { if text != oldValue { scheduleRecognition() } } }
    private(set) var phase: Phase = .idle
    var selected: Set<String> = []
    private(set) var missingTool: String?

    private let paths: ClaudePaths
    private let resolver: InstallResolver
    private let guesser: IntentGuesser
    private let installer: Installer
    private let runner: CommandRunner
    private var recognition: Task<Void, Never>?
    private var generation = 0

    init(paths: ClaudePaths, github: GitHubClient, guesser: IntentGuesser, runner: CommandRunner) {
        self.paths = paths
        self.resolver = InstallResolver(github: github, paths: paths)
        self.guesser = guesser
        self.installer = Installer(runner: runner)
        self.runner = runner
    }

    // MARK: recognition

    private func scheduleRecognition() {
        recognition?.cancel()
        generation += 1
        let gen = generation
        let input = text
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { phase = .idle; return }
        phase = .looking
        recognition = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled, gen == self.generation else { return }
            var intent = InstallIntentParser.parse(input)
            if case .unrecognized = intent {
                intent = await self.guesser.guess(input)
            }
            guard !Task.isCancelled, gen == self.generation else { return }
            if case .unrecognized(let diagnosis) = intent { self.phase = .unrecognized(diagnosis); return }
            do {
                let preview = try await self.resolver.resolve(intent)
                guard !Task.isCancelled, gen == self.generation else { return }
                self.selected = Set(preview.skills.filter(\.isPreselected).map(\.folder))
                self.phase = .preview(preview)
                await self.checkTools(for: preview.kind)
            } catch let error as InstallError {
                guard gen == self.generation else { return }
                self.phase = .unrecognized(Self.sentence(for: error))
            } catch {
                guard gen == self.generation else { return }
                self.phase = .unrecognized("Couldn't reach GitHub. Check your connection.")
            }
        }
    }

    static func sentence(for error: InstallError) -> String {
        switch error {
        case .repoNotFound: "That GitHub repository doesn't exist or is private."
        case .noSkills: "That repository doesn't contain any skills (no SKILL.md files)."
        case .rateLimited: "GitHub is rate-limiting requests from this Mac. Try again in a few minutes."
        case .network: "Couldn't reach GitHub. Check your connection."
        case .other(let s): s
        }
    }

    // MARK: preconditions

    func checkTools(for kind: PreviewKind) async {
        let tool = kind == .skillsRepo ? "npx" : "claude"
        let present = await ToolCheck.resolves(tool, runner: runner)
        missingTool = present ? nil : (kind == .skillsRepo
            ? "Node.js is needed to install skills. Install it from nodejs.org, then try again."
            : "Claude Code's command-line tool wasn't found.")
    }

    // MARK: derived

    var preview: InstallPreview? { if case .preview(let p) = phase { p } else { nil } }

    var plannedCommands: [String] {
        guard let preview else { return [] }
        return installer.plan(preview, selectedFolders: orderedSelection(preview)).map { $0.joined(separator: " ") }
    }

    var canInstall: Bool {
        guard let preview, missingTool == nil else { return false }
        switch preview.kind {
        case .skillsRepo: return !selected.isEmpty
        case .plugin: return !preview.isPluginInstalled
        }
    }

    private func orderedSelection(_ preview: InstallPreview) -> [String] {
        preview.skills.map(\.folder).filter { selected.contains($0) }
    }

    // MARK: install

    func install() async {
        guard let preview, canInstall else { return }
        let folders = orderedSelection(preview)
        phase = .installing(step: preview.kind == .skillsRepo ? "Downloading skills…" : "Installing plugin…")
        switch await installer.install(preview, selectedFolders: folders) {
        case .failure(let message, let log):
            phase = .failure(message: message, log: log)
        case .success(let log):
            let installed = await waitForInstalled(preview, folders: folders)
            phase = .success(log: log, installed: installed)
        }
    }

    /// Spec §6: the cheat sheet is read from disk after install. Falls back to
    /// the predicted rows if nothing appears within 3 s.
    private func waitForInstalled(_ preview: InstallPreview, folders: [String]) async -> [PreviewSkill] {
        guard preview.kind == .skillsRepo else { return [] }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            let present = folders.allSatisfy {
                FileManager.default.fileExists(atPath: paths.personalSkillsDir.appending(path: $0).path)
            }
            if present { break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return preview.skills.filter { folders.contains($0.folder) }
    }

    func retry() { if let preview { phase = .preview(preview) } }

    func reset() {
        recognition?.cancel()
        generation += 1
        text = ""
        selected = []
        missingTool = nil
        phase = .idle
    }
}
```

- [ ] **Step 4: Build**

Run: `xcodegen generate && xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"`
Expected: `** BUILD SUCCEEDED **`. If `@Generable` inside a non-availability-gated type fails to compile, move `GuessedIntent` to file scope with the same `@available(macOS 26, *)` attribute.

- [ ] **Step 5: Commit**

```bash
git add App/Install/InstallSheetModel.swift App/Install/FoundationModelsGuesser.swift project.yml
git commit -m "feat: InstallSheetModel orchestration and on-device intent guesser

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: The Install sheet UI

**Files:**
- Create: `App/Install/InstallSheet.swift`
- Modify: `App/LibraryView.swift` (toolbar button, `.sheet`, drop target)
- Modify: `App/SkillsManagerApp.swift` (File ▸ Install… ⌘N)

**Interfaces:**
- Consumes: `InstallSheetModel` (Task 4), `KindBadge`, `SourceLink`, `InvocationChip`, `SectionCard`, `Spacing`, `Font.metadata` (DesignSystem).
- Produces: `struct InstallSheet: View { let model: InstallSheetModel; let onDone: () -> Void }`; `LibraryView` gains `@State private var showInstall = false` and `@State private var installModel = InstallSheetModel(...)`; `SkillsManagerApp` posts `Notification.Name.showInstallSheet`.

**REQUIRED before editing:** invoke `apple-design`, `make-interfaces-feel-better`, `emil-design-eng`, `better-ui`, `better-layout`, `better-typography`, `better-accessibility`, `better-writing`. Apply: standard `.sheet` sized ~560×min 320; paste field focused on appear; phase transitions animate with `.smooth`, disabled under reduce motion; the preview list is bordered rows not nested cards; checkbox rows have full-row hit areas; the Command disclosure uses `Font.invocation`; error text is secondary color with a leading `exclamationmark.triangle`; progress is `ProgressView()` indeterminate + step label; success reuses `InvocationChip`.

- [ ] **Step 1: Write `InstallSheet.swift`**

```swift
import AppKit
import SwiftUI
import SkillsManagerCore

struct InstallSheet: View {
    @Bindable var model: InstallSheetModel
    let onDone: () -> Void
    @FocusState private var fieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header
            if !isTerminal { pasteField }
            content
            footer
        }
        .padding(Spacing.xl)
        .frame(width: 560)
        .frame(minHeight: 320)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: model.phase)
        .onAppear { fieldFocused = true }
    }

    private var isTerminal: Bool {
        switch model.phase { case .success, .failure, .installing: true; default: false }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Install a skill or plugin").font(.detailTitle)
            Text("Paste a GitHub link, a skills.sh link, or an install command.")
                .foregroundStyle(.secondary)
        }
    }

    private var pasteField: some View {
        TextEditor(text: $model.text)
            .font(.invocation)
            .frame(minHeight: 64, maxHeight: 120)
            .padding(Spacing.sm)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .focused($fieldFocused)
            .accessibilityLabel("Paste a link or install command")
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .looking:
            HStack(spacing: Spacing.sm) { ProgressView().controlSize(.small); Text("Looking…").foregroundStyle(.secondary) }
        case .unrecognized(let sentence):
            Label(sentence, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        case .preview(let preview):
            previewView(preview)
        case .installing(let step):
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ProgressView()
                Text(step).foregroundStyle(.secondary)
            }
        case .success(_, let installed):
            successView(installed)
        case .failure(let message, let log):
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                DisclosureGroup("Show details") {
                    ScrollView { Text(log).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(maxHeight: 160)
                }
            }
        }
    }

    // MARK: preview

    private func previewView(_ p: InstallPreview) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(p.title).font(.headline)
                KindBadge(text: p.kind == .plugin ? "Plugin" : "Skill repository", tint: p.kind == .plugin ? .purple : .blue)
                if let author = p.authorName {
                    if let url = p.authorURL { SourceLink(label: author, url: url) } else { Text(author).foregroundStyle(.secondary) }
                }
            }
            if let summary = p.summary { Text(summary).foregroundStyle(.secondary) }
            if let note = p.marketplaceNote { Text(note).font(.callout).foregroundStyle(.secondary) }
            if p.isPluginInstalled { Text("Already installed").font(.callout).foregroundStyle(.secondary) }
            if let missing = model.missingTool { Label(missing, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.secondary) }

            if !p.skills.isEmpty {
                Text("Skills it will add".uppercased()).font(.cardLabel).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(p.skills) { skill in
                            skillRow(skill)
                            if skill.id != p.skills.last?.id { Divider() }
                        }
                    }
                }
                .frame(maxHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.quaternary))
            }

            DisclosureGroup("Command") {
                ForEach(model.plannedCommands, id: \.self) { cmd in
                    Text(cmd).font(.invocation).textSelection(.enabled)
                }
            }
            .font(.callout)
        }
    }

    private func skillRow(_ skill: PreviewSkill) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Toggle(isOn: Binding(
                get: { model.selected.contains(skill.folder) },
                set: { on in if on { model.selected.insert(skill.folder) } else { model.selected.remove(skill.folder) } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.sm) {
                        Text(skill.name)
                        Text(skill.invocation).font(.metadata).foregroundStyle(.tertiary)
                        if skill.isInstalled { Text("Already installed").font(.metadata).foregroundStyle(.tertiary) }
                        if !skill.isValid { Text("Has a formatting problem").font(.metadata).foregroundStyle(.tertiary) }
                    }
                    if let summary = skill.summary { Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
            }
            .toggleStyle(.checkbox)
            .disabled(!skill.isValid)
            DisclosureGroup("View skill text") {
                ScrollView { Text(skill.body).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 160)
            }
            .font(.caption)
            .padding(.leading, 20)
        }
        .padding(Spacing.sm)
        .contentShape(Rectangle())
    }

    // MARK: success

    private func successView(_ installed: [PreviewSkill]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label("Installed", systemImage: "checkmark.circle").font(.headline)
            if installed.isEmpty {
                Text("Restart Claude Code to load the plugin.").foregroundStyle(.secondary)
            } else {
                Text("Type any of these in Claude Code:").foregroundStyle(.secondary)
                ForEach(installed) { skill in InvocationChip(invocation: skill.invocation) }
                HStack(spacing: Spacing.sm) {
                    Text("Saved in your skills folder").font(.caption).foregroundStyle(.secondary)
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([ClaudePaths().personalSkillsDir])
                    }.buttonStyle(.link).font(.caption)
                }
            }
        }
    }

    // MARK: footer

    private var footer: some View {
        HStack {
            Spacer()
            switch model.phase {
            case .success:
                Button("Done") { model.reset(); onDone() }.keyboardShortcut(.defaultAction)
            case .failure:
                Button("Cancel") { model.reset(); onDone() }.keyboardShortcut(.cancelAction)
                Button("Try again") { model.retry() }.keyboardShortcut(.defaultAction)
            case .installing:
                Button("Cancel") {}.disabled(true)
            default:
                Button("Cancel") { model.reset(); onDone() }.keyboardShortcut(.cancelAction)
                Button("Install") { Task { await model.install() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canInstall)
            }
        }
    }
}
```

- [ ] **Step 2: Wire it into `LibraryView`**

Add state and the model near the other `@State`s:

```swift
    @State private var showInstall = false
    @State private var installModel = InstallSheetModel(
        paths: ClaudePaths(), github: URLSessionGitHubClient(),
        guesser: FoundationModelsGuesser.isAvailable ? FoundationModelsGuesser() : NoopGuesser(),
        runner: ShellCommandRunner())
```

Append these modifiers after `.navigationTitle("Skills Manager")`:

```swift
        .toolbar {
            ToolbarItem {
                Button { showInstall = true } label: { Label("Install", systemImage: "plus") }
                    .help("Install a skill or plugin from a link or command")
            }
        }
        .sheet(isPresented: $showInstall) {
            InstallSheet(model: installModel) { showInstall = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showInstallSheet)) { _ in showInstall = true }
        .onDrop(of: [.url, .plainText], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let s = object as? String else { return }
                Task { @MainActor in installModel.text = s; showInstall = true }
            }
            return true
        }
```

and at file scope:

```swift
extension Notification.Name { static let showInstallSheet = Notification.Name("SkillsManager.showInstallSheet") }
```

- [ ] **Step 3: File menu item**

In `SkillsManagerApp.swift`, inside `.commands { … }` add:

```swift
            CommandGroup(replacing: .newItem) {
                Button("Install…") { NotificationCenter.default.post(name: .showInstallSheet, object: nil) }
                    .keyboardShortcut("n")
            }
```

- [ ] **Step 4: Build and try it**

Run: `xcodegen generate && xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"`
Expected: `** BUILD SUCCEEDED **`.

Launch against a sandbox so nothing real is installed while you check the flow:

```bash
rm -rf /private/tmp/skills-sandbox && mkdir -p /private/tmp/skills-sandbox/.claude/skills /private/tmp/skills-sandbox/.agents/skills
SKILLS_MANAGER_HOME=/private/tmp/skills-sandbox "build/Build/Products/Debug/Skills Manager.app/Contents/MacOS/Skills Manager" &
```

Expected (verify what you can; report honestly what you could not observe): a "+" toolbar button; ⌘N opens the sheet; pasting `https://github.com/jakubkrehel/skills` shows "Looking…" then a preview with 11 skills; pasting `brew install ripgrep` shows the Homebrew sentence. **Do not click Install** — the sandbox `HOME` is not honored by `npx skills` (it writes to the real `~/.agents`), so a real install is the owner's checkpoint in Task 6. Quit with `pkill -f "Skills Manager"` and `rm -rf /private/tmp/skills-sandbox`.

- [ ] **Step 5: Commit**

```bash
git add App/Install/InstallSheet.swift App/LibraryView.swift App/SkillsManagerApp.swift
git commit -m "feat: Install sheet — paste, verified preview, one-click install

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: README, verification, owner checkpoint

**Files:**
- Modify: `README.md`

- [ ] **Step 1: README**

After the "## Reloading" section add:

```markdown
## Installing

Click **+** in the toolbar (or press ⌘N) and paste a GitHub link, a skills.sh
link, or the install command a README shows. The app checks what it is, shows
you the skills it will add, and installs into Claude Code with one click.
Skills are installed with [`npx skills`](https://skills.sh) and plugins with
`claude plugin`, exactly as you would in a terminal — nothing is hidden.
Requires Node.js for skills.
```

Commit: `docs: README install section` (with the Co-Authored-By line).

- [ ] **Step 2: Full verification**

Run: `cd SkillsManagerCore && swift test 2>&1 | tail -2` → 72 passing.
Run: `rm -rf build && xcodegen generate && xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -derivedDataPath build build 2>&1 | grep -E "warning:|error:|BUILD" | grep -v "DerivedData\|SourcePackages\|appintents"` → `** BUILD SUCCEEDED **`, no app warnings.

- [ ] **Step 3: Owner-verified checkpoint**

Launch `open "build/Build/Products/Debug/Skills Manager.app"` against the real home. Pause for the owner to confirm in their own words:

1. "+" in the toolbar and ⌘N open the sheet; dragging a link onto the window opens it pre-filled.
2. Paste `npx skills add jakubkrehel/skills` → preview lists the better-* skills, all "Already installed" and unchecked; Install is disabled.
3. Paste `https://www.skills.sh/vercel-labs/skills/find-skills` → preview with one preselected skill (already installed on this Mac → unchecked; pick any repo the owner does not have to test a real install, e.g. `https://github.com/anthropics/skills` and choose one skill).
4. Install one skill → progress → "Installed" with a copyable invocation → it appears under Your Skills within seconds with a Source link.
5. Paste the two-line `/plugin marketplace add … / /plugin install …` pair from a plugin README → preview shows the marketplace note; install → plugin appears under Plugins.
6. Paste `brew install ripgrep` → the Homebrew sentence.
7. Nothing jumps when the sheet switches between states.

A non-interactive executor must stop here and report rather than assume success.

- [ ] **Step 4: Finish**

Invoke `superpowers:finishing-a-development-branch`. Expected: PR against `main` titled "Install box: paste a link or command, preview, install", body ending with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
