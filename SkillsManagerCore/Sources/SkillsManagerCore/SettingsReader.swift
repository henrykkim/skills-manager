import Foundation

/// Reads the pieces of ~/.claude/settings.json we care about.
/// Read-only in this plan: writes happen through the `claude` CLI in later plans (spec §6.4).
public enum SettingsReader {
    public static func enabledPlugins(settingsFile: URL) -> [String: Bool] {
        guard let data = try? Data(contentsOf: settingsFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["enabledPlugins"] as? [String: Any] else {
            return [:]
        }
        // Per-entry: keep Bool values, drop anything else so one bad entry
        // can't wipe the whole map. (JSON 1/0 bridges to NSNumber, which
        // casts to Bool — that coercion is acceptable.)
        return raw.compactMapValues { $0 as? Bool }
    }
}
