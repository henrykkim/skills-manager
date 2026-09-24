import SwiftUI

/// First-run note shown before the app looks inside project folders.
/// Everything else (personal skills, plugins, Claude-account skills, Cowork,
/// folders added by hand) already loads without it.
struct ProjectAccessSheet: View {
    let onContinue: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Label("Find skills in your projects", systemImage: "folder.badge.gearshape")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Skills Manager can also show the skills inside the folders you use with Claude — in the terminal, the Claude app, and Cowork.")
                Text("It reads only Claude’s list of those folders and the skill and settings files inside them. It never changes anything.")
            }
            Text("If a project is in Documents, Desktop, or iCloud Drive, macOS may ask you to allow access.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: Spacing.md) {
                Spacer()
                Button("Not Now", action: onLater)
                    .keyboardShortcut(.cancelAction)
                Button("Continue", action: onContinue)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, Spacing.sm)
        }
        // Wrap body text inside the fixed-width sheet instead of truncating.
        .fixedSize(horizontal: false, vertical: true)
        .padding(Spacing.xl)
        .frame(width: 440)
    }
}
