#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

#include <nlohmann/json.hpp>

#include "MicrophoneDevice.hpp"
#include "haylen/platform/native/HaylenNative.h"

// The desktop part of the Microphone plugin, a C++ library for macOS, Windows and Linux. The function `native.load` hands its init function the `HaylenNativeApi` of the engine, through which the library answers the methods of the plugin and pushes the mono samples of the microphone into an audio stream named after their rate. Its handlers run on the frame thread and hand the work to `MicrophoneDevice`, which records through the API of each system and answers each call once, at once or later from any thread.
class MicrophonePlugin final {
  public:
    using Json = nlohmann::json;

    // The failure of a use of the microphone that the person or the system refused.
    static constexpr std::string_view kRefusal = "The person has not allowed the microphone. Ask for it with \"microphone.requestPermission('microphone')\", which shows the prompt of the system while the system still asks, or the person allows it in the settings of the system.";

    // Creates the plugin once, registers its methods and declares the library the native part of `microphone`. The library stays loaded while apps restart in the process and the init function runs again, so the plugin and its recording outlive them until the next app sends `microphone.reset`. Returns 1 when the engine hands a native API of another version.
    [[nodiscard]] static int initialize(const HaylenNativeApi* api);

    [[nodiscard]] const HaylenNativeApi& getApi() const;
    void succeed(std::uint64_t call, const Json& result) const;
    void fail(std::uint64_t call, std::string_view message, std::string_view code) const;
    void emit(std::string_view event, const Json& payload) const;

  private:
    static constexpr int kDefaultRate = 48000;
    static constexpr int kMaxRate = 768000;

    static MicrophonePlugin* instance;

    explicit MicrophonePlugin(const HaylenNativeApi& engine);

    static void start(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void stop(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void permission(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void requestPermission(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);

    // The rate of `start`, 48000 hertz when the parameters name none, or nothing for a rate that no microphone records at.
    [[nodiscard]] static std::optional<int> readSampleRate(const Json& params);
    [[nodiscard]] static std::string write(const Json& value);

    const HaylenNativeApi& api;
    MicrophoneDevice device;
};
