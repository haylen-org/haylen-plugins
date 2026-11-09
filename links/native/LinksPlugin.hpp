#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

#include "LinkOpener.hpp"
#include "haylen/platform/native/HaylenNative.h"

// The desktop part of the Links plugin, a C++ library for macOS, Windows and Linux. The function `native.load` hands its init function the `HaylenNativeApi` of the engine, through which the library answers `links.open`. Its handler runs on the frame thread, and `LinkOpener` may answer from any thread.
class LinksPlugin final {
  public:
    // Registers the methods of the plugin and declares the library the native part of `links`. Returns 1 when the engine hands a native API of another version.
    [[nodiscard]] static int initialize(const HaylenNativeApi* api);

  private:
    // Answers `links.open` with `true` once an app took the url, or fails with the code `unsupported` and the reason.
    static void open(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);

    static void answer(std::uint64_t call, const std::string& url, LinkOpener::Answer result);
    static void fail(std::uint64_t call, const std::string& message, const char* code);

    static inline const HaylenNativeApi* api = nullptr;
};
