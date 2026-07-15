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
            if let modified = skill.lastModified {
                Text("Updated \(modified.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct PluginRow: View {
    let plugin: Plugin

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
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
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
        if let updated = plugin.lastUpdated {
            parts.append("updated \(updated.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }
}
