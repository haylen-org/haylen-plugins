import Foundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import CoreHaptics
import UIKit
#endif

// Native part of the Haptics plugin on Apple platforms. The runtime creates it by the class name that `plugin.json` gives, and loads it while the app launches. An iPhone vibrates through Core Haptics and plays the feedback generators of UIKit, a Mac plays the feedback of its Force Touch trackpad, and the other devices answer why they cannot.
@objc(HapticsPlugin)
final class HapticsPlugin: NSObject, HaylenPlugin {
    struct Vibration: Decodable {
        let seconds: Double
    }

    enum Strength: String, Decodable {
        case light, medium, heavy
    }

    struct Impact: Decodable {
        let strength: Strength
    }

    enum Kind: String, Decodable {
        case success, warning, error
    }

    struct Notification: Decodable {
        let kind: Kind
    }

    struct Nothing: Decodable {}

    #if os(iOS) && !targetEnvironment(macCatalyst)
    // The haptic engine of the device, made by the first vibration and started again by every vibration, since the system stops it while the app is in the background.
    @MainActor private var engine: CHHapticEngine?
    #endif

    func load(with context: HaylenPluginContext) {
        context.register("vibrate") { [self] (params: Vibration) async throws -> Bool in
            try await vibrate(seconds: params.seconds)
            return true
        }
        context.register("impact") { (params: Impact) async throws -> Bool in
            try Self.impact(strength: params.strength)
            return true
        }
        context.register("selection") { (_: Nothing) async throws -> Bool in
            try Self.selection()
            return true
        }
        context.register("notification") { (params: Notification) async throws -> Bool in
            try Self.notification(kind: params.kind)
            return true
        }
    }

    private static func unsupported(_ message: String) -> HaylenFailure {
        HaylenFailure(message, code: "unsupported")
    }

    #if os(iOS) && !targetEnvironment(macCatalyst)

    // A device without a haptic engine, such as an iPad, plays none of the feedback generators of UIKit, which tell nothing, so the capabilities of Core Haptics tell it first.
    private static func requireHapticEngine() throws {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            throw unsupported("This device has no haptic engine.")
        }
    }

    // A continuous event of Core Haptics at full intensity lasts the seconds of the vibration.
    @MainActor
    private func vibrate(seconds: Double) async throws {
        try Self.requireHapticEngine()
        do {
            let hapticEngine = try engine ?? CHHapticEngine()
            engine = hapticEngine
            try await hapticEngine.start()
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [intensity, sharpness], relativeTime: 0, duration: seconds)
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try hapticEngine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            throw Self.unsupported("The haptic engine could not vibrate. \(error.localizedDescription)")
        }
    }

    @MainActor
    private static func impact(strength: Strength) throws {
        try requireHapticEngine()
        let style: UIImpactFeedbackGenerator.FeedbackStyle = switch strength {
        case .light: .light
        case .medium: .medium
        case .heavy: .heavy
        }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    @MainActor
    private static func selection() throws {
        try requireHapticEngine()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    @MainActor
    private static func notification(kind: Kind) throws {
        try requireHapticEngine()
        let type: UINotificationFeedbackGenerator.FeedbackType = switch kind {
        case .success: .success
        case .warning: .warning
        case .error: .error
        }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    #elseif os(macOS)

    @MainActor
    private func vibrate(seconds: Double) async throws {
        throw Self.unsupported("A Mac has no vibration motor.")
    }

    // A Mac plays one generic feedback for every strength, and only while a finger rests on a Force Touch trackpad, which the system does not tell an app.
    @MainActor
    private static func impact(strength: Strength) throws {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    @MainActor
    private static func selection() throws {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    @MainActor
    private static func notification(kind: Kind) throws {
        throw unsupported("The trackpad of a Mac has no feedback of a notification.")
    }

    #else

    // Mac Catalyst apps run on a Mac, whose trackpad plays only the feedback of AppKit, and an Apple TV and Apple Vision Pro have neither a motor nor a haptic engine.
    #if targetEnvironment(macCatalyst)
    private static let noMotor = "A Mac has no vibration motor."
    private static let noFeedback = "UIKit plays no haptic feedback on a Mac."
    #elseif os(tvOS)
    private static let noMotor = "An Apple TV has no vibration motor."
    private static let noFeedback = "An Apple TV has no haptic engine."
    #else
    private static let noMotor = "Apple Vision Pro has no vibration motor."
    private static let noFeedback = "Apple Vision Pro has no haptic engine."
    #endif

    @MainActor
    private func vibrate(seconds: Double) async throws {
        throw Self.unsupported(Self.noMotor)
    }

    @MainActor
    private static func impact(strength: Strength) throws {
        throw unsupported(noFeedback)
    }

    @MainActor
    private static func selection() throws {
        throw unsupported(noFeedback)
    }

    @MainActor
    private static func notification(kind: Kind) throws {
        throw unsupported(noFeedback)
    }

    #endif
}
