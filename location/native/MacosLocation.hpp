#pragma once

#include <cstddef>
#include <cstdint>
#include <string_view>

#include "haylen/platform/native/HaylenNative.h"

// The desktop part of the Location plugin on macOS, which the desktop player loads. Core Location gives the location only to an app whose bundle holds an `Info.plist` with "NSLocationUsageDescription", and the player runs without a bundle of its own, so every method and permission answers `unsupported` with the way to the macOS app, whose Swift part reads the location.
class MacosLocation final {
  public:
    [[nodiscard]] static int initialize(const HaylenNativeApi* api);

  private:
    static constexpr std::string_view kWithoutBundle = "The desktop player runs without an app bundle, and Core Location gives the location only to an app whose Info.plist holds \"NSLocationUsageDescription\". Run the macOS app with \"haylen app run --target macos\".";

    static void handleUnsupported(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void handlePermission(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void handleReset(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
};
