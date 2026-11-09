#pragma once

#include <cstddef>
#include <cstdint>

#include "haylen/platform/native/HaylenNative.h"

// The desktop part of the Dialogs plugin, a C++ library that the desktop player and the Windows and Linux apps load. The function `native.load` hands its init function the `HaylenNativeApi` of the engine, through which the library answers the methods of the plugin: it reads each request and hands it to the dialogs of the system, the sheets of AppKit on macOS, the dialogs of the shell on Windows and GTK 3 on Linux. Its handlers and cancels run on the frame thread.
class DialogsPlugin final {
  public:
    // Registers the methods of the plugin and declares the library the native part of `dialogs`. Returns 1 when the engine hands a native API of another version.
    [[nodiscard]] static int initialize(const HaylenNativeApi* api);

  private:
    static void show(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void cancel(void* user, std::uint64_t call);
};
