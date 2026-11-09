#pragma once

#include <cstddef>
#include <cstdint>
#include <string_view>

#include "haylen/platform/native/HaylenNative.h"

// The desktop part of the Haptics plugin, a C++ library for macOS, Windows and Linux. The function `native.load` hands its init function the `HaylenNativeApi` of the engine, through which the library answers the methods of the plugin on the frame thread. A Mac plays the feedback of its Force Touch trackpad, and no desktop has a vibration motor.
class HapticsPlugin final {
  public:
    // Registers the methods of the plugin and declares the library the native part of `haptics`. Returns 1 when the engine hands a native API of another version.
    [[nodiscard]] static int initialize(const HaylenNativeApi* api);

  private:
    static void vibrate(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void impact(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void selection(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void notification(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);

    static void succeed(std::uint64_t call);
    static void failUnsupported(std::uint64_t call, std::string_view message);

    static inline const HaylenNativeApi* api = nullptr;
};
