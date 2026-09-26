import SwiftUI
import SkillsManagerCore

/// The Usage card on a skill's detail page (spec §7). `summary == nil` means never used.
struct UsageSection: View {
    let skill: Skill
    let summary: UsageSummary?
    let window: UsageWindow
    let isAccountSkill: Bool
    /// Canonical project root path → display name, from the inventory.
    let projectNames: [String: String]

    var body: some View {
        SectionCard(title: "Usage") {
            HStack {
                Spacer()
                Text("Counts from Claude Code and Cowork sessions")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if let summary {
                statTiles(for: summary)
                Divider()
                Text("By project")
                    .font(.cardLabel)
                    .foregroundStyle(.secondary)
                projectRows(for: summary)
            } else {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Not used yet")
                        .foregroundStyle(.secondary)
                    (Text("Counts start the first time you run ")
                        + Text(Invocation.string(for: skill)).font(.invocation)
                        + Text(" in Claude Code or Cowork."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            if isAccountSkill {
                Text("Usage in claude.ai isn’t tracked. These counts cover Claude Code and Cowork only.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Stat tiles

    @ViewBuilder
    private func statTiles(for summary: UsageSummary) -> some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        LazyVGrid(columns: columns, spacing: Spacing.sm) {
            StatTile(title: "Last used",
                     value: UsageHint.text(lastUsed: summary.lastUsed).replacingOccurrences(of: "Used ", with: ""),
                     caption: summary.lastUsed.formatted(date: .omitted, time: .shortened))
            StatTile(title: window.label,
                     value: timesLabel(summary.countInWindow),
                     caption: rateCaption(count: summary.countInWindow, windowDays: windowDays(for: summary)))
            StatTile(title: "All time",
                     value: timesLabel(summary.allTimeCount),
                     caption: "since \(summary.firstUsed.formatted(.dateTime.month(.abbreviated).day().year()))")
        }
    }

    private func timesLabel(_ count: Int) -> String {
        "\(count) \(count == 1 ? "time" : "times")"
    }

    private func windowDays(for summary: UsageSummary) -> Double {
        switch window {
        case .last30Days: return 30
        case .allTime:
            let span = Date().timeIntervalSince(summary.firstUsed) / 86_400
            return max(span, 1)
        }
    }

    /// Plain-English cadence, no decimals (spec §7).
    private func rateCaption(count: Int, windowDays: Double) -> String {
        guard count > 1 else { return "once" }
        let perWeek = Double(count) / (windowDays / 7)
        if perWeek >= 2 { return "about \(Int(perWeek.rounded())) a week" }
        if perWeek >= 0.9 { return "once a week" }
        return "a few times a month"
    }

    // MARK: - By project

    @ViewBuilder
    private func projectRows(for summary: UsageSummary) -> some View {
        let maxCount = summary.byProject.map(\.count).max() ?? 1
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(summary.byProject, id: \.self) { project in
                ProjectUsageRow(name: name(for: project), count: project.count, maxCount: maxCount,
                                lastUsed: project.lastUsed, isCowork: project.projectRoot == nil)
            }
        }
    }

    private func name(for p: ProjectUsage) -> String {
        guard let root = p.projectRoot else { return "Cowork" }
        return projectNames[root.path] ?? root.lastPathComponent
    }
}

/// One stat tile in the Usage card's three-column grid.
private struct StatTile: View {
    let title: String
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.cardLabel)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(caption)
                .font(.metadata)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator))
        .accessibilityElement(children: .combine)
    }
}

/// One row of the "By project" breakdown: name, a proportional bar, count, last used.
private struct ProjectUsageRow: View {
    let name: String
    let count: Int
    let maxCount: Int
    let lastUsed: Date
    let isCowork: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(name)
                .font(.callout)
                .foregroundStyle(isCowork ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 140, alignment: .leading)

            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(.quaternary)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(isCowork ? Color.secondary : Color.accentColor)
                            .frame(width: proxy.size.width * fraction)
                    }
            }
            .frame(height: 6)
            .accessibilityHidden(true)

            Text("\(count)")
                .font(.metadata)
                .frame(minWidth: 24, alignment: .trailing)

            Text(lastUsed.formatted(date: .abbreviated, time: .omitted))
                .font(.metadata)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 92, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(count) \(count == 1 ? "time" : "times"), last used \(lastUsed.formatted(date: .abbreviated, time: .omitted))")
        .help(lastUsed.formatted(date: .abbreviated, time: .shortened))
    }

    private var fraction: CGFloat {
        guard maxCount > 0 else { return 0 }
        return CGFloat(count) / CGFloat(maxCount)
    }
}
