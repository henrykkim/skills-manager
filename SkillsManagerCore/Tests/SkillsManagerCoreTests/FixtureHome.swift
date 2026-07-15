import Foundation

struct FixtureHomeError: Error, CustomStringConvertible {
    let description: String
}

enum FixtureHome {
    /// Copies the bundled fixture tree to a unique temp dir, renames
    /// dot-claude/dot-agents to real hidden folders, writes the hidden plugin
    /// manifests, and creates the personal→shared symlink. Caller deletes when done.
    static func make() throws -> URL {
        let fm = FileManager.default
        guard let source = Bundle.module.url(forResource: "home", withExtension: nil, subdirectory: "Fixtures") else {
            throw FixtureHomeError(description: "Fixtures/home resource not found in test bundle")
        }
        let dest = fm.temporaryDirectory.appending(path: "fixture-home-\(UUID().uuidString)")
        try fm.copyItem(at: source, to: dest)
        do {
            try rename(dest.appending(path: "dot-claude"), to: ".claude")
            try rename(dest.appending(path: "dot-agents"), to: ".agents")

            // Hidden files don't reliably survive SPM's resource copying, and
            // symlinks can't be bundled at all — write both here instead.
            try writePluginManifest(home: dest, marketplace: "test-market", plugin: "demo-plugin",
                                    version: "1.2.0", description: "Demo plugin for tests")
            try writePluginManifest(home: dest, marketplace: "test-market", plugin: "disabled-plugin",
                                    version: "0.1.0", description: "Disabled in settings")
            // The shape `npx skills add` creates: canonical copy in ~/.agents/skills,
            // symlinked into ~/.claude/skills so Claude Code sees it.
            try fm.createSymbolicLink(
                at: dest.appending(path: ".claude/skills/shared-skill"),
                withDestinationURL: dest.appending(path: ".agents/skills/shared-skill"))
        } catch {
            // Don't leak a half-built fixture the caller never got a URL for.
            try? fm.removeItem(at: dest)
            throw error
        }
        return dest
    }

    private static func rename(_ url: URL, to newName: String) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            throw FixtureHomeError(description: "Fixture rename source missing: \(url.path)")
        }
        try fm.moveItem(at: url, to: url.deletingLastPathComponent().appending(path: newName))
    }

    private static func writePluginManifest(home: URL, marketplace: String, plugin: String,
                                            version: String, description: String) throws {
        let dir = home.appending(
            path: ".claude/plugins/cache/\(marketplace)/\(plugin)/\(version)/.claude-plugin")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = #"{ "name": "\#(plugin)", "version": "\#(version)", "description": "\#(description)" }"#
        try json.write(to: dir.appending(path: "plugin.json"), atomically: true, encoding: .utf8)
    }
}
