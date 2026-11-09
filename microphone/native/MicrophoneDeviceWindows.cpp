// The microphone of Windows: the default microphone of WASAPI as mono floats, and the permission `microphone`, which the capability `microphone` of the privacy settings of Windows answers. The handlers hand their work to a thread of the library in the multithreaded apartment of COM, which answers the calls, and each recording reads its samples on a thread of its own.

#define NOMINMAX
#include <windows.h>

#include <audioclient.h>
#include <mmdeviceapi.h>
#include <roapi.h>
#include <windows.foundation.h>
#include <windows.security.authorization.appcapabilityaccess.h>
#include <wrl/client.h>
#include <wrl/event.h>
#include <wrl/wrappers/corewrappers.h>

#include "MicrophoneDevice.hpp"
#include "MicrophonePlugin.hpp"

#include <charconv>
#include <condition_variable>
#include <deque>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

using ABI::Windows::Foundation::AsyncStatus;
using ABI::Windows::Foundation::IAsyncOperation;
using ABI::Windows::Foundation::IAsyncOperationCompletedHandler;
using ABI::Windows::Security::Authorization::AppCapabilityAccess::AppCapabilityAccessStatus;
using ABI::Windows::Security::Authorization::AppCapabilityAccess::IAppCapability;
using ABI::Windows::Security::Authorization::AppCapabilityAccess::IAppCapabilityStatics;
using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;
using Microsoft::WRL::Wrappers::Event;
using Microsoft::WRL::Wrappers::HandleT;
using Microsoft::WRL::Wrappers::HStringReference;
using Microsoft::WRL::Wrappers::HandleTraits::EventTraits;

struct MicrophoneDevice::System {
    // A thread of the library that runs its jobs in order, in the multithreaded apartment of COM, where WASAPI and the Windows Runtime work.
    class Worker final {
      public:
        Worker() : thread(&Worker::run, this) {}

        void post(std::function<void()> job) {
            {
                const std::lock_guard<std::mutex> guard(mutex);
                jobs.push_back(std::move(job));
            }
            wake.notify_one();
        }

      private:
        void run() {
            RoInitialize(RO_INIT_MULTITHREADED);
            for (;;) {
                std::function<void()> job;
                {
                    std::unique_lock<std::mutex> guard(mutex);
                    wake.wait(guard, [this] { return !jobs.empty(); });
                    job = std::move(jobs.front());
                    jobs.pop_front();
                }
                job();
            }
        }

        std::mutex mutex;
        std::condition_variable wake;
        std::deque<std::function<void()>> jobs;
        std::thread thread;
    };

    // The permission `microphone`, which the capability `microphone` of the privacy settings of Windows answers. Windows shows its prompt only while the settings ask the person, and a Windows without `AppCapability` tells nothing until the app opens the microphone.
    class Capability final {
      public:
        struct Answer {
            std::string state;
            std::string message;
        };

        static Answer check() {
            ComPtr<IAppCapability> capability = create();
            AppCapabilityAccessStatus status{};
            if (!capability || FAILED(capability->CheckAccess(&status))) {
                return {.state = "unknown", .message = ""};
            }
            return answer(status);
        }

        static Answer request() {
            ComPtr<IAppCapability> capability = create();
            AppCapabilityAccessStatus status{};
            if (!capability || FAILED(capability->CheckAccess(&status))) {
                return {.state = "unknown", .message = ""};
            }
            if (status != AppCapabilityAccessStatus::AppCapabilityAccessStatus_UserPromptRequired) {
                return answer(status);
            }

            ComPtr<IAsyncOperation<AppCapabilityAccessStatus>> operation;
            if (FAILED(capability->RequestAccessAsync(&operation))) {
                return {.state = "prompt", .message = ""};
            }
            if (wait(operation.Get()) != AsyncStatus::Completed || FAILED(operation->GetResults(&status))) {
                return {.state = "unknown", .message = ""};
            }
            return answer(status);
        }

