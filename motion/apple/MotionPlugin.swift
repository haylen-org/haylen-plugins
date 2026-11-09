import Foundation
#if os(iOS) && !targetEnvironment(macCatalyst) || os(visionOS)
import CoreMotion
import UIKit
#endif

// Native part of the Motion plugin on Apple platforms. The runtime creates it by the class name that `plugin.json` gives, and loads it while the app launches. An iPhone, an iPad and a Vision Pro read their sensors through Core Motion, which asks the person from version 27.2, while an Apple TV, a Mac and an app of Mac Catalyst have no sensors that Core Motion reads, so they answer `unsupported` with the reason.
@objc(MotionPlugin)
final class MotionPlugin: NSObject, HaylenPlugin {
    struct Watch: Decodable {
        let session: Int
    }

    struct Start: Decodable {
        let session: Int
        let sensors: [String]
        let rate: Double
    }

    struct Started: Encodable {
        let sensors: [String]
    }

    struct Empty: Codable {}

    // Waits until the task that runs it is cancelled, and then throws. The wait is a stream that never yields, since a sleep of the longest duration ends at once on iOS 17.
    static func untilCancelled() async throws {
        let (never, continuation) = AsyncStream<Never>.makeStream()
        for await _ in never {}
        continuation.finish()
        throw CancellationError()
    }

    #if os(iOS) && !targetEnvironment(macCatalyst) || os(visionOS)
    private let sensors = MotionSensors()

    func load(with context: HaylenPluginContext) {
        sensors.register(context)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        sensors.pause()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        sensors.resume()
    }
    #else
    func load(with context: HaylenPluginContext) {
        Permissions.register(Permission(name: "motion", capability: "the motion sensors", requirements: [], state: { answer in
            answer(.unsupported, Self.reason)
        }, request: { answer in
            answer(.unsupported, Self.reason)
        }), on: context)

        // The watch of a session never answers by itself, and the start fails with the reason.
        context.register("watch") { (_: Watch) async throws -> Empty in
            try await Self.untilCancelled()
            return Empty()
        }

        context.register("start") { (_: Start) async throws -> Started in
            throw HaylenFailure(Self.reason, code: "unsupported")
        }
    }

    #if os(tvOS)
    private static let reason = "An Apple TV has no motion sensors of its own. The Siri Remote and the controllers report their motion as gamepads, which \"input.startGamepadMotion\" of \"haylen.input\" reads."
    #else
    private static let reason = "A Mac gives apps no readings of motion sensors."
    #endif
    #endif
}

#if os(iOS) && !targetEnvironment(macCatalyst) || os(visionOS)
// The motion sensors of the device through Core Motion: the accelerometer, the gyroscope and the attitude that the device motion fuses from them, with z up. They live on the main actor, and each update reaches the main queue, which is the frame thread, and goes to the app as the batched event `reading`, in the axes of the device in its natural orientation with the quarter turns of the screen, which the Lua API turns into the axes of the screen.
@MainActor
final class MotionSensors {
    struct Reading: Encodable {
        let session: Int
        let sensor: String
        let x: Double
        let y: Double
        let z: Double
        let w: Double?
        let turns: Int
    }

    private static let standardGravity = 9.80665

    private let manager = CMMotionManager()
    private weak var context: HaylenPluginContext?
    private var session: Int?
    private var running: [String] = []
    private var interval: TimeInterval = 1.0 / 60.0
    private var paused = false
    private var asking: [Permission.Answer] = []

    func register(_ context: HaylenPluginContext) {
        self.context = context
        Permissions.register(permission(), on: context)

        // The app holds the watch of a session while its sensors run, and gives it up to stop them, which the end of the app does too.
        context.register("watch") { [unowned self] (params: MotionPlugin.Watch) async throws -> MotionPlugin.Empty in
            self.session = params.session
            do {
                try await MotionPlugin.untilCancelled()
            } catch {
                if self.session == params.session {
                    self.stop()
                    self.session = nil
                }
                throw error
            }
            return MotionPlugin.Empty()
        }

        context.register("start") { [unowned self] (params: MotionPlugin.Start) async throws -> MotionPlugin.Started in
            try self.requireSensors(params.sensors)
            try await Permissions.require("motion", on: context)
            if self.session != params.session {
                throw HaylenFailure("The app stopped the motion sensors before they started.", code: "cancelled")
            }

            self.stop()
            self.running = params.sensors
            self.interval = 1.0 / params.rate

            if !self.paused {
                self.run()
            }
            return MotionPlugin.Started(sensors: params.sensors)
        }
    }

    func pause() {
        paused = true
        stop()
    }

    func resume() {
        paused = false
        if session != nil && !running.isEmpty {
            run()
        }
    }

