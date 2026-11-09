import Foundation
import UserNotifications

// The delegate of the notification center of the app, which the Notifications plugin owns. The plugin makes it the delegate of the center as its plugin class loads, while the app launches and before launching ends, so the system delivers the response to a notification that launched the app. It hands every notification and response to the delegates in the order they registered, the Notifications plugin first, and the plugins that depend on it register theirs with `addDelegate(_:)`.
@MainActor
final class Notifications: NSObject, @MainActor UNUserNotificationCenterDelegate {
    // Joins the answers of the delegates to one notification: each delegate answers once, and the last answer hands the union of their options to the center. It is safe to share between threads, since the delegates answer from any thread and its count and options sit behind the lock.
    private final class Join: @unchecked Sendable {
        private let lock = NSLock()
        private var pending: Int
        private var options: UNNotificationPresentationOptions = []
        private let done: (UNNotificationPresentationOptions) -> Void

        init(count: Int, done: @escaping (UNNotificationPresentationOptions) -> Void) {
            pending = count
            self.done = done
        }

        // The answer of one delegate, which a second call of its completion handler cannot repeat.
        func answer() -> (UNNotificationPresentationOptions) -> Void {
            var answered = false
            return { [self] given in
                lock.lock()
                if answered {
                    lock.unlock()
                    return
                }
                answered = true
                options.formUnion(given)
                pending -= 1
                let last = pending == 0
                let joined = options
                lock.unlock()

                if last {
                    done(joined)
                }
            }
        }
    }

    private static let shared = Notifications()

    private var delegates: [NotificationsDelegate] = []

    // Makes this object the delegate of the notification center, with the plugin class of Notifications as its first delegate. The plugin class calls it once, as it loads.
    static func observe(_ plugin: NotificationsDelegate) {
        shared.delegates.append(plugin)
        UNUserNotificationCenter.current().delegate = shared
    }

    // Registers a delegate that receives the notifications and the responses of the center from then on. A plugin that depends on Notifications calls it from the `load(with:)` of its plugin class.
    static func addDelegate(_ delegate: NotificationsDelegate) {
        shared.delegates.append(delegate)
    }

    // The center may call its delegate on any thread, and the async form of each method reaches the main actor before it runs, so the delegates hear the center on the main thread.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        await withCheckedContinuation { continuation in
            present(notification, center: center, answered: continuation)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await withCheckedContinuation { continuation in
            receive(response, center: center, handled: continuation)
        }
    }

    // A delegate without the method answers with no options at once, and the plugin class of Notifications is always a delegate, so every notification gets its answer.
    private func present(_ notification: UNNotification, center: UNUserNotificationCenter, answered: CheckedContinuation<UNNotificationPresentationOptions, Never>) {
        let join = Join(count: delegates.count) { options in answered.resume(returning: options) }
        for delegate in delegates {
            let answer = join.answer()
            if delegate.userNotificationCenter?(center, willPresent: notification, withCompletionHandler: answer) == nil {
                answer([])
            }
        }
    }

    private func receive(_ response: UNNotificationResponse, center: UNUserNotificationCenter, handled: CheckedContinuation<Void, Never>) {
        let join = Join(count: delegates.count) { _ in handled.resume() }
        for delegate in delegates {
            let answer = join.answer()
            if delegate.userNotificationCenter?(center, didReceive: response, withCompletionHandler: { answer([]) }) == nil {
                answer([])
            }
        }
    }
}
