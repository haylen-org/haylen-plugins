import Foundation
import UserNotifications

// Native part of the local plugin of the sample on Apple platforms. It registers a permission of every state through the Permissions plugin, whose permission `asked` is the authorization of the notification center, which shows the prompt of the system, and answers `use` once the app holds the permission that the call names.
@objc(PermissionStatesPlugin)
final class PermissionStatesPlugin: NSObject, HaylenPlugin {
    struct Use: Decodable {
        let name: String
    }

    func load(with context: HaylenPluginContext) {
        Permissions.register(Self.fixed("held", state: .granted), on: context)
        Permissions.register(Self.asked(), on: context)
        Permissions.register(Self.fixed("refused", state: .denied), on: context)
        Permissions.register(Self.fixed("untold", state: .unknown), on: context)
        Permissions.register(Self.fixed("absent", state: .unsupported), on: context)

        context.register("use") { (params: Use) async throws -> String in
            try await Permissions.require(params.name, on: context)
            return "The plugin used the permission \"\(params.name)\"."
        }
    }

    // A permission whose state never changes, which a request answers without a prompt.
    private static func fixed(_ name: String, state: Permission.State) -> Permission {
        let reason = state == .unsupported ? "The sample has the permission \"\(name)\" on no device." : nil
        return Permission(name: name, capability: "the permission \"\(name)\" of the sample", requirements: [], state: { answer in
            answer(state, reason)
        }, request: { answer in
            answer(state, reason)
        })
    }

    private static func asked() -> Permission {
        Permission(name: "asked", capability: "notifications", requirements: [.className("UNUserNotificationCenter", framework: "UserNotifications.framework")], state: { answer in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                answer(state(of: settings.authorizationStatus), nil)
            }
        }, request: { answer in
            UNUserNotificationCenter.current().requestAuthorization(options: [.badge]) { granted, _ in
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
}
