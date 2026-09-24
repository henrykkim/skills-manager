import Foundation

public enum LocalFile {
    /// False for a cloud-synced file (iCloud Drive, Dropbox, OneDrive…) whose
    /// contents live only online. Reading such a file would trigger a
    /// download, which the app must never do (spec §4.3). Non-cloud files → true.
    public static func isDownloaded(_ url: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isUbiquitousItem == true,
              let status = values.ubiquitousItemDownloadingStatus else { return true }
        return status == .current || status == .downloaded
    }
}
