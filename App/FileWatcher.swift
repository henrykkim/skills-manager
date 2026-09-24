import CoreServices
import Foundation
import SkillsManagerCore

/// Watches one stable root (the home directory) via FSEvents and reloads only
/// for events under the target paths. Watching the root — not the targets —
/// means a target created after launch (~/.agents on a fresh machine) is still
/// picked up, and high-churn siblings (~/.claude/projects, history) are ignored.
///
/// Lifetime: create once and keep for the app's life — the FSEvents context
/// holds an unretained self, so this class must not be torn down while events
/// may still be in flight.
final class FileWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let debouncer: Debouncer
    private let queue = DispatchQueue(label: "com.henrykkim.skillsmanager.fsevents")
    /// Only touched on `queue` (FSEvents callbacks run there; setTargets hops there).
    private var targetPrefixes: [String]

    init(root: URL, targets: [URL], delay: TimeInterval = 1.0, onChange: @escaping @Sendable () -> Void) {
        debouncer = Debouncer(delay: delay, queue: .main, action: onChange)
        // FSEvents delivers canonical paths (realpath-style, e.g. /private/tmp/…).
        // Foundation's resolvingSymlinksInPath() is NOT canonical — it strips
        // /private, so /tmp-rooted watches would silently never match. Use
        // realpath(3) via canonicalize(); nonexistent targets canonicalize
        // their nearest existing ancestor.
        let rootPath = Self.canonicalize(root)
        targetPrefixes = targets.map(Self.canonicalize)

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
            if paths.contains(where: { watcher.isRelevant($0) }) {
                watcher.debouncer.call()
            }
        }
        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [rootPath] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    /// Replaces the watched targets (project folders come and go between loads).
    func setTargets(_ targets: [URL]) {
        let prefixes = targets.map(Self.canonicalize)
        queue.async { [self] in targetPrefixes = prefixes }
    }

    /// True canonical path via realpath(3) — resolvingSymlinksInPath() strips
    /// /private (making /tmp roots never match FSEvents' canonical output).
    private static func canonicalize(_ url: URL) -> String {
        if let rp = realpath(url.path, nil) {
            defer { free(rp) }
            return String(cString: rp)
        }
        let parent = url.deletingLastPathComponent()
        guard parent.path != url.path else { return url.path }
        return canonicalize(parent) + "/" + url.lastPathComponent
    }

    /// An event is relevant if it happened in or under a target, or in a
    /// target's direct parent (the target itself may have just appeared).
    private func isRelevant(_ eventPath: String) -> Bool {
        targetPrefixes.contains { WatchMatch.isRelevant(eventPath: eventPath, target: $0) }
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
