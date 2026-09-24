import SwiftUI
import SkillsManagerCore

/// One place a skill or plugin works: Global, Claude account, Cowork, or a project.
struct TagPill: View {
    let tag: LocationTag

    var body: some View {
        KindBadge(text: tag.label, tint: tint)
            // A badge never wraps; a long project name truncates instead,
            // and the full name stays reachable on hover.
            .lineLimit(1)
            .truncationMode(.tail)
            .help(tag.isProject ? tag.label : "")
    }

    private var tint: Color {
        switch tag {
        case .global: .gray
        case .account: .blue
        case .cowork: .purple
        case .project: .teal
        }
    }
}

/// Dashed "Not a skill" tag for markdown notes.
struct NotASkillTag: View {
    var body: some View {
        Text("Not a skill")
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2])).foregroundStyle(.secondary))
            .foregroundStyle(.secondary)
            .help("A markdown file you added. Claude doesn't run it on its own.")
    }
}

/// Every non-project tag, two project tags, then "+N". Hover shows the rest
/// as a tooltip; click (or keyboard) opens a popover.
struct LocationTags: View {
    let tags: [LocationTag]
    @State private var showAll = false

    var body: some View {
        let split = TagLayout.split(tags)
        HStack(spacing: Spacing.xs) {
            ForEach(split.shown, id: \.self) { tag in
                TagPill(tag: tag)
                    // Global/account/Cowork are short and always whole;
                    // only project names give way when the row is narrow.
                    .fixedSize(horizontal: !tag.isProject, vertical: false)
            }
            if !split.overflow.isEmpty {
                let names = split.overflow.map(\.label).joined(separator: ", ")
                Button("+\(split.overflow.count)") { showAll.toggle() }
                    .buttonStyle(.plain)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(.tertiary))
                    .contentShape(Capsule())
                    .fixedSize()
                    .layoutPriority(1)
                    .help("Also in \(names)")
                    .accessibilityLabel("Also in \(names)")
                    .accessibilityHint("Shows every other project")
                    .popover(isPresented: $showAll, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Also in").font(.cardLabel).foregroundStyle(.secondary)
                            ForEach(split.overflow, id: \.self) { Text($0.label) }
                        }
                        .padding(Spacing.md)
                    }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Works in")
    }
}
