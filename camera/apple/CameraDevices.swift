import AVFoundation
import Foundation

#if os(tvOS)
import AVKit
import UIKit
#endif

// The cameras that AVFoundation offers on each Apple platform, and the one that a start asks for by its id, by the way it faces, or the default camera of the system.
@available(tvOS 17.0, visionOS 2.1, *)
enum CameraDevices {
    static func all() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes(), mediaType: .video, position: .unspecified).devices
    }

    static func describe(_ device: AVCaptureDevice) -> CameraPlugin.Camera {
        CameraPlugin.Camera(id: device.uniqueID, name: device.localizedName, facing: facing(of: device))
    }

    // The built-in camera of a Mac faces the person.
    static func facing(of device: AVCaptureDevice) -> String {
        #if os(macOS)
        if device.deviceType == .builtInWideAngleCamera {
            return "front"
        }
        #endif
        switch device.position {
        case .front:
            return "front"
        case .back:
            return "back"
        default:
            return "external"
        }
    }

    @MainActor
    static func find(id: String?, facing: String?, context: HaylenPluginContext) async throws -> AVCaptureDevice {
        #if os(tvOS)
        if all().isEmpty {
            try await CameraContinuityPicker.connect(context)
        }
        #endif
        let devices = all()

        if let id {
            guard let device = devices.first(where: { $0.uniqueID == id }) else {
                throw HaylenFailure("This device has no camera with the id \"\(id)\". The function \"camera.cameras\" lists the cameras.", code: "noCamera")
            }
            return device
        }

        if let facing {
            guard let device = devices.first(where: { self.facing(of: $0) == facing }) else {
                throw HaylenFailure("This device has no camera that faces \"\(facing)\".", code: "noCamera")
            }
            return device
        }

        guard let device = defaultDevice(among: devices) else {
            throw HaylenFailure("This device has no camera.", code: "noCamera")
        }
        return device
    }

    private static func defaultDevice(among devices: [AVCaptureDevice]) -> AVCaptureDevice? {
        #if os(visionOS)
        return devices.first
        #else
        return AVCaptureDevice.default(for: .video) ?? devices.first
        #endif
    }

    // The physical cameras, without the virtual ones that join several lenses of a phone, which AVFoundation lists as cameras of their own.
    private static func deviceTypes() -> [AVCaptureDevice.DeviceType] {
        #if os(macOS)
        if #available(macOS 14.0, *) {
            return [.builtInWideAngleCamera, .external, .continuityCamera]
        }
        return [.builtInWideAngleCamera, .externalUnknown]
        #elseif os(tvOS)
        return [.continuityCamera]
        #elseif os(visionOS)
        return [.builtInWideAngleCamera]
        #else
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera, .builtInTrueDepthCamera]
        if #available(iOS 17.0, *) {
            types.append(.external)
        }
        return types
        #endif
    }
}

#if os(tvOS)
// The picker of the system in which the person connects an iPhone or an iPad as the Continuity Camera of the Apple TV. It covers the app while it shows. UIKit calls its delegate on the main thread, so the picker conforms to the delegate protocol on the main actor.
@available(tvOS 17.0, *)
@MainActor
final class CameraContinuityPicker: NSObject, @MainActor AVContinuityDevicePickerViewControllerDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private let controller = AVContinuityDevicePickerViewController()

    static func connect(_ context: HaylenPluginContext) async throws {
        guard AVContinuityDevicePickerViewController.isSupported else {
            throw HaylenFailure("This Apple TV takes no Continuity Camera.", code: "unsupported")
        }
        guard let presenter = context.viewController else {
            throw HaylenFailure("The app has no window to show the picker of the Continuity Camera in.", code: "cameraFailed")
        }

        let picker = CameraContinuityPicker()
        picker.controller.delegate = picker
        context.coverApp()
        defer { context.uncoverApp() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            picker.continuation = continuation
            presenter.present(picker.controller, animated: true)
        }
        // The delegate of the picker is weak, so the picker lives until the person answered.
        withExtendedLifetime(picker) {}
    }

    func continuityDevicePicker(_ pickerViewController: AVContinuityDevicePickerViewController, didConnect device: AVContinuityDevice) {
        finish(.success(()))
    }

    func continuityDevicePickerDidCancel(_ pickerViewController: AVContinuityDevicePickerViewController) {
        finish(.failure(HaylenFailure("The person closed the picker of the Continuity Camera without a camera.", code: "cancelled")))
    }

    private func finish(_ result: Result<Void, Error>) {
        if controller.presentingViewController != nil {
            controller.dismiss(animated: true)
        }
        let waiting = continuation
        continuation = nil
        waiting?.resume(with: result)
    }
}
#endif
