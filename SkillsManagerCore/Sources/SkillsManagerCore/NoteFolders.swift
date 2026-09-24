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
