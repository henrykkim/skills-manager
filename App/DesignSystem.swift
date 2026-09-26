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
            // Tint carries the hue on the background only; the label stays
            // primary so it clears 4.5:1 (tinted text measured 2.1–3.2:1).
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(.primary)
    }
}

/// Enabled/disabled indicator. Enabled is the default state, so it is a
/// quiet dot; disabled is the exception and says so in words, never by
/// color alone.
struct StatusDot: View {
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(isEnabled ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
            if !isEnabled {
                Text("Disabled")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        // A 7 pt dot is too small to hover for its tooltip; pad the target.
        .frame(minWidth: 16, minHeight: 16)
        .help(isEnabled ? "Enabled" : "Disabled")
        .accessibilityElement(children: .ignore)
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
struct SectionCard<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @ViewBuilder var trailing: Trailing

    init(title: String, @ViewBuilder content: () -> Content, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.content = content()
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .font(.cardLabel)
                    .foregroundStyle(.secondary)
                Spacer(minLength: Spacing.sm)
                trailing
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension SectionCard where Trailing == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, content: content, trailing: { EmptyView() })
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
                    .accessibilityHidden(true)
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
