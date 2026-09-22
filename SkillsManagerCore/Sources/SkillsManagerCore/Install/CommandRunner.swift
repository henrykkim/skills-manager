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

/// Lock-protected flag set by the timeout work item and read from the process's
/// termination handler. Swift 6 strict concurrency won't let a `@Sendable`
/// closure capture `DispatchWorkItem` (it isn't `Sendable`), so the timeout
/// signal is carried through this small `@unchecked Sendable` box instead of
/// inspecting `timer.isCancelled` inside `terminationHandler`.
private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func markTimedOut() { lock.lock(); flag = true; lock.unlock() }
    var didTimeOut: Bool { lock.lock(); defer { lock.unlock() }; return flag }
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

            let timedOutFlag = TimeoutFlag()
            let timer = DispatchWorkItem {
                if process.isRunning {
                    timedOutFlag.markTimedOut()
                    process.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
            process.terminationHandler = { p in
                // Note: we deliberately don't call timer.cancel() here — Swift 6
                // strict concurrency forbids a `@Sendable` closure (terminationHandler)
                // from capturing `DispatchWorkItem`, which isn't Sendable. Letting the
                // timer fire after a normal exit is harmless: it checks
                // process.isRunning (false by then) and no-ops.
                let o = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let e = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                continuation.resume(returning: CommandResult(status: p.terminationStatus, stdout: o, stderr: e, timedOut: timedOutFlag.didTimeOut))
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
