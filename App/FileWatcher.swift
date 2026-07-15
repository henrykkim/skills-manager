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
    private let targetPrefixes: [String]

    init(root: URL, targets: [URL], onChange: @escaping @Sendable () -> Void) {
        debouncer = Debouncer(delay: 1.0, queue: .main, action: onChange)
        // FSEvents delivers canonical paths — resolve symlinks up front or a
        // root like /tmp (→ /private/tmp) silently never matches.
        let rootPath = root.resolvingSymlinksInPath().path
        targetPrefixes = targets.map { $0.resolvingSymlinksInPath().path }

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

    /// An event is relevant if it happened under a target, or at/above one
    /// (a parent-directory event may mean the target itself appeared).
    private func isRelevant(_ eventPath: String) -> Bool {
        targetPrefixes.contains { target in
            eventPath.hasPrefix(target) || target.hasPrefix(eventPath)
        }
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
