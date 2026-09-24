import Foundation
@testable import SkillsManagerCore

/// Builds throwaway directory trees for reader tests. Root is canonical
/// (realpath) so it compares equal to what the readers produce.
struct TempTree {
    let root: URL

    init() throws {
        let raw = FileManager.default.temporaryDirectory.appending(path: "temptree-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        root = Canonical.url(raw)
    }

    func url(_ path: String) -> URL { root.appending(path: path) }

    @discardableResult
    func mkdir(_ path: String) throws -> URL {
        let u = url(path)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    @discardableResult
    func write(_ text: String, to path: String) throws -> URL {
        let u = url(path)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: u, atomically: true, encoding: .utf8)
        return u
    }

    /// Writes `<dir>/<name>/SKILL.md` with valid frontmatter.
    @discardableResult
    func skill(_ name: String, in dir: String, body: String = "Body") throws -> URL {
        try write("---\nname: \(name)\ndescription: Test skill \(name)\n---\n\(body)\n",
                  to: "\(dir)/\(name)/SKILL.md")
        return url("\(dir)/\(name)")
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
