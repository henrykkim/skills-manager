import Foundation

public struct WhereLine: Sendable, Hashable, Identifiable {
    public var id: String { label + "|" + detail + "|" + (revealURL?.path ?? "") }
    public let label: String
    public let detail: String
    public let revealURL: URL?
    public let syncedAt: Date?     // Claude-account line only; the view formats it relatively
}

/// The detail page's "Where it works" lines (spec §5.2).
public enum WhereItWorks {
    public static func lines(for entry: SkillEntry, lastSynced: Date?, home: URL) -> [WhereLine] {
        entry.locations.map { loc in
            switch loc.skill.source {
            case .account:
                return WhereLine(label: "Claude account", detail: "Synced from your Claude account",
                                 revealURL: nil, syncedAt: lastSynced)
            case .project(_, let subpath):
                let label = subpath.map { "\(loc.tag.label) › \($0)" } ?? loc.tag.label
                let detail: String
                if loc.isIgnored { detail = "Ignored — Claude uses the Global copy" }
                else if loc.differsFromPrimary { detail = "This copy is different from the others" }
                else if let subpath { detail = "Only when Claude is opened in the \(subpath) folder" }
                else { detail = abbreviate(loc.skill.directory, home: home) }
                return WhereLine(label: label, detail: detail, revealURL: loc.skill.directory, syncedAt: nil)
            case .personal, .shared, .plugin:
                return WhereLine(label: loc.tag.label, detail: abbreviate(loc.skill.directory, home: home),
                                 revealURL: loc.skill.directory, syncedAt: nil)
            }
        }
    }

    public static func lines(for entry: PluginEntry) -> [WhereLine] {
        entry.locations
            // Same strict-weak-ordering fix as Library.build: compare (rank, label, id)
            // directly rather than de-duping a 2-element array through LocationTag.sorted.
            .sorted { a, b in
                (a.tag.rank, a.tag.label, a.id) < (b.tag.rank, b.tag.label, b.id)
            }
            .map { loc in
                let detail = switch loc.plugin.scope {
                case .user: "On for all your projects"
                case .project: "Turned on for this project"
                case .cowork: "Installed in Cowork"
                }
                var reveal: URL? = loc.plugin.contentDirectory
                if case .project(let root) = loc.plugin.scope {
                    reveal = root.appending(path: ".claude", directoryHint: .isDirectory)
                }
                return WhereLine(label: loc.tag.label, detail: detail, revealURL: reveal, syncedAt: nil)
            }
    }

    static func abbreviate(_ url: URL, home: URL) -> String {
        let h = Canonical.path(home.path), p = Canonical.path(url.path)
        return p.hasPrefix(h + "/") ? "~" + p.dropFirst(h.count) : p
    }
}
