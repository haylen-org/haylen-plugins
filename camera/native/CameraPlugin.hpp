#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>
#include <string>
#include <string_view>

#include <nlohmann/json.hpp>

#include "haylen/platform/native/HaylenNative.h"

#if defined(__APPLE__)
#include "MacosCamera.hpp"
#elif defined(_WIN32)
#include "WindowsCamera.hpp"
#else
#include "LinuxCamera.hpp"
#endif

// The desktop part of the Camera plugin, a C++ library for macOS, Windows and Linux: the cameras of the system into the video stream `camera`, photos as JPEG bytes and the handlers of the permission `camera`. The function `native.load` hands its init function the `HaylenNativeApi` of the engine, through which the library answers the methods of the plugin, which the camera of each system serves. The handlers run on the frame thread, and the library answers and pushes frames from any thread.
class CameraPlugin final {
  public:
    using Json = nlohmann::json;

    static constexpr std::string_view kRefusal = "The person has not allowed the camera. Ask for it with \"camera.requestPermission('camera')\", which shows the prompt of the system while the system still asks, or the person allows it in the settings of the system.";

    // Registers the methods of the plugin and declares the library the native part of `camera`. The process keeps the library loaded across restarts of the app, which run this function again, so the plugin of the first run and its capture stay. Returns 1 when the engine hands a native API of another version.
    [[nodiscard]] static int initialize(const HaylenNativeApi* api);

    [[nodiscard]] const HaylenNativeApi& getApi() const;

    void succeed(std::uint64_t call, const Json& result, std::span<const HaylenNativeBuffer> buffers = {}) const;
    void fail(std::uint64_t call, std::string_view message, std::string_view code) const;

    // Sends the event `camera.stopped` with the code `cameraFailed` for a camera that stopped by itself while it ran.
    void emitStopped(std::string_view message) const;

    // The fields `id`, `name` and `facing` that the list of the cameras and the answer of a start share.
    [[nodiscard]] static Json describe(std::string_view id, std::string_view name, std::string_view facing);

    [[nodiscard]] static std::optional<std::string> readText(const Json& params, const char* key);
    [[nodiscard]] static int readSize(const Json& params, const char* key, int fallback);

  private:
#if defined(__APPLE__)
    using Camera = MacosCamera;
#elif defined(_WIN32)
    using Camera = WindowsCamera;
#else
    using Camera = LinuxCamera;
#endif

    explicit CameraPlugin(const HaylenNativeApi& engine);

    static void cameras(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void start(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void stop(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void takePhoto(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void permission(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void requestPermission(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);

    // The JSON of a value, with bytes that are not UTF-8 replaced, since the text crosses into the engine.
    [[nodiscard]] static std::string write(const Json& value);

    static CameraPlugin* instance;

    const HaylenNativeApi& api;
    Camera camera;
};
