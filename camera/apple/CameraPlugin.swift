import AVFoundation
import Foundation

// Native part of the Camera plugin on Apple platforms: the cameras of AVFoundation into the video stream `camera`, photos as JPEG bytes and the permission `camera`. Apple TV takes a camera from tvOS 17 on, the Continuity Camera of an iPhone or an iPad that the person connects in the picker of the system, and Apple Vision Pro gives apps the camera of the persona of the wearer from visionOS 2.1 on.
@objc(CameraPlugin)
final class CameraPlugin: NSObject, HaylenPlugin {
    struct Empty: Codable {}

    struct Start: Decodable {
        let camera: String?
        let facing: String?
        let width: Int
        let height: Int
    }

    struct Camera: Encodable {
        let id: String
        let name: String
        let facing: String
    }

    struct Started: Encodable {
        let id: String
        let name: String
        let facing: String
        let width: Int
        let height: Int
    }

    struct Stopped: Encodable {
        let message: String
        let code: String
    }

    // Counts the starts, stops and resets, so a start that awaits the permission or the camera learns that a later call took its place.
    private var request = 0

    // The capture of AVFoundation exists on Apple TV from tvOS 17 on, so the plugin keeps it as an object and reads it back through `capture`.
    private var captureObject: AnyObject?

    @available(tvOS 17.0, visionOS 2.1, *)
    private var capture: CameraCapture? {
        get { captureObject as? CameraCapture }
        set { captureObject = newValue }
    }

    func load(with context: HaylenPluginContext) {
        Permissions.register(CameraPermission.make(), on: context)

        // Every app that loads the Lua API sends `reset`, so a capture that an earlier app of the process left running stops.
        context.register("reset") { [unowned self] (_: Empty) async throws -> Empty? in
            self.request += 1
            self.stopCapture()
            return nil
        }

        context.register("cameras") { (_: Empty) async throws -> [Camera] in
            guard #available(tvOS 17.0, visionOS 2.1, *) else {
                throw CameraPermission.unavailable
            }
            try await Permissions.require("camera", on: context)
            return CameraDevices.all().map(CameraDevices.describe)
        }

        context.register("start") { [unowned self] (params: Start) async throws -> Started in
            guard #available(tvOS 17.0, visionOS 2.1, *) else {
                throw CameraPermission.unavailable
            }
            self.request += 1
            let request = self.request
            try await Permissions.require("camera", on: context)
            let device = try await CameraDevices.find(id: params.camera, facing: params.facing, context: context)
            guard request == self.request else {
                throw HaylenFailure("The camera stopped or started again before this start ended.", code: "cancelled")
            }
            guard let stream = context.openVideoStream("camera", width: 0, height: 0, format: .BGRA8) else {
                throw HaylenFailure("The video stream \"camera\" did not open.", code: "cameraFailed")
            }

            self.stopCapture()
            let capture = try CameraCapture(device: device, width: params.width, height: params.height, stream: stream) { message in
                try? context.emit("stopped", Stopped(message: message, code: "cameraFailed"))
            }
            self.capture = capture
            let size = capture.size
            return Started(id: device.uniqueID, name: device.localizedName, facing: CameraDevices.facing(of: device), width: size.width, height: size.height)
        }

        context.register("stop") { [unowned self] (_: Empty) async throws -> Empty? in
            self.request += 1
            self.stopCapture()
            return nil
        }

        // Bytes travel next to the JSON, so the photo answers a dictionary with `Data` instead of a `Codable` value.
        context.registerHandler("takePhoto") { [unowned self] _, reply in
            guard #available(tvOS 17.0, visionOS 2.1, *) else {
                reply(false, ["message": CameraPermission.unavailable.message, "code": "unsupported"])
                return
            }
            guard let capture = self.capture else {
                reply(false, ["message": "The camera is off. Call \"camera.start\" first.", "code": "cameraOff"])
                return
            }
            do throws(HaylenFailure) {
                guard let photo = try capture.photo() else {
                    reply(false, ["message": "The camera has no frame yet.", "code": "noFrame"])
                    return
                }
                reply(true, ["jpeg": photo.jpeg, "width": photo.width, "height": photo.height])
            } catch {
                reply(false, ["message": error.message, "code": "cameraFailed"])
            }
        }
    }

    private func stopCapture() {
        guard #available(tvOS 17.0, visionOS 2.1, *) else {
            return
        }
        capture?.stop()
        capture = nil
    }
}
