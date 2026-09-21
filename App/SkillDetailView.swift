import AppKit
import SwiftUI
import SkillsManagerCore

struct SkillDetailView: View {
    let skill: Skill

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header

                SectionCard(title: "How to use") {
                    InvocationChip(invocation: Invocation.string(for: skill))
                    if let hint = skill.argumentHint {
                        LabeledContent("Arguments", value: hint)
                            .font(.callout)
                    }
                    Text(Invocation.availabilityLabel(for: skill))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let whenToUse = skill.whenToUse {
                    SectionCard(title: "When to use") {
                        Text(whenToUse).font(.callout)
                    }
                }

                SectionCard(title: "Details") {
                    LabeledContent("Location") {
                        HStack(spacing: Spacing.sm) {
                            Text(skill.directory.path)
                                .truncationMode(.middle)
                                .lineLimit(1)
                                .textSelection(.enabled)
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([skill.directory])
                            }
                            .buttonStyle(.link)
                        }
                    }
                    if let modified = skill.lastModified {
                        LabeledContent("Last modified",
                                       value: modified.formatted(date: .abbreviated, time: .shortened))
                    }
                    LabeledContent("Source", value: sourceLabel)
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .navigationTitle(skill.displayName)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Text(skill.displayName).font(.detailTitle)
                switch skill.source {
                case .personal: KindBadge(text: "Skill", tint: .blue)
                case .shared: KindBadge(text: "Shared", tint: .teal)
                case .plugin: KindBadge(text: "Plugin Skill", tint: .purple)
                }
            }
            if let summary = skill.summary {
                Text(summary).foregroundStyle(.secondary)
            }
        }
    }

    private var sourceLabel: String {
        switch skill.source {
        case .personal: "Your skills folder (~/.claude/skills)"
        case .shared: "Shared skills folder (~/.agents/skills)"
        case .plugin(let pluginID): "Plugin \(pluginID)"
        }
    }
}
