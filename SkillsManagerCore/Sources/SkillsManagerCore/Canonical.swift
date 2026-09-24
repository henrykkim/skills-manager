import Foundation

/// Canonical filesystem paths via realpath(3). Foundation's
/// resolvingSymlinksInPath() strips /private and is NOT canonical — never use
/// it for comparisons.
public enum Canonical {
    public static func path(_ path: String) -> String {
        if let rp = realpath(path, nil) {
            defer { free(rp) }
            return String(cString: rp)
        }
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent().path
        guard parent != path, !parent.isEmpty else { return path }
        return (self.path(parent) as NSString).appendingPathComponent(url.lastPathComponent)
    }

    public static func url(_ url: URL) -> URL {
        URL(fileURLWithPath: path(url.path), isDirectory: url.hasDirectoryPath)
    }
}
