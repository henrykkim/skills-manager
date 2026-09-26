import Foundation

/// The one file this feature writes (spec §5). A store that fails to decode
/// is treated as empty so the next scan rebuilds it (spec §9).
public enum UsageStoreFile {
    public static func load(at url: URL) -> UsageStoreData {
        guard let data = try? Data(contentsOf: url) else { return UsageStoreData() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(UsageStoreData.self, from: data)) ?? UsageStoreData()
    }

    public static func save(_ store: UsageStoreData, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(store).write(to: url, options: .atomic)
    }

    public static func delete(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
