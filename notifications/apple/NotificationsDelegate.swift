import Foundation
import UserNotifications

// What a plugin that depends on Notifications implements to receive the notifications and the responses of the notification center, on the main thread. The plugin registers itself with `Notifications.addDelegate(_:)` from the `load(with:)` of its plugin class, so it receives the response to a notification that launched the app, and it never replaces the delegate of the center, which the Notifications plugin owns. Each delegate answers only for its own notifications, and calls the completion handler once.
@MainActor
@objc protocol NotificationsDelegate: NSObjectProtocol {
    // A notification that arrives while the app is in front shows with the union of the options that the delegates ask for, or not at all when none asks.
    @objc optional func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)

    // The response to a notification, such as a tap, reaches every delegate, and the center hears that it was handled once every delegate called its completion handler.
    @objc optional func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void)
}