      private:
        static ComPtr<IAppCapability> create() {
            ComPtr<IAppCapabilityStatics> statics;
            const HStringReference className(RuntimeClass_Windows_Security_Authorization_AppCapabilityAccess_AppCapability);
            if (FAILED(RoGetActivationFactory(className.Get(), IID_PPV_ARGS(&statics)))) {
                return nullptr;
            }

            ComPtr<IAppCapability> capability;
            if (FAILED(statics->Create(HStringReference(L"microphone").Get(), &capability))) {
                return nullptr;
            }
            return capability;
        }

        // Waits on the thread of the library for the operation and returns its status, which `GetResults` follows.
        static AsyncStatus wait(IAsyncOperation<AppCapabilityAccessStatus>* operation) {
            Event finished(CreateEventExW(nullptr, nullptr, CREATE_EVENT_MANUAL_RESET, EVENT_ALL_ACCESS));
            AsyncStatus outcome = AsyncStatus::Error;
            // clang-format off
            const auto completed = Callback<IAsyncOperationCompletedHandler<AppCapabilityAccessStatus>>([&finished, &outcome](IAsyncOperation<AppCapabilityAccessStatus>*, AsyncStatus status) {
                outcome = status;
                SetEvent(finished.Get());
                return S_OK;
            });
            // clang-format on
            if (FAILED(operation->put_Completed(completed.Get()))) {
                return AsyncStatus::Error;
            }
            WaitForSingleObject(finished.Get(), INFINITE);
            return outcome;
        }

        // The two refusals of `AppCapabilityAccessStatus` are the setting of the person and the one of the system or its policy.
        static Answer answer(AppCapabilityAccessStatus status) {
            switch (status) {
            case AppCapabilityAccessStatus::AppCapabilityAccessStatus_Allowed:
                return {.state = "granted", .message = ""};
            case AppCapabilityAccessStatus::AppCapabilityAccessStatus_UserPromptRequired:
                return {.state = "prompt", .message = ""};
            case AppCapabilityAccessStatus::AppCapabilityAccessStatus_DeniedByUser:
            case AppCapabilityAccessStatus::AppCapabilityAccessStatus_DeniedBySystem:
                return {.state = "denied", .message = ""};
            case AppCapabilityAccessStatus::AppCapabilityAccessStatus_NotDeclaredByApp:
                return {.state = "unsupported", .message = "The app does not declare the capability \"microphone\" of Windows."};
            }
            return {.state = "unknown", .message = ""};
        }
    };

    // The recording of the default microphone through WASAPI in shared mode, which converts the samples of the device into mono floats at the rate the app asked for. A thread of its own waits for each packet and pushes it into the audio stream of that rate.
    class Recording final {
      public:
        struct Opened {
            std::unique_ptr<Recording> recording;
            std::string message;
            std::string code = "microphoneFailed";
        };

