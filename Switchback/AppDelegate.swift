import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        statusController = StatusItemController()
    }

    /// Show automated-switch notifications even while Switchback is active.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
