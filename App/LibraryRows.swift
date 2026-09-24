import SwiftUI
import SkillsManagerCore

struct SkillRow: View {
    let skill: Skill

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(skill.displayName)
            if let summary = skill.summary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SkillEntryRow: View {
    let entry: SkillEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text(entry.skill.displayName)
                    if !entry.skill.isEnabled {
                        // Same word the plugin rows use (StatusDot).
                        Text("Disabled").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if let summary = entry.skill.summary {
                    Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            HStack(spacing: Spacing.sm) {
                LocationTags(tags: entry.tags)
                if entry.copiesDiffer {
                    Text("Copies differ")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .help("This skill is in more than one place and the copies aren't identical. The details show which one Claude uses.")
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct NoteRow: View {
    let file: NoteFile

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(file.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(file.name)
            Spacer(minLength: Spacing.sm)
            NotASkillTag()
        }
        .padding(.vertical, 2)
    }
}

struct PluginRow: View {
    let entry: PluginEntry
    private var plugin: Plugin { entry.plugin }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.name)
                if let summary = plugin.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !caption.isEmpty {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                LocationTags(tags: entry.tags).padding(.top, 2)
            }
            Spacer()
            StatusDot(isEnabled: plugin.isEnabled)
        }
        .padding(.vertical, 2)
    }

    // Skills and commands are different things — never merge their counts.
    private var caption: String {
        var parts: [String] = []
        if let provenance = plugin.provenance { parts.append(provenance) }
        if let version = plugin.version { parts.append("v\(version)") }
        if !plugin.skills.isEmpty {
            parts.append("\(plugin.skills.count) skill\(plugin.skills.count == 1 ? "" : "s")")
        }
        if !plugin.commands.isEmpty {
            parts.append("\(plugin.commands.count) command\(plugin.commands.count == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }
}
