import FirebaseCore
import FirebaseInstallations
import FirebaseMessaging
import Foundation
import UIKit
import UserNotifications

// Native part of the Firebase Cloud Messaging plugin on Apple platforms. It registers the app instance with Cloud Messaging by its Firebase installation ID, which `FirebaseMessagingInstallationIdEnabled` of the `Info.plist` turns on. The plugin `firebase` turns off the swizzling of Firebase, so the runtime hands this class the device token of APNs and the plugin `notifications`, whose delegate of the notification center this class joins as a `NotificationsDelegate`, hands it the events of the center, which it passes to Firebase. It answers only the notifications of Firebase, which carry `gcm.message_id` in their user info, and leaves every other notification to the plugin that posted it, such as `notifications`. Messages reach the app as messageReceived, the taps on notifications as messageOpened, retained so the tap that launched the app waits for the first listener, and every registration of the app instance as registered. Cloud Messaging calls its delegate on the main thread, so the plugin conforms to the delegate protocol on the main actor.
@objc(FirebaseMessagingPlugin)
final class FirebaseMessagingPlugin: NSObject, HaylenPlugin, NotificationsDelegate, @MainActor MessagingDelegate {
    struct Registration: Encodable {
        let installationId: String
    }

    struct Topic: Codable {
        let topic: String
    }

    struct Enabled: Codable {
        let enabled: Bool
    }

    // The parameters of a call that takes none, which decode from any JSON, `null` included.
    struct Nothing: Decodable {
        init(from decoder: Decoder) {}
    }

    private static let messageIdKey = "gcm.message_id"

    private var context: HaylenPluginContext!
    private var showsInForeground = false

    func load(with context: HaylenPluginContext) {
        self.context = context
        showsInForeground = context.config["showInForeground"] as? Bool == true
        Notifications.addDelegate(self)
        registerInstance(context)
        registerTopics(context)

        // The token of APNs needs no permission of the person, so the app registers for remote notifications at once.
        guard FirebaseApp.app() != nil else {
            return
        }
        Messaging.messaging().delegate = self
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func registerInstance(_ context: HaylenPluginContext) {
        context.register("register") { (_: Nothing) async throws -> Registration in
            let messaging = try Self.messaging()
            do {
                try await messaging.register()
                let installationId = try await Installations.installations().installationID()
                return Registration(installationId: installationId)
            } catch {
                throw HaylenFailure("Firebase Cloud Messaging did not register the app instance: \(error.localizedDescription)", code: "unavailable")
            }
        }

        context.register("unregister") { (_: Nothing) async throws -> Registration in
            let messaging = try Self.messaging()
            do {
                let installationId = try await Installations.installations().installationID()
                try await messaging.unregister()
                return Registration(installationId: installationId)
            } catch {
                throw HaylenFailure("Firebase Cloud Messaging did not unregister the app instance: \(error.localizedDescription)", code: "unavailable")
            }
        }

        context.register("setAutoInitEnabled") { (params: Enabled) async throws -> Enabled in
            try Self.messaging().isAutoInitEnabled = params.enabled
            return params
        }
    }

    private func registerTopics(_ context: HaylenPluginContext) {
        context.register("subscribe") { (params: Topic) async throws -> Topic in
            let messaging = try Self.messaging()
            do {
                try await messaging.subscribe(toTopic: params.topic)
                return params
            } catch {
                throw HaylenFailure("Firebase Cloud Messaging did not subscribe to \"\(params.topic)\": \(error.localizedDescription)", code: "unavailable")
            }
        }

        context.register("unsubscribe") { (params: Topic) async throws -> Topic in
            let messaging = try Self.messaging()
            do {
                try await messaging.unsubscribe(fromTopic: params.topic)
                return params
            } catch {
                throw HaylenFailure("Firebase Cloud Messaging did not unsubscribe from \"\(params.topic)\": \(error.localizedDescription)", code: "unavailable")
            }
        }
    }

    private static func messaging() throws -> Messaging {
        guard FirebaseApp.app() != nil else {
            throw HaylenFailure("Firebase is not configured, so Cloud Messaging receives nothing. Give the plugin \"firebase\" a valid \"servicesPlist\".", code: "notConfigured")
        }
        return Messaging.messaging()
    }

    private static func isFirebaseMessage(_ userInfo: [AnyHashable: Any]) -> Bool {
        FirebaseApp.app() != nil && userInfo[messageIdKey] != nil
    }

    // A message as the app reads it: the title and the body of its notification, if any, and its data.
    private static func describe(_ userInfo: [AnyHashable: Any], title: String?, body: String?) -> [String: Any] {
        var data: [String: Any] = [:]
        for (key, value) in userInfo {
            guard let name = key as? String, name != "aps", !name.hasPrefix("gcm."), !name.hasPrefix("google.") else {
                continue
            }
            data[name] = value
        }

        var message: [String: Any] = ["data": data]
        message["messageId"] = userInfo[messageIdKey]
        message["title"] = title
        message["body"] = body
        return message
    }

    func messaging(_ messaging: Messaging, didReceiveRegistration installationId: String?) {
        guard let installationId else {
            return
        }
        context.emit("registered", payload: ["installationId": installationId], retain: true, batched: false)
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        context.emit("registrationFailed", payload: ["message": error.localizedDescription], retain: true, batched: false)
    }

    // A data message reaches the app in the background too, which the background mode remote-notification allows.
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard Self.isFirebaseMessage(userInfo) else {
            completionHandler(.noData)
            return
        }

        Messaging.messaging().appDidReceiveMessage(userInfo)
        context.emit("messageReceived", payload: Self.describe(userInfo, title: nil, body: nil))
        completionHandler(.newData)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let content = notification.request.content
        guard Self.isFirebaseMessage(content.userInfo) else {
            completionHandler([])
            return
        }

        Messaging.messaging().appDidReceiveMessage(content.userInfo)
        context.emit("messageReceived", payload: Self.describe(content.userInfo, title: content.title, body: content.body))
        completionHandler(showsInForeground ? [.banner, .list, .sound] : [])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        guard Self.isFirebaseMessage(content.userInfo) else {
            completionHandler()
            return
        }

        Messaging.messaging().appDidReceiveMessage(content.userInfo)
        context.emitRetained("messageOpened", payload: Self.describe(content.userInfo, title: content.title, body: content.body))
        completionHandler()
    }
}
