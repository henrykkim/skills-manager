import Foundation

public struct Project: Sendable, Hashable, Identifiable {
    public var id: String { root.path }
    public let root: URL            // canonical
    public let displayName: String  // folder name, disambiguated by parent when needed

    public init(root: URL, displayName: String) {
        self.root = root
        self.displayName = displayName
    }
}

public struct ProjectDiscovery: Sendable {
    public var projects: [Project]
    public var issues: [ParseIssue]

    public init(projects: [Project] = [], issues: [ParseIssue] = []) {
        self.projects = projects
        self.issues = issues
    }
}

struct SourceFormatError: Error {}

/// Finds every folder Claude has been given access to (spec §4.1–4.2).
/// All three sources are internal Claude files: read leniently, decode only
/// the path fields.
public enum ProjectSources {
    public static func terminalFolders(claudeJSON: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: claudeJSON.path) else { return [] }
        let data = try Data(contentsOf: claudeJSON)
        // Top-level keys only; project values are never inspected.
        struct File: Decodable {
            let projects: [String: IgnoredValue]?
        }
        let file = try JSONDecoder().decode(File.self, from: data)
        return file.projects.map { Array($0.keys) } ?? []
    }

    public static func codeTabFolders(sessionsDir: URL) throws -> [String] {
        struct Session: Decodable { let cwd: String?; let originCwd: String? }
        return try decodeAll(sessionFiles(in: sessionsDir), as: Session.self) { [$0.cwd, $0.originCwd].compactMap { $0 } }
    }

    public static func coworkFolders(sessionsDir: URL) throws -> [String] {
        struct Session: Decodable { let userSelectedFolders: [String]? }
        let files = sessionFiles(in: sessionsDir, skipping: ["skills-plugin"])
        return try decodeAll(files, as: Session.self) { $0.userSelectedFolders ?? [] }
    }

    /// `<dir>/<account>/<org>/local_*.json` — exactly that depth, nothing deeper.
    public static func sessionFiles(in dir: URL, skipping: Set<String> = []) -> [URL] {
        let fm = FileManager.default
        func children(_ u: URL) -> [URL] {
            (try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        }
        var files: [URL] = []
        for a in children(dir) where !skipping.contains(a.lastPathComponent) {
            for b in children(a) {
                files += children(b).filter {
                    $0.lastPathComponent.hasPrefix("local_") && $0.pathExtension == "json"
                }
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    /// One bad session file is skipped; if every file fails, the source is broken.
    private static func decodeAll<T: Decodable>(_ files: [URL], as type: T.Type,
                                                 paths: (T) -> [String]) throws -> [String] {
        var result: [String] = []
        var failures = 0
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let session = try? JSONDecoder().decode(type, from: data) else {
                failures += 1
                continue
            }
            result += paths(session)
        }
        if !files.isEmpty && failures == files.count { throw SourceFormatError() }
        return result
    }

    public static func normalize(_ raw: [String], home: URL) -> [Project] {
        let fm = FileManager.default
        let homePath = Canonical.path(home.path)
        var seen = Set<String>()
        var roots: [URL] = []
        for path in raw {
            var p = path
            if let r = p.range(of: "/.claude/worktrees/") { p = String(p[..<r.lowerBound]) }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue else { continue }
            let canon = Canonical.path(p)
            guard canon != homePath, canon != "/", seen.insert(canon).inserted else { continue }
            roots.append(URL(fileURLWithPath: canon, isDirectory: true))
        }
        let nameCounts = Dictionary(grouping: roots, by: \.lastPathComponent).mapValues(\.count)
        return roots.map { root in
            let base = root.lastPathComponent
            let name = (nameCounts[base] ?? 0) > 1
                ? "\(base) (\(root.deletingLastPathComponent().lastPathComponent))"
                : base
            return Project(root: root, displayName: name)
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    public static func discover(paths: ClaudePaths, addedProjects: [URL]) -> ProjectDiscovery {
        var raw: [String] = []
        var issues: [ParseIssue] = []
        func collect(_ message: String, _ location: URL, _ read: () throws -> [String]) {
            do { raw += try read() } catch {
                issues.append(ParseIssue(location: location, detail: message))
            }
        }
        collect("Couldn't read Claude Code's project list. Some projects may be missing.", paths.claudeJSON) {
            try terminalFolders(claudeJSON: paths.claudeJSON)
        }
        collect("Couldn't read the Claude app's Code sessions. Some projects may be missing.", paths.codeSessionsDir) {
            try codeTabFolders(sessionsDir: paths.codeSessionsDir)
        }
        collect("Couldn't read Cowork's folder list. Cowork items may be missing.", paths.coworkSessionsDir) {
            try coworkFolders(sessionsDir: paths.coworkSessionsDir)
        }
        raw += addedProjects.map(\.path)
        return ProjectDiscovery(projects: normalize(raw, home: paths.home), issues: issues)
    }
}

/// Decodes any JSON value and throws it away — lets us read dictionary keys
/// without ever materializing the values.
struct IgnoredValue: Decodable {
    init(from decoder: Decoder) throws {}
}
