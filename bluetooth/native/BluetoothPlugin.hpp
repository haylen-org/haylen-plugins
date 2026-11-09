#pragma once

#include <cstddef>
#include <cstdint>
#include <string_view>

#include "BluetoothBridge.hpp"
#include "haylen/platform/native/HaylenNative.h"

#if defined(_WIN32)
#include "WindowsBluetooth.hpp"
#else
#include "LinuxBluetooth.hpp"
#endif

// The desktop part of the Bluetooth plugin, a C++ library for Windows and Linux that the Lua API loads with `native.load`. It is a central of Bluetooth Low Energy through the API of each system, the Windows Runtime on Windows and BlueZ on Linux, whose class does the work on a thread of its own. The handlers run on the frame thread, read the parameters of each call and hand the call to that thread.
class BluetoothPlugin final {
  public:
    // Creates the plugin once per process, since its thread and its connections outlive the restarts of the app, registers its methods and declares the library the native part of `bluetooth`. Returns 1 when the engine hands a native API of another version.
    [[nodiscard]] static int initialize(const HaylenNativeApi* api);

  private:
#if defined(_WIN32)
    using Central = WindowsBluetooth;
#else
    using Central = LinuxBluetooth;
#endif

    static constexpr std::string_view kPrefix = "bluetooth.";

    explicit BluetoothPlugin(const HaylenNativeApi& engine);

    static void handleCall(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    // Gives up a scan or a connection whose call the app cancelled or whose timeout passed.
    static void cancelCall(void* user, std::uint64_t call);

    static inline BluetoothPlugin* instance = nullptr;

    BluetoothBridge bridge;
    Central central;
};
