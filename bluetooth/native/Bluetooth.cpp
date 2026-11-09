#include "BluetoothPlugin.hpp"

#if defined(_WIN32)
#define BLUETOOTH_EXPORT __declspec(dllexport)
#else
#define BLUETOOTH_EXPORT __attribute__((visibility("default")))
#endif

// The init function that `native.load('bluetooth', {init = 'bluetooth_haylen_init'})` finds by its C name, which forwards to the plugin.
extern "C" BLUETOOTH_EXPORT int bluetooth_haylen_init(const HaylenNativeApi* api) {
    return BluetoothPlugin::initialize(api);
}
