import AVFoundation
import Foundation

// The permission `microphone` that the plugin owns, which AVFoundation reads and asks for once the `Info.plist` gives the text of its prompt. Apple TV before tvOS 17 has no microphone for apps.
enum MicrophonePermission {
    static let unavailable = HaylenFailure("Apple TV gives apps a microphone from tvOS 17 on.", code: "unsupported")

    static func make() -> Permission {
        Permission(name: "microphone", capability: "the microphone", requirements: [.usageDescription("NSMicrophoneUsageDescription")], state: { answer in
            guard #available(tvOS 17.0, *) else {
                answer(.unsupported, unavailable.message)
                return
            }
            answer(state(of: AVCaptureDevice.authorizationStatus(for: .audio)), nil)
        }, request: { answer in
            guard #available(tvOS 17.0, *) else {
                answer(.unsupported, unavailable.message)
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                answer(granted ? .granted : .denied, nil)
            }
        })
    }

    @available(tvOS 17.0, *)
    private static func state(of status: AVAuthorizationStatus) -> Permission.State {
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
