import SwiftUI
import SkillsManagerCore

struct PluginDetailView: View {
    let plugin: Plugin

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header

                if !plugin.commands.isEmpty {
                    SectionCard(title: "Commands") {
                        ForEach(plugin.commands) { command in
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                InvocationChip(invocation: command.invocation)
                                if let hint = command.argumentHint {
                                    LabeledContent("Arguments", value: hint)
                                        .font(.callout)
                                }
                                if let summary = command.summary {
                                    Text(summary)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.bottom, Spacing.sm)
                        }
                    }
                }

                if !plugin.skills.isEmpty {
                    SectionCard(title: "Bundled skills") {
                        ForEach(plugin.skills) { skill in
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                InvocationChip(invocation: Invocation.string(for: skill))
                                if let summary = skill.summary {
                                    Text(summary)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                            }
                            .padding(.bottom, Spacing.sm)
                        }
                    }
                }

                SectionCard(title: "Details") {
                    LabeledContent("Status", value: plugin.isEnabled ? "Enabled" : "Disabled")
                    if let version = plugin.version {
                        LabeledContent("Version", value: version)
                    }
                    LabeledContent("Marketplace", value: plugin.marketplace)
                    if let provenance = plugin.provenance {
                        LabeledContent("From", value: provenance)
                    }
                    if let updated = plugin.lastUpdated {
                        LabeledContent("Last updated",
                                       value: updated.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .navigationTitle(plugin.name)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Text(plugin.name).font(.detailTitle)
                KindBadge(text: "Plugin", tint: .purple)
                StatusDot(isEnabled: plugin.isEnabled)
            }
            if let summary = plugin.summary {
                Text(summary).foregroundStyle(.secondary)
            }
        }
    }
}
