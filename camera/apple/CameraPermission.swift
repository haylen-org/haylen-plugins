import AVFoundation
import Foundation

// The permission `camera` that the plugin owns, which AVFoundation reads and asks for once the `Info.plist` gives the text of its prompt. Apple TV before tvOS 17 has no camera for apps.
enum CameraPermission {
    #if os(visionOS)
    static let unavailable = HaylenFailure("Apple Vision Pro gives apps a camera from visionOS 2.1 on.", code: "unsupported")
    #else
    static let unavailable = HaylenFailure("Apple TV gives apps a camera from tvOS 17 on.", code: "unsupported")
    #endif

    static func make() -> Permission {
        Permission(name: "camera", capability: "the camera", requirements: [.usageDescription("NSCameraUsageDescription")], state: { answer in
            guard #available(tvOS 17.0, *) else {
                answer(.unsupported, unavailable.message)
                return
            }
            answer(state(of: AVCaptureDevice.authorizationStatus(for: .video)), nil)
        }, request: { answer in
            guard #available(tvOS 17.0, *) else {
                answer(.unsupported, unavailable.message)
                return
            }
            AVCaptureDevice.requestAccess(for: .video) { granted in
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
