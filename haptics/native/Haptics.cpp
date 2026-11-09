#include "HapticsPlugin.hpp"

#if defined(_WIN32)
#define HAPTICS_EXPORT __declspec(dllexport)
#else
#define HAPTICS_EXPORT __attribute__((visibility("default")))
#endif

// The init function that `native.load('haptics', {init = 'haptics_haylen_init'})` finds by its C name, which forwards to the plugin.
extern "C" HAPTICS_EXPORT int haptics_haylen_init(const HaylenNativeApi* api) {
    return HapticsPlugin::initialize(api);
}
