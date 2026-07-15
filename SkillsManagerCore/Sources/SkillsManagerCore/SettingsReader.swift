import Foundation

/// Reads the pieces of ~/.claude/settings.json we care about.
/// Read-only in this plan: writes happen through the `claude` CLI in later plans (spec §6.4).
public enum SettingsReader {
    public static func enabledPlugins(settingsFile: URL) -> [String: Bool] {
        guard let data = try? Data(contentsOf: settingsFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let map = json["enabledPlugins"] as? [String: Bool] else {
            return [:]
        }
        return map
    }
}
