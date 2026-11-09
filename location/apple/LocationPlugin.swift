import CoreLocation
import Foundation

// Native part of the Location plugin on Apple platforms: one fix of Core Location or its updates, and the permissions `location`, `preciseLocation` and `backgroundLocation`. The runtime creates it by the class name that `plugin.json` gives, and loads it while the app launches.
@objc(LocationPlugin)
final class LocationPlugin: NSObject, HaylenPlugin {
    struct Empty: Codable {}

    struct Current: Decodable {
        let precise: Bool
        let timeout: Double
    }

    struct Watch: Decodable {
        let distance: Double
        let precise: Bool
        let background: Bool
    }

    private let authorization = LocationAuthorization()
    private var updates: LocationUpdates?

    func load(with context: HaylenPluginContext) {
        let updates = LocationUpdates(context: context)
        self.updates = updates

        for permission in authorization.permissions() {
            Permissions.register(permission, on: context)
        }

        // Every app that loads the Lua API sends `reset`, so updates that an earlier app of the process left running stop.
        context.register("reset") { (_: Empty) async throws -> Empty? in
            updates.stop()
            return nil
        }

        context.register("current") { (params: Current) async throws -> LocationUpdates.Place in
            try await Permissions.require(params.precise ? "preciseLocation" : "location", on: context)
            try await Self.requireLocationOn()
            return try await updates.current(precise: params.precise, timeout: params.timeout)
        }

        context.register("watch") { (params: Watch) async throws -> Empty? in
            try await Permissions.require(params.precise ? "preciseLocation" : "location", on: context)
            if params.background {
                try await Permissions.require("backgroundLocation", on: context)
            }
            try await Self.requireLocationOn()
            try updates.watch(distance: params.distance, precise: params.precise, background: params.background)
            return nil
        }

        context.register("stop") { (_: Empty) async throws -> Empty? in
            updates.stop()
            return nil
        }
    }

    // Core Location reads whether the location of the device is on away from the main thread, since the answer may take a while.
    private static func requireLocationOn() async throws {
        let enabled = await Task.detached { CLLocationManager.locationServicesEnabled() }.value
        guard enabled else {
            throw HaylenFailure("The location of the device is turned off. The person turns it on in the settings of the system.", code: "locationOff")
        }
    }
}
