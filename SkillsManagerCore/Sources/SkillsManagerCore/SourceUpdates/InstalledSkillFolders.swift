import Foundation

public enum InstalledSkillFolders {
    /// Folder names present in personalSkillsDir or sharedSkillsDir (symlinks count, dotfiles skipped).
    public static func names(paths: ClaudePaths) -> Set<String> {
        let fm = FileManager.default
        var names = Set<String>()
        for dir in [paths.personalSkillsDir, paths.sharedSkillsDir] {
            for entry in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where !entry.hasPrefix(".") {
                names.insert(entry)
            }
        }
        return names
    }
}
