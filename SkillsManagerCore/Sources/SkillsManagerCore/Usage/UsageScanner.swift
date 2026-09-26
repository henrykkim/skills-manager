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
