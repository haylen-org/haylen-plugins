import FirebaseCore
import FirebaseCrashlytics
import Foundation

// Native part of the Firebase Crashlytics plugin on Apple platforms. Crashlytics reports through the default Firebase app that the plugin `firebase` configures, and every Lua error that stops the app reaches it as a non-fatal error with the frames of the Lua stack.
@objc(FirebaseCrashlyticsPlugin)
final class FirebaseCrashlyticsPlugin: NSObject, HaylenPlugin {
    struct Message: Decodable {
        let message: String
    }

    struct Enabled: Codable {
        let enabled: Bool
    }

    struct Crashed: Encodable {
        let crashed: Bool
    }

    // The parameters of a call that takes none, which decode from any JSON, `null` included.
    struct Nothing: Decodable {
        init(from decoder: Decoder) {}
    }

    private static let notConfiguredMessage = "Firebase is not configured, so Crashlytics reports nothing. Give the plugin \"firebase\" a valid \"servicesPlist\"."
    private static let notConfigured = ["message": notConfiguredMessage, "code": "notConfigured"]

    private var reportsLuaErrors = false

    func load(with context: HaylenPluginContext) {
        reportsLuaErrors = context.config["reportLuaErrors"] as? Bool == true
        registerReports(context)
        registerCollection(context)

        // Crashes the app on purpose after the answer, so a project checks that its crashes reach Crashlytics.
        context.register("crash") { (_: Nothing) async throws -> [String: Bool] in
            try Self.requireConfigured()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                fatalError("A test crash that the app asked for through the plugin \"firebase-crashlytics\".")
            }
            return ["crashing": true]
        }
    }

    func appDidFail(with error: [String: Any]) {
        guard reportsLuaErrors, FirebaseApp.app() != nil else {
            return
        }
        let message = error["message"] as? String ?? "The Lua code of the app failed."
        let frames = error["frames"] as? [[String: Any]] ?? []
        Self.record(message: message, frames: frames)
    }

    private func registerReports(_ context: HaylenPluginContext) {
        context.register("log") { (params: Message) async throws -> [String: Bool] in
            try Self.requireConfigured()
            Crashlytics.crashlytics().log(params.message)
            return ["logged": true]
        }

        context.registerHandler("setUserId") { params, reply in
            guard FirebaseApp.app() != nil else {
                reply(false, Self.notConfigured)
                return
            }

            let call = params as? [String: Any]
            Crashlytics.crashlytics().setUserID(call?["id"] as? String)
            reply(true, NSNull())
        }

        // Custom keys take texts, numbers and flags, so they go through the dictionaries of the bridge.
        context.registerHandler("setCustomKeys") { params, reply in
            guard FirebaseApp.app() != nil else {
                reply(false, Self.notConfigured)
                return
            }
            guard let keys = params as? [String: Any] else {
                reply(false, ["message": "The method \"setCustomKeys\" needs a table of keys and values.", "code": "invalidParams"])
                return
            }

            Crashlytics.crashlytics().setCustomKeysAndValues(keys)
            reply(true, NSNull())
        }

        context.registerHandler("recordError") { params, reply in
            guard FirebaseApp.app() != nil else {
                reply(false, Self.notConfigured)
                return
            }
            guard let call = params as? [String: Any], let message = call["message"] as? String else {
                reply(false, ["message": "The method \"recordError\" needs the message of the error.", "code": "invalidParams"])
                return
            }

            Self.record(message: message, frames: call["frames"] as? [[String: Any]] ?? [])
            reply(true, NSNull())
        }
    }

    private func registerCollection(_ context: HaylenPluginContext) {
        context.register("setCollectionEnabled") { (params: Enabled) async throws -> Enabled in
            try Self.requireConfigured()
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(params.enabled)
            return params
        }

        context.register("didCrashOnPreviousExecution") { (_: Nothing) async throws -> Crashed in
            try Self.requireConfigured()
            return Crashed(crashed: Crashlytics.crashlytics().didCrashDuringPreviousExecution())
        }

        context.register("sendUnsentReports") { (_: Nothing) async throws -> [String: Bool] in
            try Self.requireConfigured()
            Crashlytics.crashlytics().sendUnsentReports()
            return ["sent": true]
        }

        context.register("deleteUnsentReports") { (_: Nothing) async throws -> [String: Bool] in
            try Self.requireConfigured()
            Crashlytics.crashlytics().deleteUnsentReports()
            return ["deleted": true]
        }
    }

    private static func requireConfigured() throws {
        guard FirebaseApp.app() != nil else {
            throw HaylenFailure(notConfiguredMessage, code: "notConfigured")
        }
    }

    // A Lua error becomes a non-fatal exception whose stack is the Lua stack, from the innermost call outward.
    private static func record(message: String, frames: [[String: Any]]) {
        let exception = ExceptionModel(name: "LuaError", reason: message)
        exception.stackTrace = frames.map { frame in
            let symbol = frame["function"] as? String ?? "?"
            let file = frame["source"] as? String ?? "?"
            let line = frame["line"] as? Int ?? 0
            return StackFrame(symbol: symbol, file: file, line: line)
        }
        Crashlytics.crashlytics().record(exceptionModel: exception)
    }
}
