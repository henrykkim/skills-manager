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
        // NSLock's raw lock()/unlock() are unavailable from async contexts on this
        // SDK; withLock is the Swift-only synchronous wrapper and is not annotated
        // that way, so it works here while keeping the same synchronous critical section.
        lock.withLock {
            calls.append(argv)
            return results.isEmpty ? CommandResult(status: 0, stdout: "", stderr: "", timedOut: false) : results.removeFirst()
        }
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
    #expect(argv == [["npx", "-y", "skills", "add", "o/r", "-g", "-y", "-a", "claude-code", "-s", "a", "c"]])
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
    #expect(FailureCopy.sentence(for: r("something odd"), marketplace: nil) == "The installer reported a problem. Show Details for what it said.")
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
