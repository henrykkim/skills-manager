import AppKit
import SwiftUI

// The app's design constants and shared components.
// Motion: critically damped only (.smooth/.snappy) — nothing here carries momentum.
// Spacing: one scale, no ad-hoc values.

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

extension Font {
    /// Commands the user types — always monospaced.
    static let invocation = Font.system(.callout, design: .monospaced).weight(.medium)
    static let detailTitle = Font.title2.weight(.semibold)
    static let cardLabel = Font.caption.weight(.semibold)
    /// Dates, versions, counts — tabular so columns of metadata align.
    static let metadata = Font.caption.monospacedDigit()
}

/// Small capsule naming an item's kind ("Plugin", "Skill", "Shared").
struct KindBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}

/// Enabled/disabled indicator with an explanatory tooltip.
struct StatusDot: View {
    let isEnabled: Bool

    var body: some View {
        Circle()
            .fill(isEnabled ? Color.green : Color.secondary.opacity(0.5))
            .frame(width: 7, height: 7)
            .help(isEnabled ? "Enabled" : "Disabled")
            .accessibilityLabel(isEnabled ? "Enabled" : "Disabled")
    }
}

/// A monospaced command with a copy button. Feedback is instant and reduced-motion aware.
struct InvocationChip: View {
    let invocation: String
    @State private var copied = false
    @State private var revertTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(invocation)
                .font(.invocation)
                .textSelection(.enabled)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(invocation, forType: .string)
                revertTask?.cancel()
                setCopied(true)
                revertTask = Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    guard !Task.isCancelled else { return }
                    setCopied(false)
                }
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .labelStyle(.iconOnly)
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(copied ? Color.green : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help("Copy command")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func setCopied(_ value: Bool) {
        if reduceMotion {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { copied = value }
        } else {
            withAnimation(.smooth(duration: 0.3)) { copied = value }
        }
    }
}

/// Titled card for the detail views. Sits on the secondary background —
/// a single level of elevation, never stacked on another card.
struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title.uppercased())
                .font(.cardLabel)
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// "Updated Sep 11, 2026" — muted, tabular, with the full timestamp on hover.
struct UpdatedLabel: View {
    let date: Date

    var body: some View {
        Text("Updated \(date.formatted(date: .abbreviated, time: .omitted))")
            .font(.metadata)
            .foregroundStyle(.tertiary)
            .help(date.formatted(date: .long, time: .shortened))
            .accessibilityLabel("Updated \(date.formatted(date: .long, time: .omitted))")
    }
}

/// An outbound link. The arrow tells the user it opens their browser; the
/// tooltip shows exactly where. Whole label is the hit area.
struct SourceLink: View {
    let label: String
    let url: URL
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: Spacing.xs) {
                Text(label)
                    .underline(hovering, color: .accentColor)
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(Color.accentColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            if reduceMotion {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { hovering = isHovering }
            } else {
                withAnimation(.smooth(duration: 0.15)) { hovering = isHovering }
            }
        }
        .help(url.absoluteString)
        .accessibilityHint("Opens \(url.host() ?? "a web page") in your browser")
        .accessibilityAddTraits(.isLink)
    }
}
