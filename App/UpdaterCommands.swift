import Combine
import Sparkle
import SwiftUI

/// Mirrors SPUUpdater.canCheckForUpdates so the menu item greys out while a
/// check or update is already running.
@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }
}

/// Skills Manager → Check for Updates…
struct CheckForUpdatesView: View {
    @ObservedObject private var model: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.model = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!model.canCheckForUpdates)
    }
}

/// Mirrors SPUUpdater.automaticallyDownloadsUpdates for the Settings switch.
/// Sparkle persists the value itself (user defaults), so this is a thin bridge.
@MainActor
final class UpdaterSettingsModel: ObservableObject {
    @Published var automaticallyDownloadsUpdates: Bool {
        didSet {
            guard updater.automaticallyDownloadsUpdates != automaticallyDownloadsUpdates else { return }
            updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
        }
    }
    @Published var canCheckForUpdates = false
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        // The Sparkle update window has the same checkbox; keep the switch in step.
        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$automaticallyDownloadsUpdates)
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    func checkNow() { updater.checkForUpdates() }
}
