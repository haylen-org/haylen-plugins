#include "MotionPlugin.hpp"

#if defined(_WIN32)
#define MOTION_EXPORT __declspec(dllexport)
#else
#define MOTION_EXPORT __attribute__((visibility("default")))
#endif

// The init function that `native.load('motion', {init = 'motion_haylen_init'})` finds by its C name, which forwards to the plugin.
extern "C" MOTION_EXPORT int motion_haylen_init(const HaylenNativeApi* api) {
    return MotionPlugin::initialize(api);
}
