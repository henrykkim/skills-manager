import Foundation

/// Pure planning for the Recommended sheet (spec §6): which catalog items
/// to install, in catalog order, and which skill folders each one needs.
/// Resolution (network) and execution (processes) live elsewhere.
public enum RecommendationPlan {
    public struct Step: Sendable, Equatable {
        public let itemID: String
        public let preview: InstallPreview
        /// Skill folders to pass to `Installer`; empty for plugins.
        public let folders: [String]
        public init(itemID: String, preview: InstallPreview, folders: [String]) {
            self.itemID = itemID; self.preview = preview; self.folders = folders
        }
    }

    /// A plugin is installed when the registry says so. A skills repo is
    /// installed when it has at least one valid skill and all of them are
    /// on disk; invalid skills are ignored (they could never be installed).
    public static func isInstalled(_ preview: InstallPreview) -> Bool {
        switch preview.kind {
        case .plugin:
            return preview.isPluginInstalled
        case .skillsRepo:
            let valid = preview.skills.filter(\.isValid)
            return !valid.isEmpty && valid.allSatisfy(\.isInstalled)
        }
    }

    /// Valid skills not yet on disk, in preview order. Empty for plugins.
    public static func folders(toInstallFrom preview: InstallPreview) -> [String] {
        guard preview.kind == .skillsRepo else { return [] }
        return preview.skills.filter { $0.isValid && !$0.isInstalled }.map(\.folder)
    }

    /// One step per selected, resolved, not-yet-installed item, in catalog order.
    public static func make(items: [RecommendationItem], previews: [String: InstallPreview],
                            selected: Set<String>) -> [Step] {
        items.compactMap { item in
            guard selected.contains(item.id), let preview = previews[item.id], !isInstalled(preview) else { return nil }
            let folders = folders(toInstallFrom: preview)
            if preview.kind == .skillsRepo, folders.isEmpty { return nil }
            return Step(itemID: item.id, preview: preview, folders: folders)
        }
    }
}
