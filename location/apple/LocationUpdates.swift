import CoreLocation
import Foundation

// One fix of Core Location, or every change of the location while the app watches, sent batched as the event `changed`. A fix waits for the next location that arrives, which a watch delivers anyway, and fails once its timeout passes. Apple TV gives one fix but no updates. It lives on the main actor, whose thread makes its manager, so Core Location calls its delegate on the main thread, and it conforms to the delegate protocol on the main actor.
@MainActor
final class LocationUpdates: NSObject, @MainActor CLLocationManagerDelegate {
    struct Place: Encodable {
        let latitude: Double
        let longitude: Double
        let accuracy: Double
        let altitude: Double?
        let speed: Double?
        let heading: Double?
        let timestamp: Double
    }

    struct Stopped: Encodable {
        let message: String
        let code: String
    }

    private let manager = CLLocationManager()
    private let context: HaylenPluginContext
    private var fixes: [UUID: CheckedContinuation<CLLocation, Error>] = [:]
    private var watching = false

    init(context: HaylenPluginContext) {
        self.context = context
        super.init()
        manager.delegate = self
    }

    func current(precise: Bool, timeout: Double) async throws -> Place {
        manager.desiredAccuracy = precise ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
        let id = UUID()
        let deadline = Task { @MainActor in
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            self.finish(id, .failure(HaylenFailure("No fix of the location came within \(Self.seconds(timeout)) seconds.", code: "timeout")))
        }
        defer { deadline.cancel() }

        let location = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation, Error>) in
            fixes[id] = continuation
            if !watching {
                manager.requestLocation()
            }
        }
        return Self.place(of: location)
    }

    #if os(tvOS)
    func watch(distance: Double, precise: Bool, background: Bool) throws {
        throw HaylenFailure("Apple TV gives one fix of the location but no updates.", code: "unsupported")
    }
    #else
    // The location in the background needs the mode `location` of `UIBackgroundModes` on iPhones and iPads, while a Mac keeps the updates of an app that runs.
    func watch(distance: Double, precise: Bool, background: Bool) throws {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        if background {
            try context.require(.backgroundMode("location"))
        }
        manager.allowsBackgroundLocationUpdates = background
        manager.pausesLocationUpdatesAutomatically = !background
        #elseif os(visionOS)
        if background {
            throw HaylenFailure("Apple Vision Pro reads the location only while the app is in use.", code: "unsupported")
        }
        #endif
        manager.desiredAccuracy = precise ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
        manager.distanceFilter = distance > 0 ? distance : kCLDistanceFilterNone
        watching = true
        manager.startUpdatingLocation()
    }
    #endif

    func stop() {
        watching = false
        #if !os(tvOS)
        manager.stopUpdatingLocation()
        #endif
        #if os(iOS) && !targetEnvironment(macCatalyst)
        manager.allowsBackgroundLocationUpdates = false
        #endif
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newest = locations.last else {
            return
        }
        for id in Array(fixes.keys) {
            finish(id, .success(newest))
        }

        guard watching else {
            return
        }
        for location in locations {
            try? context.emit("changed", Self.place(of: location), batched: true)
        }
    }

    // A watch goes on through the errors that Core Location recovers from, and ends when the person takes the location back.
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let failure = Self.failure(of: error)
        for id in Array(fixes.keys) {
            finish(id, .failure(failure))
        }

        if failure.code == "denied", watching {
            stop()
            try? context.emit("stopped", Stopped(message: failure.message, code: "denied"))
        }
    }

    private func finish(_ id: UUID, _ result: Result<CLLocation, Error>) {
        fixes.removeValue(forKey: id)?.resume(with: result)
    }

    private static func failure(of error: Error) -> HaylenFailure {
        guard (error as? CLError)?.code == .denied else {
            return HaylenFailure("The location is unknown: \(error.localizedDescription)", code: "locationUnknown")
        }
        return HaylenFailure("The person has not allowed the location. Ask for it with \"location.requestPermission('location')\", which shows the prompt of the system while the system still asks, or the person allows it in the settings of the system.", code: "denied")
    }

    private static func place(of location: CLLocation) -> Place {
        let altitude = location.verticalAccuracy >= 0 ? location.altitude : nil
        let speed = location.speed >= 0 ? location.speed : nil
        let heading = location.course >= 0 ? location.course : nil
        return Place(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, accuracy: location.horizontalAccuracy, altitude: altitude, speed: speed, heading: heading, timestamp: location.timestamp.timeIntervalSince1970)
    }

    private static func seconds(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
