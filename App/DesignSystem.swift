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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(invocation)
                .font(.invocation)
                .textSelection(.enabled)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(invocation, forType: .string)
                setCopied(true)
                Task {
                    try? await Task.sleep(for: .seconds(1.6))
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