    // The permission `motion`, which Core Motion asks for from version 27.2 with the `NSMotionUsageDescription` of the `Info.plist`, and earlier systems give every app.
    private func permission() -> Permission {
        let usage = HaylenRequirement.usageDescription("NSMotionUsageDescription")
        return Permission(name: "motion", capability: "the motion sensors", requirements: [usage], state: { [unowned self] answer in
            answer(self.state(), self.hasSensors() ? nil : Self.noSensors)
        }, request: { [unowned self] answer in
            self.asking.append(answer)
            self.prompt()
        })
    }

    private static let noSensors = "This device has no motion sensors."

    private func hasSensors() -> Bool {
        manager.isAccelerometerAvailable || manager.isGyroAvailable || manager.isDeviceMotionAvailable
    }

    private func state() -> Permission.State {
        if !hasSensors() {
            return .unsupported
        }
        guard #available(iOS 27.2, visionOS 27.2, *) else {
            return .granted
        }
        switch CMMotionManager.authorizationStatus {
        case .notDetermined:
            return .prompt
        case .restricted, .denied:
            return .denied
        case .authorized:
            return .granted
        @unknown default:
            return .unknown
        }
    }

    // The system asks the person when an app first starts the updates of the device motion, and the first update or error comes once the person answered. No sensor runs before that, so the updates stop there until a start runs them.
    private func prompt() {
        if asking.count > 1 {
            return
        }
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [unowned self] _, _ in
            if self.asking.isEmpty {
                return
            }
            self.manager.stopDeviceMotionUpdates()
            if self.session != nil && self.running.contains("attitude") && !self.paused {
                self.runAttitude()
            }

            let answers = self.asking
            self.asking.removeAll()
            let state = self.state()
            for answer in answers {
                answer(state, nil)
            }
        }
    }

    private func requireSensors(_ names: [String]) throws {
        let available = ["accelerometer": manager.isAccelerometerAvailable, "gyroscope": manager.isGyroAvailable, "attitude": manager.isDeviceMotionAvailable]
        let absent = names.filter { available[$0] != true }
        if absent.isEmpty {
            return
        }
        if !hasSensors() {
            throw HaylenFailure(Self.noSensors, code: "unsupported")
        }
        let quoted = absent.map { "\"\($0)\"" }
        let list = quoted.count == 1 ? quoted[0] : quoted.dropLast().joined(separator: ", ") + " and " + quoted[quoted.count - 1]
        throw HaylenFailure("The device has no motion \(quoted.count == 1 ? "sensor" : "sensors") \(list).", code: "unsupported")
    }

    private func run() {
        if running.contains("accelerometer") {
            manager.accelerometerUpdateInterval = interval
            manager.startAccelerometerUpdates(to: .main) { [unowned self] measurement, _ in
                guard let value = measurement?.acceleration else {
                    return
                }
                // Core Motion measures the pull of gravity in units of gravity, so a device that lies face up reads -1 on z, while the plugin reads the push that holds the device up in meters per second squared.
                let gravity = Self.standardGravity
                self.send("accelerometer", -value.x * gravity, -value.y * gravity, -value.z * gravity, nil)
            }
        }
        if running.contains("gyroscope") {
            manager.gyroUpdateInterval = interval
            manager.startGyroUpdates(to: .main) { [unowned self] measurement, _ in
                guard let value = measurement?.rotationRate else {
                    return
                }
                self.send("gyroscope", value.x, value.y, value.z, nil)
            }
        }
        if running.contains("attitude") {
            runAttitude()
        }
    }

    private func runAttitude() {
        manager.deviceMotionUpdateInterval = interval
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [unowned self] motion, _ in
            guard let value = motion?.attitude.quaternion else {
                return
            }
            self.send("attitude", value.x, value.y, value.z, value.w)
        }
    }

    private func stop() {
        manager.stopAccelerometerUpdates()
        manager.stopGyroUpdates()
        if asking.isEmpty {
            manager.stopDeviceMotionUpdates()
        }
    }

    private func send(_ sensor: String, _ x: Double, _ y: Double, _ z: Double, _ w: Double?) {
        guard let session else {
            return
        }
        try? context?.emit("reading", Reading(session: session, sensor: sensor, x: x, y: y, z: z, w: w, turns: Self.quarterTurns(context)), batched: true)
    }

    // The quarter turns counterclockwise of the device while the screen keeps the app upright. A Vision Pro shows the app in a window that never turns.
    private static func quarterTurns(_ context: HaylenPluginContext?) -> Int {
        #if os(iOS)
        switch context?.windowScene?.interfaceOrientation {
        case .landscapeRight:
            return 1
        case .portraitUpsideDown:
            return 2
        case .landscapeLeft:
            return 3
        default:
            return 0
        }
        #else
        return 0
        #endif
    }
}
#endif
