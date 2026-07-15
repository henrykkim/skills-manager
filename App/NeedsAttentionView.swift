import AppKit
import SwiftUI
import SkillsManagerCore

struct NeedsAttentionView: View {
    let issues: [ParseIssue]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Needs Attention").font(.detailTitle)
                    Text("These items exist on disk but couldn't be read. They are never hidden — fix the file or remove the folder.")
                        .foregroundStyle(.secondary)
                }

                ForEach(issues) { issue in
                    SectionCard(title: issue.location.lastPathComponent) {
                        Text(issue.detail).font(.callout)
                        HStack(spacing: Spacing.sm) {
                            Text(issue.location.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .truncationMode(.middle)
                                .lineLimit(1)
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([issue.location])
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .navigationTitle("Needs Attention")
    }
}
