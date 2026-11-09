import FirebaseAnalytics
import FirebaseCore
import Foundation

// Native part of the Firebase Analytics plugin on Apple platforms. It logs into the default Firebase app that the plugin `firebase` configures, which loads before it.
@objc(FirebaseAnalyticsPlugin)
final class FirebaseAnalyticsPlugin: NSObject, HaylenPlugin {
    struct Enabled: Codable {
        let enabled: Bool
    }

    struct Identifier: Encodable {
        let id: String?
    }

    struct Reset: Encodable {
        let reset: Bool
    }

    // The parameters of a call that takes none, which decode from any JSON, `null` included.
    struct Nothing: Decodable {
        init(from decoder: Decoder) {}
    }

    private static let consentTypes: [String: ConsentType] = ["analyticsStorage": .analyticsStorage, "adStorage": .adStorage, "adUserData": .adUserData, "adPersonalization": .adPersonalization]

    private static let notConfiguredMessage = "Firebase is not configured, so Analytics logs nothing. Give the plugin \"firebase\" a valid \"servicesPlist\"."
    private static let notConfigured = ["message": notConfiguredMessage, "code": "notConfigured"]

    func load(with context: HaylenPluginContext) {
        registerEvents(context)
        registerConsent(context)

        context.register("appInstanceId") { (_: Nothing) async throws -> Identifier in
            try Self.requireConfigured()
            return Identifier(id: Analytics.appInstanceID())
        }

        context.register("resetAnalyticsData") { (_: Nothing) async throws -> Reset in
            try Self.requireConfigured()
            Analytics.resetAnalyticsData()
            return Reset(reset: true)
        }
    }

    // Events and properties take any values that JSON gives, so they go through the dictionaries of the bridge.
    private func registerEvents(_ context: HaylenPluginContext) {
        context.registerHandler("logEvent") { params, reply in
            guard FirebaseApp.app() != nil else {
                reply(false, Self.notConfigured)
                return
            }
            guard let call = params as? [String: Any], let name = call["name"] as? String, !name.isEmpty else {
                reply(false, ["message": "The method \"logEvent\" needs the name of the event.", "code": "invalidParams"])
                return
            }

            Analytics.logEvent(name, parameters: call["params"] as? [String: Any])
            reply(true, NSNull())
        }

        context.registerHandler("setUserId") { params, reply in
            guard FirebaseApp.app() != nil else {
                reply(false, Self.notConfigured)
                return
            }

            let call = params as? [String: Any]
            Analytics.setUserID(call?["id"] as? String)
            reply(true, NSNull())
        }

        context.registerHandler("setUserProperty") { params, reply in
            guard FirebaseApp.app() != nil else {
                reply(false, Self.notConfigured)
                return
            }
            guard let call = params as? [String: Any], let name = call["name"] as? String, !name.isEmpty else {
                reply(false, ["message": "The method \"setUserProperty\" needs the name of the property.", "code": "invalidParams"])
                return
            }

            Analytics.setUserProperty(call["value"] as? String, forName: name)
            reply(true, NSNull())
        }
    }

    private func registerConsent(_ context: HaylenPluginContext) {
        context.registerHandler("setConsent") { params, reply in
            guard FirebaseApp.app() != nil else {
                reply(false, Self.notConfigured)
                return
            }

            var consent: [ConsentType: ConsentStatus] = [:]
            for (key, value) in params as? [String: Any] ?? [:] {
                guard let type = Self.consentTypes[key], let status = value as? String, status == "granted" || status == "denied" else {
                    reply(false, ["message": "The consent \"\(key)\" takes \"granted\" or \"denied\", for analyticsStorage, adStorage, adUserData and adPersonalization.", "code": "invalidParams"])
                    return
                }
                consent[type] = status == "granted" ? .granted : .denied
            }

            Analytics.setConsent(consent)
            reply(true, NSNull())
        }

        context.register("setCollectionEnabled") { (params: Enabled) async throws -> Enabled in
            try Self.requireConfigured()
            Analytics.setAnalyticsCollectionEnabled(params.enabled)
            return params
        }
    }

    private static func requireConfigured() throws {
        guard FirebaseApp.app() != nil else {
            throw HaylenFailure(notConfiguredMessage, code: "notConfigured")
        }
    }
}
