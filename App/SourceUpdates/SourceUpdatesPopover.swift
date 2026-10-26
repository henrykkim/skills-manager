import SwiftUI
import SkillsManagerCore

/// Toolbar bell with a count capsule; toggles the "New from your sources" popover.
struct SourceUpdatesButton: View {
    @Environment(SourceUpdatesModel.self) private var model
    @State private var presented = false

    var body: some View {
        Button { presented.toggle() } label: {
            Label("What's new", systemImage: "bell.badge")
        }
        .help("New skills from sources you've installed from")
        .overlay(alignment: .topTrailing) {
            if model.newSkillCount > 0 {
                Text("\(model.newSkillCount)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .background(Capsule().fill(.red))
                    .offset(x: 6, y: -4)
                    .allowsHitTesting(false)
            }
        }
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            SourceUpdatesPopover(close: { presented = false })
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSourceUpdates)) { _ in presented = true }
        .onChange(of: model.findings.isEmpty) { _, empty in
            if empty { presented = false }
        }
    }
}

struct SourceUpdatesPopover: View {
    @Environment(SourceUpdatesModel.self) private var model
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("New from your sources").font(.headline)
            ForEach(model.findings) { finding in
                section(finding)
            }
            footer
        }
        .padding(Spacing.lg)
        .frame(width: 380)
    }

    private func section(_ finding: SourceFinding) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Link(finding.id, destination: finding.htmlURL)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if finding.skills.count >= 2 {
                    Button("Install all") { Task { await model.installAll(finding) } }
                        .buttonStyle(.link)
                        .disabled(model.isInstalling)
                }
            }
            ForEach(finding.skills) { skill in
                row(skill, in: finding)
            }
        }
    }

    private func row(_ skill: NewSkill, in finding: SourceFinding) -> some View {
        let state = model.rowStates[finding.key(skill)] ?? .idle
        return HStack(alignment: .top, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(skill.name)
                Text(skill.summary ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if case .failed(let message, let log) = state {
                    Text(message).font(.caption).foregroundStyle(.red)
                    DisclosureGroup("Show Details") {
                        Text(log)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                    }
                    .font(.caption)
                }
            }
            Spacer(minLength: Spacing.sm)
            switch state {
            case .installing:
                ProgressView().controlSize(.small)
            case .idle:
                Button("Install") { Task { await model.install(skill, from: finding) } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(model.isInstalling)
            case .failed:
                Button("Try again") { Task { await model.install(skill, from: finding) } }
                    .buttonStyle(.link)
                    .disabled(model.isInstalling)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(footerText).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Dismiss") {
                model.dismiss()
                close()
            }
            .buttonStyle(.link)
        }
    }

    private var footerText: String {
        var text = "Not checked yet"
        if let date = model.lastCompleted {
            let f = RelativeDateTimeFormatter()
            text = "Checked \(f.localizedString(for: date, relativeTo: Date()))"
        }
        return model.lastRunFailed ? "Couldn't reach GitHub · " + text : text
    }
}
