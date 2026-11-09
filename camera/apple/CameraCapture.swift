import AVFoundation
import Foundation
import ImageIO

#if os(iOS) && !targetEnvironment(macCatalyst)
import UIKit
#endif

// The capture of one camera through AVFoundation, whose BGRA frames arrive on a dispatch queue of its own, which pushes them into the stream and keeps the newest one for a photo. The camera takes the format whose size is the closest to the one the app asked for. On iPhones and iPads the frames turn with the device so the picture stays upright, and the front camera shows a mirror image like the camera app of the system. It is safe to share between threads, since the session starts and stops only on its queue once it is configured, the newest frame sits behind the lock, the stream takes frames from any thread and everything else belongs to the main actor.
@available(tvOS 17.0, visionOS 2.1, *)
final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let stream: HaylenVideoStream
    private let queue = DispatchQueue(label: "com.haylen.plugins.camera.capture")
    private let lock = NSLock()
    private var newest: CVPixelBuffer?
    private var runtimeErrors: NSObjectProtocol?
    private let dimensions: CMVideoDimensions
    #if os(iOS) && !targetEnvironment(macCatalyst)
    private var rotation: AnyObject?
    private var rotationObservation: NSKeyValueObservation?
    #endif

    @MainActor
    init(device: AVCaptureDevice, width: Int, height: Int, stream: HaylenVideoStream, failed: @escaping @Sendable (String) -> Void) throws {
        self.stream = stream
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw HaylenFailure("The camera \"\(device.localizedName)\" did not open: \(error.localizedDescription)", code: "cameraFailed")
        }
        guard let format = Self.closestFormat(of: device, width: width, height: height) else {
            throw HaylenFailure("The camera \"\(device.localizedName)\" offers no format of video.", code: "cameraFailed")
        }
        dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        super.init()

        session.beginConfiguration()
        #if os(iOS)
        // The format of the device decides the size of the frames instead of a preset of the session.
        session.sessionPreset = .inputPriority
        #endif
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw HaylenFailure("The camera \"\(device.localizedName)\" cannot deliver frames to the app.", code: "cameraFailed")
        }
        session.addInput(input)
        #if os(macOS)
        // The session of macOS keeps the size of its preset whatever format the device takes, so the output scales its frames to the size of the format.
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: Int(dimensions.width), kCVPixelBufferHeightKey as String: Int(dimensions.height)]
        #else
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        #endif
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw HaylenFailure("The camera \"\(device.localizedName)\" cannot deliver frames to the app.", code: "cameraFailed")
        }
        session.addOutput(output)
        orient(device: device)
        session.commitConfiguration()
        // The session applies its preset as it commits, so the format of the device follows the commit and decides the size of the frames.
        try Self.activate(format, of: device)

        runtimeErrors = NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
            failed("The camera stopped: \(error?.localizedDescription ?? "AVFoundation gave no reason").")
        }
        queue.async {
            self.session.startRunning()
        }
    }

    // The size of the frames that the stream receives, turned with the device on iPhones and iPads.
    @MainActor
    var size: (width: Int, height: Int) {
        let width = Int(dimensions.width)
        let height = Int(dimensions.height)
        guard let connection = output.connection(with: .video) else {
            return (width, height)
        }
        return Self.isQuarterTurn(connection) ? (height, width) : (width, height)
    }

    @MainActor
    func stop() {
        if let runtimeErrors {
            NotificationCenter.default.removeObserver(runtimeErrors)
        }
        #if os(iOS) && !targetEnvironment(macCatalyst)
        rotationObservation?.invalidate()
        #endif
        queue.async {
            self.session.stopRunning()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        lock.lock()
        newest = buffer
        lock.unlock()
        stream.push(buffer, timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds)
    }

    // Encodes the newest frame as a JPEG file with ImageIO, or returns nil before the first frame.
    func photo() throws(HaylenFailure) -> (jpeg: Data, width: Int, height: Int)? {
        lock.lock()
        let buffer = newest
        lock.unlock()
        guard let buffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let pixels = CVPixelBufferGetBaseAddress(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let bitmap = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw Self.unencoded
        }
        guard let context = CGContext(data: pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: space, bitmapInfo: bitmap), let image = context.makeImage() else {
            throw Self.unencoded
        }

        let jpeg = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(jpeg as CFMutableData, "public.jpeg" as CFString, 1, nil) else {
            throw Self.unencoded
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw Self.unencoded
        }
        return (jpeg as Data, width, height)
    }

    private static let unencoded = HaylenFailure("The frame of the camera did not encode as a JPEG file.", code: "cameraFailed")

    private static func closestFormat(of device: AVCaptureDevice, width: Int, height: Int) -> AVCaptureDevice.Format? {
        device.formats.min { first, second in
            distance(first, width: width, height: height) < distance(second, width: width, height: height)
        }
    }

    private static func distance(_ format: AVCaptureDevice.Format, width: Int, height: Int) -> Int {
        let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return abs(Int(size.width) - width) + abs(Int(size.height) - height)
    }

    private static func activate(_ format: AVCaptureDevice.Format, of device: AVCaptureDevice) throws {
        do {
            try device.lockForConfiguration()
        } catch {
            throw HaylenFailure("The camera \"\(device.localizedName)\" refused its format: \(error.localizedDescription)", code: "cameraFailed")
        }
        device.activeFormat = format
        device.unlockForConfiguration()
    }

    private static func isQuarterTurn(_ connection: AVCaptureConnection) -> Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        if #available(iOS 17.0, *) {
            return Int(connection.videoRotationAngle) % 180 != 0
        }
        return connection.videoOrientation == .portrait || connection.videoOrientation == .portraitUpsideDown
        #else
        return false
        #endif
    }

    // Turns the frames of iPhones and iPads with the device, with the rotation coordinator of AVFoundation from iOS 17 on and with the orientation of the interface at the start before, and mirrors the front camera.
    @MainActor
    private func orient(device: AVCaptureDevice) {
        guard let connection = output.connection(with: .video) else {
            return
        }
        #if !os(visionOS)
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = device.position == .front
        }
        #endif

        #if os(iOS) && !targetEnvironment(macCatalyst)
        if #available(iOS 17.0, *) {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
            connection.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelCapture
            rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { @Sendable [weak self] coordinator, _ in
                let angle = coordinator.videoRotationAngleForHorizonLevelCapture
                DispatchQueue.main.async {
                    self?.rotate(to: angle)
                }
            }
            rotation = coordinator
            return
        }
        let interface = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.interfaceOrientation }.first ?? .portrait
        let orientations: [UIInterfaceOrientation: AVCaptureVideoOrientation] = [.portrait: .portrait, .portraitUpsideDown: .portraitUpsideDown, .landscapeLeft: .landscapeLeft, .landscapeRight: .landscapeRight]
        if connection.isVideoOrientationSupported, let orientation = orientations[interface] {
            connection.videoOrientation = orientation
        }
        #endif
    }

    #if os(iOS) && !targetEnvironment(macCatalyst)
    @available(iOS 17.0, *)
    @MainActor
    private func rotate(to angle: CGFloat) {
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }
    #endif
}
