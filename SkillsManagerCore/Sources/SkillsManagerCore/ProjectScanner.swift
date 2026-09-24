import Foundation

public struct ProjectScanResult: Sendable {
    public var skills: [Skill] = []
    public var plugins: [Plugin] = []
    public var issues: [ParseIssue] = []
}

/// Everything one project folder contributes (spec §4.3).
public enum ProjectScanner {
    public static let maxDepth = 4
    public static let skippedFolders: Set<String> = ["node_modules", ".git", ".build", "DerivedData", "Pods", "vendor"]

    public static func scan(_ project: Project, paths: ClaudePaths) -> ProjectScanResult {
        var result = ProjectScanResult()
        let dirs: [(dir: URL, subpath: String?)]
        do {
            dirs = try skillDirectories(in: project.root)
        } catch {
            result.issues.append(ParseIssue(
                location: project.root,
                detail: "Skills Manager can't open \(project.displayName). Allow it in System Settings → Privacy & Security → Files and Folders."))
            return result
        }
        for (dir, subpath) in dirs {
            let scan = SkillScanner.scan(directory: dir, source: .project(root: project.root, subpath: subpath),
                                         skipOnlineOnly: true)
            result.skills += scan.skills
            result.issues += scan.issues
        }

        var seenPlugins = Set<String>()
        for name in ["settings.json", "settings.local.json"] {
            let file = project.root.appending(path: ".claude/\(name)")
            guard LocalFile.isDownloaded(file) else { continue }
            let enabled = SettingsReader.enabledPlugins(settingsFile: file).filter(\.value)
            let wanted = Set(enabled.keys).subtracting(seenPlugins)
            guard !wanted.isEmpty else { continue }
            let loaded = PluginRegistry.loadPlugins(store: paths.userPluginStore, enabledPlugins: enabled,
                                                    scope: .project(root: project.root), only: wanted)
            result.plugins += loaded.plugins
            result.issues += loaded.issues
            seenPlugins.formUnion(loaded.plugins.map(\.pluginID))
        }
        return result
    }

    /// `.claude/skills` folders in the project root and in subfolders up to
    /// `maxDepth` levels down. Only folder names are checked; nothing is read.
    /// Throws only when the project root itself can't be listed.
    public static func skillDirectories(in root: URL) throws -> [(dir: URL, subpath: String?)] {
        let fm = FileManager.default
        func skillsDir(_ folder: URL) -> URL? {
            let d = folder.appending(path: ".claude/skills", directoryHint: .isDirectory)
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: d.path, isDirectory: &isDir) && isDir.boolValue ? d : nil
        }
        func subfolders(_ folder: URL) throws -> [URL] {
            try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                       options: [.skipsHiddenFiles])
                .filter { url in
                    guard !skippedFolders.contains(url.lastPathComponent),
                          let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
                    return v.isDirectory == true && v.isSymbolicLink != true   // no symlink loops
                }
                .sorted { $0.path < $1.path }
        }

        var found: [(dir: URL, subpath: String?)] = []
        if let d = skillsDir(root) { found.append((d, nil)) }
        var frontier = try subfolders(root)          // throws if root is unreadable
        var depth = 1
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        while !frontier.isEmpty && depth <= maxDepth {
            var next: [URL] = []
            for folder in frontier {
                if let d = skillsDir(folder) {
                    found.append((d, String(folder.path.dropFirst(rootPrefix.count))))
                }
                if depth < maxDepth { next += (try? subfolders(folder)) ?? [] }
            }
            frontier = next
            depth += 1
        }
        return found
    }
}
