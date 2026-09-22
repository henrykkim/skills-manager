import AppKit
import SwiftUI
import SkillsManagerCore

struct InstallSheet: View {
    @Bindable var model: InstallSheetModel
    let onDone: () -> Void
    @FocusState private var fieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header
            if !isTerminal { pasteField }
            content
            footer
        }
        .padding(Spacing.xl)
        .frame(width: 560)
        .frame(minHeight: 320)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: model.phase)
        .onAppear { fieldFocused = true }
    }

    private var isTerminal: Bool {
        switch model.phase { case .success, .failure, .installing: true; default: false }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Install a skill or plugin").font(.detailTitle)
            Text("Paste a GitHub link, a skills.sh link, or an install command.")
                .foregroundStyle(.secondary)
        }
    }

    private var pasteField: some View {
        TextEditor(text: $model.text)
            .font(.invocation)
            .frame(minHeight: 64, maxHeight: 120)
            .padding(Spacing.sm)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .topLeading) {
                if model.text.isEmpty {
                    // TextEditor has no native placeholder; a plain example
                    // string grounds the header's instruction in something
                    // concrete without duplicating it as a second label.
                    Text("e.g. https://github.com/owner/repo")
                        .font(.invocation)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.md)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .focused($fieldFocused)
            .accessibilityLabel("Paste a link or install command")
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .looking:
            HStack(spacing: Spacing.sm) { ProgressView().controlSize(.small); Text("Looking…").foregroundStyle(.secondary) }
                .accessibilityElement(children: .combine)
        case .unrecognized(let sentence):
            Label(sentence, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        case .preview(let preview):
            previewView(preview)
        case .installing(let step):
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ProgressView()
                Text(step).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        case .success(_, let installed):
            successView(installed)
        case .failure(let message, let log):
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                DisclosureGroup("Show details") {
                    ScrollView { Text(log).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(maxHeight: 160)
                }
            }
        }
    }

    // MARK: preview

    private func previewView(_ p: InstallPreview) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(p.title).font(.headline).lineLimit(1).truncationMode(.tail)
                KindBadge(text: p.kind == .plugin ? "Plugin" : "Skill repository", tint: p.kind == .plugin ? .purple : .blue)
                if let author = p.authorName {
                    if let url = p.authorURL { SourceLink(label: author, url: url) } else { Text(author).foregroundStyle(.secondary) }
                }
            }
            if let summary = p.summary { Text(summary).foregroundStyle(.secondary) }
            if let note = p.marketplaceNote { Text(note).font(.callout).foregroundStyle(.secondary) }
            if p.isPluginInstalled { Text("Already installed").font(.callout).foregroundStyle(.secondary) }
            if let missing = model.missingTool { Label(missing, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.secondary) }

            if !p.skills.isEmpty {
                Text("Skills it will add".uppercased()).font(.cardLabel).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(p.skills) { skill in
                            skillRow(skill)
                            if skill.id != p.skills.last?.id { Divider() }
                        }
                    }
                }
                .frame(maxHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.quaternary))
            }

            DisclosureGroup("Command") {
                ForEach(model.plannedCommands, id: \.self) { cmd in
                    Text(cmd)
                        .font(.invocation)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(.callout)
        }
    }

    private func skillRow(_ skill: PreviewSkill) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // The Toggle's label is the whole VStack below, so clicking or
            // tapping anywhere on the row — name, invocation, or summary —
            // toggles selection, not just the checkbox glyph.
            Toggle(isOn: Binding(
                get: { model.selected.contains(skill.folder) },
                set: { on in if on { model.selected.insert(skill.folder) } else { model.selected.remove(skill.folder) } }
            )) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.sm) {
                        Text(skill.name).lineLimit(1).truncationMode(.tail)
                        Text(skill.invocation).font(.metadata).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                        if skill.isInstalled { Text("Already installed").font(.metadata).foregroundStyle(.tertiary) }
                        if !skill.isValid { Text("Has a formatting problem").font(.metadata).foregroundStyle(.tertiary) }
                    }
                    if let summary = skill.summary { Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
            }
            .toggleStyle(.checkbox)
            .disabled(!skill.isValid)
            .accessibilityLabel(accessibilityLabel(for: skill))
            DisclosureGroup("View skill text") {
                ScrollView { Text(skill.body).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 160)
            }
            .font(.caption)
            .padding(.leading, Spacing.lg + Spacing.xs)
        }
        .padding(Spacing.sm)
        .contentShape(Rectangle())
    }

    /// One combined announcement per row so VoiceOver reads a skill's name,
    /// invocation, and status together instead of as separate stops.
    private func accessibilityLabel(for skill: PreviewSkill) -> String {
        var parts = [skill.name, skill.invocation]
        if skill.isInstalled { parts.append("Already installed") }
        if !skill.isValid { parts.append("Has a formatting problem, can't be selected") }
        if let summary = skill.summary { parts.append(summary) }
        return parts.joined(separator: ". ")
    }

    // MARK: success

    private func successView(_ installed: [PreviewSkill]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label("Installed", systemImage: "checkmark.circle").font(.headline)
            if installed.isEmpty {
                Text("Restart Claude Code to load the plugin.").foregroundStyle(.secondary)
            } else {
                Text("Type any of these in Claude Code:").foregroundStyle(.secondary)
                ForEach(installed) { skill in InvocationChip(invocation: skill.invocation) }
                HStack(spacing: Spacing.sm) {
                    Text("Saved in your skills folder").font(.caption).foregroundStyle(.secondary)
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([ClaudePaths().personalSkillsDir])
                    }.buttonStyle(.link).font(.caption)
                }
            }
        }
    }

    // MARK: footer

    private var footer: some View {
        HStack {
            Spacer()
            switch model.phase {
            case .success:
                Button("Done") { model.reset(); onDone() }.keyboardShortcut(.defaultAction)
            case .failure:
                Button("Cancel") { model.reset(); onDone() }.keyboardShortcut(.cancelAction)
                Button("Try again") { model.retry() }.keyboardShortcut(.defaultAction)
            case .installing:
                Button("Cancel") {}.disabled(true)
                    .accessibilityHint("Installing — please wait")
            default:
                Button("Cancel") { model.reset(); onDone() }.keyboardShortcut(.cancelAction)
                Button("Install") { Task { await model.install() } }
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Install (⌘↩)")
                    .disabled(!model.canInstall)
            }
        }
    }
}
