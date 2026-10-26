import AppKit
import UserNotifications

/// Posts a local notification when new source skills are found while the app
/// is in the background; clicking it brings the app forward and opens the
/// What's new popover.
@MainActor
final class SourceUpdatesNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = SourceUpdatesNotifier()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func announce(title: String, body: String) {
        if NSApp.isActive && NSApp.keyWindow != nil { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = nil
            let request = UNNotificationRequest(
                identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .showSourceUpdates, object: nil)
        }
        completionHandler()
    }
}
