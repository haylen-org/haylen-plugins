// The microphone of macOS: the input of AVAudioEngine as mono samples at the rate the app asks for, and the permission `microphone` of AVFoundation. The player runs without a bundle of its own, so macOS asks for the microphone in the name of the app that started it, such as the terminal. The frame thread is the main thread of AppKit, so the handlers and the answers of the prompt run there.

#import <AVFoundation/AVFoundation.h>

#include "MicrophoneDevice.hpp"
#include "MicrophonePlugin.hpp"

#include <string>
#include <string_view>

// The recording of AVAudioEngine, whose input arrives as blocks of 32-bit floats on the thread of the audio system, which AVAudioConverter turns into mono samples at the rate of the stream before they enter it. A change of the input, such as a headset plugged in or out, stops the engine and sends the event `microphone.stopped`.
@interface MicrophoneRecording : NSObject

- (instancetype)initWithPlugin:(const MicrophonePlugin*)owner stream:(const std::string&)name sampleRate:(int)sampleRate failure:(std::string&)failure code:(std::string&)code;
- (void)stop;

@end

@implementation MicrophoneRecording {
    const MicrophonePlugin* plugin;
    AVAudioEngine* engine;
    AVAudioConverter* converter;
    AVAudioPCMBuffer* converted;
    HaylenNativeAudioStream* stream;
    id configurationChanges;
}

- (instancetype)initWithPlugin:(const MicrophonePlugin*)owner stream:(const std::string&)name sampleRate:(int)sampleRate failure:(std::string&)failure code:(std::string&)code {
    self = [super init];
    plugin = owner;
    engine = [[AVAudioEngine alloc] init];
    AVAudioFormat* input = [engine.inputNode outputFormatForBus:0];
    if (input.sampleRate <= 0 || input.channelCount == 0) {
        failure = "This device has no microphone.";
        code = "unsupported";
        return nil;
    }

    AVAudioFormat* format = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32 sampleRate:sampleRate channels:1 interleaved:NO];
    converter = [[AVAudioConverter alloc] initFromFormat:input toFormat:format];
    converted = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:static_cast<AVAudioFrameCount>(sampleRate / 2)];
    stream = plugin->getApi().openAudioStream("microphone", name.c_str(), sampleRate, 1, HAYLEN_NATIVE_SAMPLES_FLOAT32, sampleRate);
    code = "microphoneFailed";
    if (converter == nil || converted == nil) {
        failure = "The microphone cannot record mono samples at " + std::to_string(sampleRate) + " Hz.";
        return nil;
    }
    if (stream == nullptr) {
        failure = "The audio stream \"" + name + "\" did not open.";
        return nil;
    }
    converter.downmix = YES;

    // The notification center keeps its block, so the block holds the plugin instead of the recording.
    __weak MicrophoneRecording* recording = self;
    const MicrophonePlugin* events = plugin;
    [engine.inputNode installTapOnBus:0 bufferSize:1024 format:input block:^(AVAudioPCMBuffer* buffer, AVAudioTime*) { [recording push:buffer]; }];
    // clang-format off
    configurationChanges = [NSNotificationCenter.defaultCenter addObserverForName:AVAudioEngineConfigurationChangeNotification object:engine queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*) {
        events->emit("microphone.stopped", {{"message", "The input of the microphone changed, such as a headset that was plugged in or out, which stopped the recording."}, {"code", "microphoneFailed"}});
    }];
    // clang-format on

    NSError* error = nil;
    if (![engine startAndReturnError:&error]) {
        [self stop];
        failure = "The microphone did not start: " + std::string(error.localizedDescription.UTF8String);
        return nil;
    }
    return self;
}

- (void)stop {
    [NSNotificationCenter.defaultCenter removeObserver:configurationChanges];
    [engine.inputNode removeTapOnBus:0];
    [engine stop];
}

// Hands the converter the one block of the tap, and pushes what it gives back.
- (void)push:(AVAudioPCMBuffer*)buffer {
    __block BOOL handed = NO;
    converted.frameLength = 0;
    // clang-format off
    AVAudioConverterOutputStatus status = [converter convertToBuffer:converted error:nil withInputFromBlock:^AVAudioBuffer*(AVAudioPacketCount, AVAudioConverterInputStatus* state) {
        if (handed) {
            *state = AVAudioConverterInputStatus_NoDataNow;
            return nil;
        }
        handed = YES;
        *state = AVAudioConverterInputStatus_HaveData;
        return buffer;
    }];
    // clang-format on
    if (status != AVAudioConverterOutputStatus_Error) {
        plugin->getApi().pushAudioFrames(stream, converted.floatChannelData[0], converted.frameLength);
    }
}

@end

struct MicrophoneDevice::System {
    const MicrophonePlugin& plugin;
    MicrophoneRecording* recording = nil;

    static std::string_view describe(AVAuthorizationStatus status) {
        switch (status) {
        case AVAuthorizationStatusNotDetermined:
            return "prompt";
        case AVAuthorizationStatusAuthorized:
            return "granted";
        case AVAuthorizationStatusDenied:
        case AVAuthorizationStatusRestricted:
            return "denied";
        }
        return "unknown";
    }

    void stopRecording() {
        [recording stop];
        recording = nil;
    }

    // Starts the recording once the process holds the microphone, after the prompt of the system where it does not hold it yet, and fails the call with the code `denied` otherwise.
    void start(std::uint64_t call, int sampleRate) {
        const AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
        if (status == AVAuthorizationStatusAuthorized) {
            record(call, sampleRate);
            return;
        }
        if (status != AVAuthorizationStatusNotDetermined) {
            plugin.fail(call, MicrophonePlugin::kRefusal, "denied");
            return;
        }

        System* recorder = this;
        // clang-format off
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL allowed) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!allowed) {
                    recorder->plugin.fail(call, MicrophonePlugin::kRefusal, "denied");
                    return;
                }
                recorder->record(call, sampleRate);
            });
        }];
        // clang-format on
    }

    void record(std::uint64_t call, int sampleRate) {
        stopRecording();
        const std::string name = "microphone-" + std::to_string(sampleRate);
        std::string failure;
        std::string code;
        MicrophoneRecording* started = [[MicrophoneRecording alloc] initWithPlugin:&plugin stream:name sampleRate:sampleRate failure:failure code:code];
        if (started == nil) {
            plugin.fail(call, failure, code);
            return;
        }
        recording = started;
        plugin.succeed(call, {{"sampleRate", sampleRate}, {"channels", 1}, {"stream", name}});
    }
};

MicrophoneDevice::MicrophoneDevice(const MicrophonePlugin& owner) : system(std::make_unique<System>(System{.plugin = owner})) {}

MicrophoneDevice::~MicrophoneDevice() = default;

void MicrophoneDevice::start(std::uint64_t call, int sampleRate) {
    system->start(call, sampleRate);
}

void MicrophoneDevice::stop(std::uint64_t call) {
    system->stopRecording();
    system->plugin.succeed(call, nullptr);
}

// Reads the state of the permission without asking, the state that macOS keeps for the app that started the player.
void MicrophoneDevice::permission(std::uint64_t call) {
    const AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    system->plugin.succeed(call, System::describe(status));
}

void MicrophoneDevice::requestPermission(std::uint64_t call) {
    const AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    if (status != AVAuthorizationStatusNotDetermined) {
        system->plugin.succeed(call, System::describe(status));
        return;
    }

    const MicrophonePlugin* plugin = &system->plugin;
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL allowed) { plugin->succeed(call, allowed ? "granted" : "denied"); }];
}
