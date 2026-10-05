import Foundation
import UserNotifications

/// Notifications for automated switches (F6). Permission is requested the first
/// time one happens; if it's denied, the name flashed next to the menu-bar icon is
/// the only signal.
enum SwitchNotifier {
    static func post(_ announcement: AutomationSwitch.Announcement) async {
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert])
        }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let content = UNMutableNotificationContent()
        (content.title, content.body) = text(for: announcement)
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// Title and body for each announcement. Kept separate so it's testable.
    static func text(for announcement: AutomationSwitch.Announcement) -> (String, String) {
        switch announcement {
        case .switched(let name, .shortcut):
            return ("Switched to \(name)", "A shortcut changed your network location.")
        case .switched(let name, .focus):
            return ("Switched to \(name)", "Your Focus changed your network location.")
        case .helperNeeded:
            return ("Focus didn\u{2019}t switch locations",
                    "To let a Focus switch your network location, choose Set Up Passwordless Switching\u{2026} in Switchback\u{2019}s menu.")
        case .focusFailed(let name):
            return ("Couldn\u{2019}t switch to \(name)",
                    "Your Focus tried to change your network location. You can switch from Switchback\u{2019}s menu instead.")
        }
    }
}
