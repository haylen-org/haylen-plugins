// The microphone of Linux: the default capture device of ALSA as mono floats, whose plug layer converts the samples of the device to the rate the app asks for. Linux gates no microphone for an app outside a sandbox, so the permission `microphone` is granted and a request shows no prompt. A thread of the recording reads the samples.

#include "MicrophoneDevice.hpp"
#include "MicrophonePlugin.hpp"

#include <alsa/asoundlib.h>

#include <atomic>
#include <cerrno>
#include <string>
#include <thread>
#include <vector>

struct MicrophoneDevice::System {
    // The recording of the default capture device, whose blocks of a hundredth of a second its thread reads and pushes into the stream. The frame thread starts and stops it, and the thread reads only what never changes while it runs, besides the flag that stops it.
    class Recording final {
      public:
        struct Opened {
            std::unique_ptr<Recording> recording;
            std::string message;
            std::string code = "microphoneFailed";
        };

        // Opens the default capture device for mono floats at the rate, or returns the reason it does not. A system without a capture device answers `unsupported`.
        static Opened open(const MicrophonePlugin& plugin, int sampleRate) {
            snd_pcm_t* opened = nullptr;
            const int status = snd_pcm_open(&opened, "default", SND_PCM_STREAM_CAPTURE, SND_PCM_NONBLOCK);
            if (status < 0) {
                const bool absent = status == -ENOENT || status == -ENODEV || status == -ENXIO;
                const std::string reason = snd_strerror(status);
                if (absent) {
                    return {.recording = nullptr, .message = "This device has no microphone that ALSA opens: " + reason + ".", .code = "unsupported"};
                }
                return {.recording = nullptr, .message = "The microphone did not open: " + reason + "."};
            }
            Device device(opened, &snd_pcm_close);

            const int configured = snd_pcm_set_params(device.get(), SND_PCM_FORMAT_FLOAT_LE, SND_PCM_ACCESS_RW_INTERLEAVED, 1, static_cast<unsigned>(sampleRate), 1, kLatencyMicroseconds);
            if (configured < 0) {
                return {.recording = nullptr, .message = "The microphone refused mono samples at " + std::to_string(sampleRate) + " Hz: " + snd_strerror(configured) + "."};
            }

            const std::string name = "microphone-" + std::to_string(sampleRate);
            HaylenNativeAudioStream* stream = plugin.getApi().openAudioStream("microphone", name.c_str(), sampleRate, 1, HAYLEN_NATIVE_SAMPLES_FLOAT32, sampleRate);
            if (stream == nullptr) {
                return {.recording = nullptr, .message = "The microphone did not start: the audio stream did not open."};
            }
            const int started = snd_pcm_start(device.get());
            if (started < 0) {
                return {.recording = nullptr, .message = "The microphone did not start: " + std::string(snd_strerror(started)) + "."};
            }
            return {.recording = std::unique_ptr<Recording>(new Recording(plugin, std::move(device), stream, sampleRate)), .message = ""};
        }

        ~Recording() {
            running.store(false);
            reader.join();
        }

        Recording(const Recording&) = delete;
        Recording& operator=(const Recording&) = delete;

        [[nodiscard]] int getSampleRate() const {
            return sampleRate;
        }

      private:
        using Device = std::unique_ptr<snd_pcm_t, decltype(&snd_pcm_close)>;

        static constexpr unsigned kLatencyMicroseconds = 100000;
        static constexpr int kWaitMilliseconds = 200;

        Recording(const MicrophonePlugin& owner, Device opened, HaylenNativeAudioStream* audioStream, int rate) : plugin(owner), device(std::move(opened)), stream(audioStream), sampleRate(rate), block(static_cast<std::size_t>(rate / 100)), reader(&Recording::read, this) {}

        // Reads every block that the device captured and pushes it, until the frame thread stops the recording or the device fails for good. An overrun, when the thread fell behind, starts the device again.
        void read() {
            while (running.load()) {
                const int waited = snd_pcm_wait(device.get(), kWaitMilliseconds);
                if (waited == 0) {
                    continue;
                }

                const snd_pcm_sframes_t frames = waited < 0 ? waited : snd_pcm_readi(device.get(), block.data(), block.size());
                if (frames == -EAGAIN) {
                    continue;
                }
                if (frames >= 0) {
                    plugin.getApi().pushAudioFrames(stream, block.data(), static_cast<std::size_t>(frames));
                    continue;
                }

                int recovered = snd_pcm_recover(device.get(), static_cast<int>(frames), 1);
                if (recovered == 0) {
                    recovered = snd_pcm_start(device.get());
                }
                if (recovered < 0) {
                    plugin.emit("microphone.stopped", {{"message", "The microphone stopped: " + std::string(snd_strerror(recovered)) + "."}, {"code", "microphoneFailed"}});
                    return;
                }
            }
        }

        const MicrophonePlugin& plugin;
        Device device;
        HaylenNativeAudioStream* stream;
        const int sampleRate;
        std::vector<float> block;
        std::atomic<bool> running{true};
        std::thread reader;
    };

    const MicrophonePlugin& plugin;
    std::unique_ptr<Recording> recording;
};

MicrophoneDevice::MicrophoneDevice(const MicrophonePlugin& owner) : system(std::make_unique<System>(System{.plugin = owner, .recording = nullptr})) {}

MicrophoneDevice::~MicrophoneDevice() = default;

void MicrophoneDevice::start(std::uint64_t call, int sampleRate) {
    system->recording.reset();
    System::Recording::Opened opened = System::Recording::open(system->plugin, sampleRate);
    if (!opened.recording) {
        system->plugin.fail(call, opened.message, opened.code);
        return;
    }

    system->recording = std::move(opened.recording);
    const int rate = system->recording->getSampleRate();
    system->plugin.succeed(call, {{"sampleRate", rate}, {"channels", 1}, {"stream", "microphone-" + std::to_string(rate)}});
}

void MicrophoneDevice::stop(std::uint64_t call) {
    system->recording.reset();
    system->plugin.succeed(call, nullptr);
}

void MicrophoneDevice::permission(std::uint64_t call) {
    system->plugin.succeed(call, "granted");
}

void MicrophoneDevice::requestPermission(std::uint64_t call) {
    system->plugin.succeed(call, "granted");
}
