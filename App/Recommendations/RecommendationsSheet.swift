import SwiftUI
import SkillsManagerCore

/// The Recommended sheet (spec §5). Rows mirror the Install box's skill rows;
/// the footer mirrors its Install/Done states.
struct RecommendationsSheet: View {
    @Bindable var model: RecommendationsModel
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header
            rows
            if let missing = model.missingTool {
                Label(missing, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.secondary)
            }
            footer
        }
        .padding(Spacing.xl)
        .frame(width: 560)
        .onAppear { model.start() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(model.catalog.title).font(.detailTitle).accessibilityAddTraits(.isHeader)
            if let intro = model.catalog.intro { Text(intro).foregroundStyle(.secondary) }
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Plugins and skills").textCase(.uppercase).tracking(0.4).font(.cardLabel).foregroundStyle(.secondary)
                Spacer()
                Button(model.allSelected ? "Deselect All" : "Select All") {
                    if model.allSelected { model.deselectAll() } else { model.selectAll() }
                }
                .buttonStyle(.link).font(.callout)
                .disabled(model.selectableIDs.isEmpty || model.isInstalling || model.isResolving || model.finished)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.catalog.items) { item in
                        row(item)
                        if item.id != model.catalog.items.last?.id { Divider() }
                    }
                }
            }
            .frame(maxHeight: 320)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.quaternary))
        }
    }

    private func row(_ item: RecommendationItem) -> some View {
        let state = model.states[item.id] ?? .checking
        let selectable: Bool = { if case .ready = state { !model.isInstalling && !model.finished } else { false } }()
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Toggle(isOn: Binding(
                get: { model.selected.contains(item.id) },
                set: { on in if on { model.selected.insert(item.id) } else { model.selected.remove(item.id) } }
            )) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(item.name).lineLimit(1).truncationMode(.tail)
                    if let blurb = item.blurb { Text(blurb).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    status(state)
                }
            }
            .toggleStyle(.checkbox)
            .disabled(!selectable)
            .accessibilityLabel(accessibilityLabel(item, state))
            if case .failed(_, let log) = state {
                DisclosureGroup("Show Details") {
                    ScrollView { Text(log).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(maxHeight: 120)
                }
                .font(.caption)
                .padding(.leading, Spacing.lg + Spacing.xs)
            }
        }
        .padding(Spacing.sm)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func status(_ state: RecommendationsModel.ItemState) -> some View {
        switch state {
        case .checking:
            HStack(spacing: Spacing.xs) { ProgressView().controlSize(.mini); Text("Checking…") }
                .font(.metadata).foregroundStyle(.tertiary)
        case .ready(let preview):
            Text(model.summary(for: preview)).font(.metadata).foregroundStyle(.tertiary)
        case .installed:
            Text("Already installed").font(.metadata).foregroundStyle(.tertiary)
        case .unavailable(let sentence):
            Label(sentence, systemImage: "exclamationmark.triangle").font(.metadata).foregroundStyle(.secondary)
        case .installing:
            HStack(spacing: Spacing.xs) { ProgressView().controlSize(.mini); Text("Installing…") }
                .font(.metadata).foregroundStyle(.secondary)
        case .done:
            Label("Installed", systemImage: "checkmark.circle").font(.metadata).foregroundStyle(.secondary)
        case .failed(let message, _):
            Label(message, systemImage: "exclamationmark.triangle").font(.metadata).foregroundStyle(.secondary)
        }
    }

    private func accessibilityLabel(_ item: RecommendationItem, _ state: RecommendationsModel.ItemState) -> String {
        var parts = [item.name]
        if let blurb = item.blurb { parts.append(blurb) }
        switch state {
        case .checking: parts.append("Checking")
        case .ready(let p): parts.append(model.summary(for: p))
        case .installed: parts.append("Already installed, can't be selected")
        case .unavailable(let s): parts.append("Unavailable. \(s)")
        case .installing: parts.append("Installing")
        case .done: parts.append("Installed")
        case .failed(let m, _): parts.append("Failed. \(m)")
        }
        return parts.joined(separator: ". ")
    }

    private var footer: some View {
        HStack {
            Spacer()
            if model.finished {
                Button("Done") { onDone() }.keyboardShortcut(.defaultAction)
            } else if model.isInstalling {
                HStack(spacing: Spacing.xs) { ProgressView().controlSize(.small); Text("Installing…") }
                    .foregroundStyle(.secondary)
            } else {
                Button("Not Now") { onDone() }.keyboardShortcut(.cancelAction)
                Button("Install Selected") { Task { await model.install() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canInstall)
            }
        }
    }
}
