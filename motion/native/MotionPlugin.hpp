#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include <nlohmann/json.hpp>

#include "MotionDevice.hpp"
#include "haylen/platform/native/HaylenNative.h"

// The desktop part of the Motion plugin, a C++ library for macOS, Windows and Linux. The function `native.load` hands its init function the `HaylenNativeApi` of the engine, through which the library answers the methods of the plugin and sends the readings of the sensors as the batched event `motion.reading`. Its handlers run on the frame thread, read the parameters that the Lua API of the plugin writes and hand the work to `MotionDevice`, which answers each call once, at once or later from any thread.
class MotionPlugin final {
  public:
    using Json = nlohmann::json;

    // Creates the plugin once, registers its methods and declares the library the native part of `motion`. The library stays loaded while apps restart in the process and the init function runs again, so the plugin and the sensors it runs outlive them. Returns 1 when the engine hands a native API of another version.
    [[nodiscard]] static int initialize(const HaylenNativeApi* api);

    [[nodiscard]] const HaylenNativeApi& getApi() const;
    void succeed(std::uint64_t call, const Json& result) const;
    void fail(std::uint64_t call, std::string_view message, std::string_view code) const;
    void emit(std::string_view event, const Json& payload, int flags) const;

  private:
    static MotionPlugin* instance;

    explicit MotionPlugin(const HaylenNativeApi& engine);

    static void permission(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void watch(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void cancelWatch(void* user, std::uint64_t call);
    static void start(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);

    // The session of the parameters, a whole number from 1 that the Lua API counts, or nothing where they hold none.
    [[nodiscard]] static std::optional<std::int64_t> readSession(const Json& params);
    [[nodiscard]] static std::optional<double> readNumber(const Json& params, const char* key);
    [[nodiscard]] static std::vector<std::string> readNames(const Json& params, const char* key);
    [[nodiscard]] static std::string write(const Json& value);

    const HaylenNativeApi& api;
    MotionDevice device;
};
