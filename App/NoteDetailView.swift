import AppKit
import SwiftUI
import SkillsManagerCore

/// Read-only view of a markdown file the user added. Never writes to the
/// file, and never reads one that is stored online only (reading would
/// make macOS download it).
struct NoteDetailView: View {
    let file: NoteFile
    @State private var content: Content = .loading

    private enum Content {
        case loading
        case blocks([MarkdownBlock])
        /// Why there's nothing to show — styled as status, never as the file's text.
        case message(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                bodyContent
            }
            .padding(Spacing.xl)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .navigationTitle(file.name)
        .task(id: file.id) { load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(file.name).font(.detailTitle)
                NotASkillTag()
            }
            Text("This is a markdown file, not a Claude skill. Claude won't run it automatically.")
                .foregroundStyle(.secondary)
            HStack(spacing: Spacing.md) {
                Button("Open in Editor") { NSWorkspace.shared.open(file.url) }
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
                    .buttonStyle(.link)
            }
            .padding(.top, Spacing.xs)
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch content {
        case .loading:
            EmptyView()
        case .message(let text):
            Label(text, systemImage: "doc.text")
                .foregroundStyle(.secondary)
        case .blocks(let blocks):
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    view(for: block, isFirst: index == 0)
                }
            }
            .textSelection(.enabled)
        }
    }

    private func load() {
        content = .loading
        guard LocalFile.isDownloaded(file.url) else {
            content = .message("This file is stored online only. Download it in Finder to read it here.")
            return
        }
        guard let text = try? String(contentsOf: file.url, encoding: .utf8) else {
            content = .message("This file can't be read as text.")
            return
        }
        let blocks = MarkdownBlocks.parse(text)
        content = blocks.isEmpty ? .message("This file is empty.") : .blocks(blocks)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock, isFirst: Bool) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(level == 1 ? .title2.weight(.semibold) : level == 2 ? .title3.weight(.semibold) : .headline)
                .accessibilityAddTraits(.isHeader)
                // Closer to the text it introduces than to the section above.
                .padding(.top, isFirst ? 0 : Spacing.sm)
        case .paragraph(let text):
            Text(inline(text)).lineSpacing(Spacing.xs)
        case .bullet(let text):
            listItem(marker: "•", text: text)
        case .numbered(let text):
            listItem(marker: "–", text: text)
        case .code(let text):
            Text(text).font(.system(.callout, design: .monospaced))
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func listItem(marker: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(marker).foregroundStyle(.secondary)
            Text(inline(text)).lineSpacing(Spacing.xs)
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
