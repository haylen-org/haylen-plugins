import CoreBluetooth
import Foundation

// Native part of the Bluetooth plugin on iOS, iPadOS, Mac Catalyst, tvOS, visionOS and macOS, built on CoreBluetooth. The runtime creates it by the class name that `plugin.json` gives and loads it while the app launches. Values cross the bridge as bytes, which the Swift helpers for decodable values do not carry, so its handlers take and answer dictionaries.
@objc(BluetoothPlugin)
final class BluetoothPlugin: NSObject, HaylenPlugin {
    private var context: HaylenPluginContext!
    private var central: BluetoothCentral!

    func load(with context: HaylenPluginContext) {
        self.context = context
        central = BluetoothCentral(context: context)
        Permissions.register(central.permission(), on: context)

        handle("scan") { [unowned self] params in
            try await self.central.scan(services: try Self.texts(params, "services"), seconds: try Self.number(params, "seconds"))
            return [:]
        }
        handle("stopScan", asks: false) { [unowned self] _ in
            self.central.stopScan()
            return [:]
        }
        handle("connect") { [unowned self] params in
            try await self.central.connect(try Self.text(params, "id"))
        }
        handle("disconnect", asks: false) { [unowned self] params in
            try await self.central.disconnect(try Self.text(params, "id"))
            return [:]
        }
        handle("services") { [unowned self] params in
            try await self.central.services(try Self.text(params, "id"))
        }
        handle("characteristics") { [unowned self] params in
            try await self.central.characteristics(try Self.text(params, "id"), service: try Self.text(params, "service"))
        }
        handle("read") { [unowned self] params in
            ["value": try await self.central.read(try Self.target(params))]
        }
        handle("write") { [unowned self] params in
            guard let value = params["value"] as? Data else {
                throw HaylenFailure("The value of the write is not bytes.", code: "invalidParams")
            }
            try await self.central.write(value, to: try Self.target(params), response: try Self.flag(params, "response"))
            return [:]
        }
        handle("subscribe") { [unowned self] params in
            try await self.central.setNotify(true, for: try Self.target(params))
            return [:]
        }
        handle("unsubscribe") { [unowned self] params in
            try await self.central.setNotify(false, for: try Self.target(params))
            return [:]
        }
    }

    // Answers `bluetooth.<method>` with an async function on the main actor, whose task ends when the app cancels the call or its timeout passes. A method that `asks` needs the permission, and asks for it first where the app does not hold it yet.
    private func handle(_ method: String, asks: Bool = true, _ body: @escaping @MainActor ([String: Any]) async throws -> Any) {
        context.registerCancellableHandler(method) { [unowned self] params, reply in
            let task = Task { @MainActor in
                do {
                    if asks {
                        try await Permissions.require("bluetooth", on: self.context)
                    }
                    reply(true, try await body(params as? [String: Any] ?? [:]))
                } catch is CancellationError {
                    return
                } catch let failure as HaylenFailure {
                    var answer: [String: Any] = ["message": failure.message, "code": failure.code ?? "failed"]
                    if let missing = failure.data as? [String: [[String: String]]] {
                        answer["data"] = missing
                    }
                    reply(false, answer)
                } catch {
                    reply(false, ["message": error.localizedDescription, "code": "failed"])
                }
            }
            return { task.cancel() }
        }
    }

    private static func text(_ params: [String: Any], _ key: String) throws -> String {
        guard let value = params[key] as? String else {
            throw HaylenFailure("The call needs \"\(key)\".", code: "invalidParams")
        }
        return value
    }

    // An empty list of Lua crosses the bridge as an empty object.
    private static func texts(_ params: [String: Any], _ key: String) throws -> [String] {
        if let list = params[key] as? [String] {
            return list
        }
        if let object = params[key] as? [String: Any], object.isEmpty {
            return []
        }
        throw HaylenFailure("The call needs \"\(key)\" as a list of strings.", code: "invalidParams")
    }

    private static func number(_ params: [String: Any], _ key: String) throws -> Double {
        guard let value = params[key] as? Double else {
            throw HaylenFailure("The call needs \"\(key)\" as a number.", code: "invalidParams")
        }
        return value
    }

    private static func flag(_ params: [String: Any], _ key: String) throws -> Bool {
        guard let value = params[key] as? Bool else {
            throw HaylenFailure("The call needs \"\(key)\" as a boolean.", code: "invalidParams")
        }
        return value
    }

    private static func target(_ params: [String: Any]) throws -> BluetoothCentral.Target {
        BluetoothCentral.Target(device: try text(params, "id"), service: try text(params, "service"), characteristic: try text(params, "characteristic"))
    }
}
