import AVFoundation
import Foundation

#if os(tvOS)
import AVKit
import UIKit
#endif

// The recording of AVAudioEngine, whose input arrives as blocks of 32-bit floats on the thread of the audio system, which AVAudioConverter turns into mono samples at the rate of the stream before they enter it. A change of the input, such as a headset plugged in or out, stops the recording, and `failed` tells why. It is safe to share between threads, since only the thread of the audio system converts and pushes the samples, while the engine and the session start and stop on the main actor.
@available(tvOS 17.0, *)
final class MicrophoneRecording: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let stream: HaylenAudioStream
    private let converter: AVAudioConverter
    private let converted: AVAudioPCMBuffer
    private var configurationChanges: NSObjectProtocol?
    #if !os(macOS)
    private let category: AVAudioSession.Category
    private let options: AVAudioSession.CategoryOptions
    #endif

    @MainActor
    init(context: HaylenPluginContext, stream name: String, sampleRate: Int, failed: @escaping @Sendable (String) -> Void) throws {
        #if !os(macOS)
        // Recording needs a session that records, which mixes with the sound of the app, and the session of the app comes back when the microphone stops.
        let session = AVAudioSession.sharedInstance()
        category = session.category
        options = session.categoryOptions
        do {
            try session.setCategory(.playAndRecord, options: Self.sessionOptions)
            try session.setActive(true)
        } catch {
            throw HaylenFailure("The audio session refused to record: \(error.localizedDescription)", code: "microphoneFailed")
        }
        #endif

        let input = engine.inputNode.outputFormat(forBus: 0)
        do {
            (converter, converted) = try Self.makeConverter(from: input, sampleRate: sampleRate)
            stream = try Self.openStream(context: context, name: name, sampleRate: sampleRate)
        } catch {
            #if !os(macOS)
            Self.restoreSession(category: category, options: options)
            #endif
            throw error
        }

        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: input) { @Sendable [unowned self] buffer, _ in
            self.push(buffer)
        }
        configurationChanges = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { _ in
            failed("The input of the microphone changed, such as a headset that was plugged in or out, which stopped the recording.")
        }
        do {
            try engine.start()
        } catch {
            stop()
            throw HaylenFailure("The microphone did not start: \(error.localizedDescription)", code: "microphoneFailed")
        }
    }

    @MainActor
    func stop() {
        if let configurationChanges {
            NotificationCenter.default.removeObserver(configurationChanges)
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        #if !os(macOS)
        Self.restoreSession(category: category, options: options)
        #endif
    }

    // The converter of the input to mono samples at the rate, and the buffer of half a second that it converts into.
    private static func makeConverter(from input: AVAudioFormat, sampleRate: Int) throws -> (AVAudioConverter, AVAudioPCMBuffer) {
        guard input.sampleRate > 0, input.channelCount > 0 else {
            throw HaylenFailure("This device has no microphone.", code: "unsupported")
        }

        let unsupportedRate = HaylenFailure("The microphone cannot record mono samples at \(sampleRate) Hz.", code: "microphoneFailed")
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: 1, interleaved: false) else {
            throw unsupportedRate
        }
        guard let converter = AVAudioConverter(from: input, to: format) else {
            throw unsupportedRate
        }
        guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleRate / 2)) else {
            throw unsupportedRate
        }
        converter.downmix = true
        return (converter, converted)
    }

    private static func openStream(context: HaylenPluginContext, name: String, sampleRate: Int) throws -> HaylenAudioStream {
        guard let stream = context.openAudioStream(name, sampleRate: sampleRate, channels: 1, format: .float32, capacity: sampleRate) else {
            throw HaylenFailure("The audio stream \"\(name)\" did not open.", code: "microphoneFailed")
        }
        return stream
    }

    #if !os(macOS)
    // Gives the app back the audio session it had before the microphone started.
    private static func restoreSession(category: AVAudioSession.Category, options: AVAudioSession.CategoryOptions) {
        try? AVAudioSession.sharedInstance().setCategory(category, options: options)
    }
    #endif

    // Hands the converter the one block of the tap, and pushes what it gives back.
    private func push(_ buffer: AVAudioPCMBuffer) {
        var handed = false
        var failure: NSError?
        converted.frameLength = 0
        let status = converter.convert(to: converted, error: &failure) { _, state in
            if handed {
                state.pointee = .noDataNow
                return nil
            }
            handed = true
            state.pointee = .haveData
            return buffer
        }
        guard status != .error, let samples = converted.floatChannelData?[0] else {
            return
        }
        stream.push(samples, frames: Int(converted.frameLength))
    }

    #if os(iOS) || os(visionOS)
    private static let sessionOptions: AVAudioSession.CategoryOptions = [.mixWithOthers, .defaultToSpeaker]
    #elseif os(tvOS)
    private static let sessionOptions: AVAudioSession.CategoryOptions = [.mixWithOthers]
    #endif
}

#if os(tvOS)
// The picker of the system in which the person connects an iPhone or an iPad whose microphone the Apple TV records, shown only while the Apple TV has no input. It covers the app while it shows. UIKit calls its delegate on the main thread, so the picker conforms to the delegate protocol on the main actor and takes the input of the connected device there.
@available(tvOS 17.0, *)
@MainActor
final class MicrophoneContinuityPicker: NSObject, @MainActor AVContinuityDevicePickerViewControllerDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private let controller = AVContinuityDevicePickerViewController()

    static func connect(_ context: HaylenPluginContext) async throws {
        let session = AVAudioSession.sharedInstance()
        if session.isInputAvailable {
            return
        }
        guard AVContinuityDevicePickerViewController.isSupported else {
            throw HaylenFailure("This Apple TV has no microphone and takes no Continuity Camera.", code: "unsupported")
        }
        guard let presenter = context.viewController else {
            throw HaylenFailure("The app has no window to show the picker of the Continuity Camera in.", code: "microphoneFailed")
        }

        let picker = MicrophoneContinuityPicker()
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
        finish(Self.record(from: device))
    }

    func continuityDevicePickerDidCancel(_ pickerViewController: AVContinuityDevicePickerViewController) {
        finish(.failure(HaylenFailure("The person closed the picker of the Continuity Camera without a device.", code: "cancelled")))
    }

    // Makes the microphone of the connected device the input of the audio session.
    private static func record(from device: AVContinuityDevice) -> Result<Void, Error> {
        guard let input = device.audioSessionInputs.first else {
            return .failure(HaylenFailure("The connected device gives the Apple TV no microphone.", code: "unsupported"))
        }
        do {
            try AVAudioSession.sharedInstance().setPreferredInput(input)
            return .success(())
        } catch {
            return .failure(HaylenFailure("The Apple TV refused the microphone of the connected device: \(error.localizedDescription)", code: "microphoneFailed"))
        }
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
