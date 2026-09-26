import AppKit
import SwiftUI

/// Settings › Usage: the switch that turns skill-usage tracking on and off,
/// what it reads, and the file it collects into.
struct SettingsView: View {
    @Environment(UsageStore.self) private var usage

    var body: some View {
        @Bindable var usage = usage
        Form {
            Section("Usage") {
                Toggle("Show when and how often skills are used", isOn: $usage.isEnabled)
                Text("Reads skill invocation records from Claude Code and Cowork session logs. Message text is never read or stored. Turning this off deletes the usage data Skills Manager has collected.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if usage.isEnabled {
                    Divider()

                    LabeledContent("Reads", value: "Claude Code sessions · Cowork sessions")
                    LabeledContent("Not covered", value: "claude.ai in the browser")
                    LabeledContent("Last scanned", value: lastScannedText)
                    LabeledContent("Collected", value: collectedText)

                    HStack {
                        Spacer()
                        Button("Show Usage File in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([UsageStore.storeURL])
                        }
                        .disabled(!usageFileExists)
                        Button("Rescan Now") { usage.refresh() }
                            .disabled(usage.isScanning)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding(.bottom, Spacing.sm)
    }

    private var usageFileExists: Bool {
        FileManager.default.fileExists(atPath: UsageStore.storeURL.path)
    }

    private var lastScannedText: String {
        guard let date = usage.lastScanned else { return "Never" }
        return date.formatted(.relative(presentation: .named))
    }

    private var collectedText: String {
        let events = usage.eventCount
        let sessions = usage.sessionCount
        let eventWord = events == 1 ? "invocation" : "invocations"
        let sessionWord = sessions == 1 ? "session" : "sessions"
        return "\(events) \(eventWord) across \(sessions) \(sessionWord)"
    }
}
