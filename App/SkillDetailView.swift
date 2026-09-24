import AppKit
import SwiftUI
import SkillsManagerCore

struct SkillDetailView: View {
    let skill: Skill
    let parentPlugin: Plugin?
    // Task 10 stubs: wired up by the detail-view task.
    let entry: SkillEntry?
    let accountLastSynced: Date?

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
                                .help(skill.directory.path)
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([skill.directory])
                            }
                            .buttonStyle(.link)
                        }
                    }
                    LabeledContent("Source") { sourceView }
                    if let installed = skill.installedAt ?? parentPlugin?.installedAt {
                        LabeledContent("Installed") {
                            Text(installed.formatted(date: .abbreviated, time: .omitted)).font(.metadata)
                        }
                    }
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .navigationTitle(skill.displayName)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(skill.displayName).font(.detailTitle)
                switch skill.source {
                case .personal: KindBadge(text: "Skill", tint: .gray)
                case .shared: KindBadge(text: "Shared", tint: .teal)
                case .plugin: KindBadge(text: "Plugin Skill", tint: .purple)
                case .project: KindBadge(text: "Project Skill", tint: .teal)
                case .account: KindBadge(text: "Claude Account", tint: .blue)
                }
                if let updated = skill.updatedAt ?? skill.lastModified {
                    UpdatedLabel(date: updated)
                }
            }
            if let summary = skill.summary {
                Text(summary).foregroundStyle(.secondary)
            }
        }
    }

    /// A link when we know where the skill came from; honest plain text otherwise.
    @ViewBuilder
    private var sourceView: some View {
        switch skill.source {
        case .personal, .shared:
            if let url = skill.sourceURL {
                SourceLink(label: skill.sourceLabel ?? url.absoluteString, url: url)
            } else if case .personal = skill.source {
                Text("Your skills folder (~/.claude/skills)")
            } else {
                Text("Shared skills folder (~/.agents/skills)")
            }
        case .project(let root, _):
            Text("Project folder (\(root.lastPathComponent))")
        case .account:
            Text("Your Claude account")
        case .plugin:
            if let plugin = parentPlugin, let url = plugin.homepageURL ?? plugin.marketplaceURL {
                SourceLink(label: "Plugin \(plugin.name)", url: url)
            } else if let plugin = parentPlugin {
                Text("Plugin \(plugin.name)")
            } else {
                Text("Plugin")
            }
        }
    }
}
