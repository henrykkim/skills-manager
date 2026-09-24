import AppKit
import SwiftUI
import SkillsManagerCore

/// "Where it works" on skill and plugin detail pages: one line per place
/// the item is installed, with a way to find it on disk.
struct WhereItWorksSection: View {
    let lines: [WhereLine]

    var body: some View {
        SectionCard(title: "Where it works") {
            ForEach(lines) { line in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Text(line.label)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                            // The label names the place; the detail gives way first.
                            .layoutPriority(1)
                        Text(detail(line))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .help(detail(line))
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: Spacing.sm)
                    if let url = line.revealURL {
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            .buttonStyle(.link)
                            // Several of these can sit in one card; VoiceOver needs to know which.
                            .accessibilityLabel("Reveal \(line.label) in Finder")
                    }
                }
            }
        }
    }

    private func detail(_ line: WhereLine) -> String {
        guard let synced = line.syncedAt else { return line.detail }
        return line.detail + " · last synced " + synced.formatted(.relative(presentation: .named))
    }
}
