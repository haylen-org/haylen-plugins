#pragma once

#include <cstddef>
#include <cstdint>

#include "haylen/platform/native/HaylenNative.h"

// The desktop part of the Share plugin, a C++ library that the macOS desktop player and the Windows apps load. The function `native.load` hands its init function the `HaylenNativeApi` of the engine, through which the library answers `share.share` with the share UI of the system over the window of the app: the sharing service picker of AppKit on macOS, and the share UI of `IDataTransferManagerInterop` on Windows. The handler runs on the frame thread.
class SharePlugin final {
  public:
    // Registers the method of the plugin and declares the library the native part of `share`. Returns 1 when the engine hands a native API of another version.
    [[nodiscard]] static int initialize(const HaylenNativeApi* api);

  private:
    static const HaylenNativeApi* api;

    static void share(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
};
