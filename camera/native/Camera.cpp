#include "CameraPlugin.hpp"

#if defined(_WIN32)
#define CAMERA_EXPORT __declspec(dllexport)
#else
#define CAMERA_EXPORT __attribute__((visibility("default")))
#endif

// The init function that `native.load('camera', {init = 'camera_haylen_init'})` finds by its C name, which forwards to the plugin.
extern "C" CAMERA_EXPORT int camera_haylen_init(const HaylenNativeApi* api) {
    return CameraPlugin::initialize(api);
}
