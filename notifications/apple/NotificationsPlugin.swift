import Foundation
import UserNotifications

// Native part of the Notifications plugin on iOS, iPadOS, Mac Catalyst, visionOS and macOS, built on UserNotifications. The runtime creates it by the class name that `plugin.json` gives and loads it while the app launches, where it makes `Notifications` the delegate of the notification center, with itself as the first `NotificationsDelegate`. The identifiers of its requests carry a prefix, so it lists, cancels and answers only the notifications of the plugin.
@objc(NotificationsPlugin)
final class NotificationsPlugin: NSObject, HaylenPlugin, NotificationsDelegate {
    struct Schedule: Decodable {
        let id: String
        let title: String
        let body: String
        let seconds: Double?
        let date: Double?
        let sound: Bool
        let badge: Int?
    }

    struct Identified: Decodable {
        let id: String
    }

    struct Empty: Codable {}

    private static let prefix = "notifications."

    // The user info of a request holds property list values alone, so it keeps the data of the notification, any JSON value, as JSON text, next to the date when it shows.
    private static let dataKey = "notifications.data"
    private static let dateKey = "notifications.date"

    private var context: HaylenPluginContext!
    private let center = UNUserNotificationCenter.current()

    func load(with context: HaylenPluginContext) {
        self.context = context
        Notifications.observe(self)
        Permissions.register(permission(), on: context)
        registerSchedule()
        registerLists()
        registerCancels()
    }

    // The permission `notifications`, which the plugin registers through the Permissions plugin and which asks for alerts, sounds and badges. A provisional or an ephemeral authorization delivers the notifications as well, so it counts as granted.
    private func permission() -> Permission {
        Permission(name: "notifications", capability: "notifications", requirements: [], state: { [center] answer in
            center.getNotificationSettings { settings in
                answer(Self.state(of: settings.authorizationStatus), nil)
            }
        }, request: { [center] answer in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                answer(granted ? .granted : .denied, nil)
            }
        })
    }

    private nonisolated static func state(of status: UNAuthorizationStatus) -> Permission.State {
        switch status {
        case .notDetermined:
            return .prompt
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            return .granted
        @unknown default:
            return .unknown
        }
    }

    // The data of a notification is any JSON value, so the handler reads the parameters as a dictionary instead of a decodable value.
    private func registerSchedule() {
        context.registerHandler("schedule") { [unowned self] params, reply in
            guard let fields = params as? [String: Any], let input = try? JSONSerialization.data(withJSONObject: fields), let schedule = try? JSONDecoder().decode(Schedule.self, from: input) else {
                reply(false, ["message": "The parameters of the notification are invalid.", "code": "invalidParams"])
                return
            }
            let data = Self.jsonText(of: fields["data"])
            Task { @MainActor in
                do {
                    try await Permissions.require("notifications", on: self.context)
                    let date = try await self.add(schedule, data: data)
                    reply(true, ["id": schedule.id, "date": date.timeIntervalSince1970])
                } catch let failure as HaylenFailure {
                    reply(false, ["message": failure.message, "code": failure.code ?? "failed"])
                } catch {
                    reply(false, ["message": "The notification could not be scheduled: \(error.localizedDescription)", "code": "failed"])
                }
            }
        }
    }

    // A date matches the calendar, so the notification follows a change of the clock or of the time zone, while seconds count from now. A date less than a second away shows after one second, since the calendar matches whole seconds.
    private func add(_ schedule: Schedule, data: String?) async throws -> Date {
        let now = Date()
        let trigger: UNNotificationTrigger
        let date: Date
        if let at = schedule.date, at - now.timeIntervalSince1970 >= 1 {
            date = Date(timeIntervalSince1970: at)
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        } else {
            let seconds = max(schedule.seconds ?? 1, 1)
            date = now.addingTimeInterval(seconds)
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        }

        let content = UNMutableNotificationContent()
        content.title = schedule.title
        content.body = schedule.body
        content.sound = schedule.sound ? .default : nil
        content.badge = schedule.badge.map { NSNumber(value: $0) }
        var userInfo: [String: Any] = [Self.dateKey: date.timeIntervalSince1970]
        userInfo[Self.dataKey] = data
        content.userInfo = userInfo

        let request = UNNotificationRequest(identifier: Self.prefix + schedule.id, content: content, trigger: trigger)
        try await center.add(request)
        return date
    }

    // The entries hold the data of each notification as any JSON value, so the handlers answer with dictionaries instead of encodable values.
    private func registerLists() {
        context.registerHandler("pending") { [unowned self] _, reply in
            Task { @MainActor in
                let requests = await self.center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(Self.prefix) }
                let entries = requests.map { Self.describe($0, date: $0.content.userInfo[Self.dateKey] as? Double ?? 0) }
                reply(true, Self.sorted(entries))
            }
        }

        context.registerHandler("delivered") { [unowned self] _, reply in
            Task { @MainActor in
                let notifications = await self.center.deliveredNotifications().filter { $0.request.identifier.hasPrefix(Self.prefix) }
                let entries = notifications.map { Self.describe($0.request, date: $0.date.timeIntervalSince1970) }
                reply(true, Self.sorted(entries))
            }
        }
    }

    private func registerCancels() {
        context.register("cancel") { [unowned self] (params: Identified) async throws -> Empty in
            let identifier = Self.prefix + params.id
            self.center.removePendingNotificationRequests(withIdentifiers: [identifier])
            self.center.removeDeliveredNotifications(withIdentifiers: [identifier])
            return Empty()
        }

        context.register("cancelAll") { [unowned self] (_: Empty) async throws -> Empty in
            let pending = await self.center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
            let delivered = await self.center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix(Self.prefix) }
            self.center.removePendingNotificationRequests(withIdentifiers: pending)
            self.center.removeDeliveredNotifications(withIdentifiers: delivered)
            return Empty()
        }
    }

    private static func describe(_ request: UNNotificationRequest, date: Double) -> [String: Any] {
        var entry: [String: Any] = ["id": String(request.identifier.dropFirst(prefix.count)), "title": request.content.title, "body": request.content.body, "date": date]
        entry["data"] = data(of: request)
        return entry
    }

    private static func sorted(_ entries: [[String: Any]]) -> [[String: Any]] {
        entries.sorted { ($0["date"] as? Double ?? 0) < ($1["date"] as? Double ?? 0) }
    }

    private static func jsonText(of value: Any?) -> String? {
        guard let value, !(value is NSNull), let bytes = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed) else {
            return nil
        }
        return String(data: bytes, encoding: .utf8)
    }

    private static func data(of request: UNNotificationRequest) -> Any? {
        guard let text = request.content.userInfo[dataKey] as? String, let bytes = text.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: bytes, options: .fragmentsAllowed)
    }

    // A notification of the plugin shows while the app is in front too, and the notifications of the plugins that depend on it keep the options those plugins ask for.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(notification.request.identifier.hasPrefix(Self.prefix) ? [.banner, .list, .sound, .badge] : [])
    }

    // The tap on a notification of the plugin reaches the app as `opened`, retained, so the tap that launched the app waits for the first listener.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let request = response.notification.request
        if request.identifier.hasPrefix(Self.prefix) && response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            var payload: [String: Any] = ["id": String(request.identifier.dropFirst(Self.prefix.count))]
            payload["data"] = Self.data(of: request)
            context.emitRetained("opened", payload: payload)
        }
        completionHandler()
    }
}
