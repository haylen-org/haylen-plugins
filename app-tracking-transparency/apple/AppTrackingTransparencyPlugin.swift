import AdSupport
import AppTrackingTransparency
import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// Native part of the App Tracking Transparency plugin on Apple platforms. It owns the permission `tracking`, which it registers through the Permissions plugin and answers from the authorization of AppTrackingTransparency, and it gives the advertising identifier once the person allows tracking.
@objc(AppTrackingTransparencyPlugin)
final class AppTrackingTransparencyPlugin: NSObject, HaylenPlugin {
    struct Empty: Codable {}

    struct Identifier: Encodable {
        let id: String
    }

    func load(with context: HaylenPluginContext) {
        Permissions.register(Self.permission(), on: context)

        // The identifier is all zeros until the person allows tracking, so the call asks for the permission first and fails with the code `denied` without it.
        context.register("advertisingId") { (_: Empty) async throws -> Identifier in
            try await Permissions.require("tracking", on: context)
            return Identifier(id: ASIdentifierManager.shared().advertisingIdentifier.uuidString)
        }
    }

    // The system shows the prompt only while the app is active. A request of an app that is not active, such as one during its launch, answers `notDetermined` at once and leaves a prompt that shows later without telling the app, so the plugin asks only while the app is active and answers `prompt` otherwise, which the app asks again for.
    private static func permission() -> Permission {
        Permission(name: "tracking", capability: "tracking across the apps and websites of other companies", requirements: [.usageDescription("NSUserTrackingUsageDescription")], state: { answer in
            answer(state(of: ATTrackingManager.trackingAuthorizationStatus), nil)
        }, request: { answer in
            guard isAppActive() else {
                answer(.prompt, nil)
                return
            }
            ATTrackingManager.requestTrackingAuthorization { status in
                answer(state(of: status), nil)
            }
        })
    }

    @MainActor
    private static func isAppActive() -> Bool {
        #if os(macOS)
        return NSApplication.shared.isActive
        #else
        return UIApplication.shared.applicationState == .active
        #endif
    }

    // A restricted device, such as one that a parent or an organization manages, never lets the person allow tracking, so it counts as denied.
    private nonisolated static func state(of status: ATTrackingManager.AuthorizationStatus) -> Permission.State {
        switch status {
        case .notDetermined:
            return .prompt
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .unknown
        }
    }
}
