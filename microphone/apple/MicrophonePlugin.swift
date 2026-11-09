import AVFoundation
import Foundation

// Native part of the Microphone plugin on Apple platforms: the input of AVAudioEngine as mono samples at the rate the app asks for, into an audio stream named after its rate, and the permission `microphone`. Apple TV takes a microphone from tvOS 17 on, the one of an iPhone or an iPad that the person connects in the picker of the Continuity Camera.
@objc(MicrophonePlugin)
final class MicrophonePlugin: NSObject, HaylenPlugin {
    struct Empty: Codable {}

    struct Start: Decodable {
        let sampleRate: Int
    }

    struct Started: Encodable {
        let sampleRate: Int
        let channels: Int
        let stream: String
    }

    struct Stopped: Encodable {
        let message: String
        let code: String
    }

    // The recording of AVAudioEngine exists on Apple TV from tvOS 17 on, so the plugin keeps it as an object and reads it back through `recording`.
    private var recordingObject: AnyObject?

    @available(tvOS 17.0, *)
    private var recording: MicrophoneRecording? {
        get { recordingObject as? MicrophoneRecording }
        set { recordingObject = newValue }
    }

    func load(with context: HaylenPluginContext) {
        Permissions.register(MicrophonePermission.make(), on: context)

        // Every app that loads the Lua API sends `reset`, so a recording that an earlier app of the process left running stops.
        context.register("reset") { [unowned self] (_: Empty) async throws -> Empty? in
            self.stopRecording()
            return nil
        }

        context.register("start") { [unowned self] (params: Start) async throws -> Started in
            guard #available(tvOS 17.0, *) else {
                throw MicrophonePermission.unavailable
            }
            try await Permissions.require("microphone", on: context)
            #if os(tvOS)
            try await MicrophoneContinuityPicker.connect(context)
            #endif

            self.stopRecording()
            let name = "microphone-\(params.sampleRate)"
            let recording = try MicrophoneRecording(context: context, stream: name, sampleRate: params.sampleRate) { message in
                try? context.emit("stopped", Stopped(message: message, code: "microphoneFailed"))
            }
            self.recording = recording
            return Started(sampleRate: params.sampleRate, channels: 1, stream: name)
        }

        context.register("stop") { [unowned self] (_: Empty) async throws -> Empty? in
            self.stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        guard #available(tvOS 17.0, *) else {
            return
        }
        recording?.stop()
        recording = nil
    }
}
