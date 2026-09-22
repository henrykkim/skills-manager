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
                    if let author = plugin.authorName {
                        LabeledContent("Author") {
                            if let url = plugin.authorURL {
                                SourceLink(label: author, url: url)
                            } else {
                                Text(author)
                            }
                        }
                    }
                    if let source = sourceLink {
                        LabeledContent("Source") { source }
                    }
                    LabeledContent("Marketplace") {
                        if let url = plugin.marketplaceURL {
                            SourceLink(label: marketplaceName, url: url)
                        } else {
                            Text(marketplaceName)
                        }
                    }
                    if let version = plugin.version {
                        LabeledContent("Version") { Text(version).font(.metadata) }
                    }
                    if let installed = plugin.installedAt {
                        LabeledContent("Installed") {
                            Text(installed.formatted(date: .abbreviated, time: .omitted)).font(.metadata)
                        }
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
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(plugin.name).font(.detailTitle)
                KindBadge(text: "Plugin", tint: .purple)
                StatusDot(isEnabled: plugin.isEnabled)
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 3 }
                if let updated = plugin.lastUpdated {
                    UpdatedLabel(date: updated)
                }
            }
            if let summary = plugin.summary {
                Text(summary).foregroundStyle(.secondary)
            }
        }
    }

    /// Homepage first, then the marketplace repo — never a dead row.
    private var sourceLink: SourceLink? {
        if let url = plugin.homepageURL {
            return SourceLink(label: displayLabel(for: url), url: url)
        }
        if let url = plugin.marketplaceURL {
            return SourceLink(label: displayLabel(for: url), url: url)
        }
        return nil
    }

    /// "Anthropic official" reads better than "claude-plugins-official"; everything else as-is.
    private var marketplaceName: String {
        plugin.marketplace == "claude-plugins-official" ? "Anthropic official" : plugin.marketplace
    }

    /// "github.com/owner/repo" — host plus path, no scheme noise.
    private func displayLabel(for url: URL) -> String {
        let host = url.host() ?? ""
        let path = url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? host : "\(host)/\(path)"
    }
}