        // Opens the default microphone with its samples converted to the rate, or returns the reason it cannot.
        static Opened open(const MicrophonePlugin& plugin, int rate) {
            ComPtr<IMMDeviceEnumerator> devices;
            ComPtr<IMMDevice> device;
            ComPtr<IAudioClient> audioClient;
            if (const HRESULT result = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&devices)); FAILED(result)) {
                return {.recording = nullptr, .message = "The audio devices of Windows did not open, and WASAPI answered " + describe(result) + "."};
            }
            if (FAILED(devices->GetDefaultAudioEndpoint(eCapture, eConsole, &device))) {
                return {.recording = nullptr, .message = "This device has no microphone.", .code = "unsupported"};
            }
            if (const HRESULT result = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, &audioClient); FAILED(result)) {
                return {.recording = nullptr, .message = "The microphone did not open, and WASAPI answered " + describe(result) + "."};
            }

            WAVEFORMATEX format{};
            format.wFormatTag = WAVE_FORMAT_IEEE_FLOAT;
            format.nChannels = 1;
            format.nSamplesPerSec = static_cast<DWORD>(rate);
            format.wBitsPerSample = 32;
            format.nBlockAlign = 4;
            format.nAvgBytesPerSec = static_cast<DWORD>(rate) * 4;
            const DWORD flags = AUDCLNT_STREAMFLAGS_EVENTCALLBACK | AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY;
            if (const HRESULT result = audioClient->Initialize(AUDCLNT_SHAREMODE_SHARED, flags, kBufferDuration, 0, &format, nullptr); FAILED(result)) {
                return {.recording = nullptr, .message = "The microphone does not record at " + std::to_string(rate) + " Hz, and WASAPI answered " + describe(result) + "."};
            }

            HandleT<EventTraits> packetReady(CreateEventExW(nullptr, nullptr, 0, EVENT_ALL_ACCESS));
            ComPtr<IAudioCaptureClient> captureClient;
            if (FAILED(audioClient->SetEventHandle(packetReady.Get())) || FAILED(audioClient->GetService(IID_PPV_ARGS(&captureClient)))) {
                return {.recording = nullptr, .message = "The microphone cannot deliver samples to the app."};
            }
            const std::string name = "microphone-" + std::to_string(rate);
            HaylenNativeAudioStream* audioStream = plugin.getApi().openAudioStream("microphone", name.c_str(), rate, 1, HAYLEN_NATIVE_SAMPLES_FLOAT32, rate);
            if (audioStream == nullptr) {
                return {.recording = nullptr, .message = "The audio stream \"" + name + "\" did not open."};
            }
            if (const HRESULT result = audioClient->Start(); FAILED(result)) {
                return {.recording = nullptr, .message = "The microphone did not start, and WASAPI answered " + describe(result) + "."};
            }
            return {.recording = std::unique_ptr<Recording>(new Recording(plugin, audioClient, captureClient, std::move(packetReady), audioStream, rate)), .message = ""};
        }

        ~Recording() {
            SetEvent(stopping.Get());
            reader.join();
            client->Stop();
        }

        Recording(const Recording&) = delete;
        Recording& operator=(const Recording&) = delete;

        [[nodiscard]] int getSampleRate() const {
            return sampleRate;
        }

      private:
        // The shared buffer holds a fifth of a second, in the units of a hundred nanoseconds of WASAPI.
        static constexpr REFERENCE_TIME kBufferDuration = 2000000;

        Recording(const MicrophonePlugin& owner, ComPtr<IAudioClient> audioClient, ComPtr<IAudioCaptureClient> captureClient, HandleT<EventTraits> packetReady, HaylenNativeAudioStream* audioStream, int rate) : plugin(owner), client(std::move(audioClient)), capture(std::move(captureClient)), ready(std::move(packetReady)), stopping(CreateEventExW(nullptr, nullptr, CREATE_EVENT_MANUAL_RESET, EVENT_ALL_ACCESS)), stream(audioStream), sampleRate(rate), reader(&Recording::read, this) {}

        static std::string describe(HRESULT result) {
            char text[16];
            const auto written = std::to_chars(text, text + sizeof(text), static_cast<std::uint32_t>(result), 16);
            return "0x" + std::string(text, written.ptr);
        }

        void read() {
            RoInitialize(RO_INIT_MULTITHREADED);
            const HANDLE waits[] = {stopping.Get(), ready.Get()};
            std::vector<float> silence;
            while (WaitForMultipleObjects(2, waits, FALSE, INFINITE) == WAIT_OBJECT_0 + 1) {
                if (!drain(silence)) {
                    plugin.emit("microphone.stopped", {{"message", "The microphone went away, such as when the person unplugged it."}, {"code", "microphoneFailed"}});
                    break;
                }
            }
            RoUninitialize();
        }

        // Pushes every packet that waits, with silence for the packets that WASAPI marks silent, and returns false once the device went away.
        bool drain(std::vector<float>& silence) {
            for (;;) {
                UINT32 waiting = 0;
                if (FAILED(capture->GetNextPacketSize(&waiting))) {
                    return false;
                }
                if (waiting == 0) {
                    return true;
                }

                BYTE* samples = nullptr;
                UINT32 frames = 0;
                DWORD flags = 0;
                if (FAILED(capture->GetBuffer(&samples, &frames, &flags, nullptr, nullptr))) {
                    return false;
                }
                if ((flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0) {
                    silence.assign(frames, 0.0f);
                    plugin.getApi().pushAudioFrames(stream, silence.data(), frames);
                } else {
                    plugin.getApi().pushAudioFrames(stream, samples, frames);
                }
                capture->ReleaseBuffer(frames);
            }
        }

        const MicrophonePlugin& plugin;
        ComPtr<IAudioClient> client;
        ComPtr<IAudioCaptureClient> capture;
        HandleT<EventTraits> ready;
        HandleT<EventTraits> stopping;
        HaylenNativeAudioStream* stream;
        const int sampleRate;
        std::thread reader;
    };

    // Answers `microphone.permission` and `microphone.requestPermission` with the name of the state, or fails them with the code `unsupported` and the reason.
    void answerPermission(std::uint64_t call, const Capability::Answer& given) const {
        if (given.state == "unsupported") {
            plugin.fail(call, given.message, "unsupported");
            return;
        }
        plugin.succeed(call, given.state);
    }

    // Asks for the microphone where the app does not hold it yet, and fails the call where the person or the system refuses it. A Windows that tells nothing lets the use try.
    bool require(std::uint64_t call) const {
        const Capability::Answer answer = Capability::request();
        if (answer.state == "granted" || answer.state == "unknown") {
            return true;
        }
        if (answer.state == "unsupported") {
            plugin.fail(call, answer.message, "unsupported");
            return false;
        }
        plugin.fail(call, MicrophonePlugin::kRefusal, "denied");
        return false;
    }

    void start(std::uint64_t call, int sampleRate) {
        if (!require(call)) {
            return;
        }
        recording.reset();
        Recording::Opened opened = Recording::open(plugin, sampleRate);
        if (!opened.recording) {
            plugin.fail(call, opened.message, opened.code);
            return;
        }

        recording = std::move(opened.recording);
        const int rate = recording->getSampleRate();
        plugin.succeed(call, {{"sampleRate", rate}, {"channels", 1}, {"stream", "microphone-" + std::to_string(rate)}});
    }

    const MicrophonePlugin& plugin;
    // Only the worker touches the recording, which lives as long as the process, since the engine may still call the library while the process exits.
    Worker worker;
    std::unique_ptr<Recording> recording;
};

MicrophoneDevice::MicrophoneDevice(const MicrophonePlugin& owner) : system(new System{.plugin = owner}) {}

MicrophoneDevice::~MicrophoneDevice() = default;

void MicrophoneDevice::start(std::uint64_t call, int sampleRate) {
    System* recorder = system.get();
    recorder->worker.post([recorder, call, sampleRate] { recorder->start(call, sampleRate); });
}

void MicrophoneDevice::stop(std::uint64_t call) {
    System* recorder = system.get();
    // clang-format off
    recorder->worker.post([recorder, call] {
        recorder->recording.reset();
        recorder->plugin.succeed(call, nullptr);
    });
    // clang-format on
}

void MicrophoneDevice::permission(std::uint64_t call) {
    System* recorder = system.get();
    recorder->worker.post([recorder, call] { recorder->answerPermission(call, System::Capability::check()); });
}

void MicrophoneDevice::requestPermission(std::uint64_t call) {
    System* recorder = system.get();
    recorder->worker.post([recorder, call] { recorder->answerPermission(call, System::Capability::request()); });
}
