import Foundation

/// Cowork keeps its own plugin set per account, in Claude Code's plugin layout:
/// local-agent-mode-sessions/<account>/<org>/cowork_plugins/ plus
/// cowork_settings.json (enabledPlugins).
public enum CoworkPlugins {
    public static func load(sessionsDir: URL) -> PluginLoadResult {
        let fm = FileManager.default
        func children(_ u: URL) -> [URL] {
            (try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        }
        var result = PluginLoadResult()
        var seen = Set<String>()
        for a in children(sessionsDir).sorted(by: { $0.path < $1.path }) where a.lastPathComponent != "skills-plugin" {
            for b in children(a).sorted(by: { $0.path < $1.path }) {
                let store = PluginStore(root: b.appending(path: "cowork_plugins", directoryHint: .isDirectory))
                guard fm.fileExists(atPath: store.installedPluginsFile.path) else { continue }
                let enabled = SettingsReader.enabledPlugins(settingsFile: b.appending(path: "cowork_settings.json"))
                let loaded = PluginRegistry.loadPlugins(store: store, enabledPlugins: enabled, scope: .cowork, only: nil)
                result.issues += loaded.issues
                for plugin in loaded.plugins where seen.insert(plugin.pluginID).inserted {
                    result.plugins.append(plugin)
                }
            }
        }
        return result
    }
}
