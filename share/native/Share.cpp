#include "SharePlugin.hpp"

#if defined(_WIN32)
#define SHARE_EXPORT __declspec(dllexport)
#else
#define SHARE_EXPORT __attribute__((visibility("default")))
#endif

// The init function that `native.load('share', {init = 'share_haylen_init'})` finds by its C name, which forwards to the plugin.
extern "C" SHARE_EXPORT int share_haylen_init(const HaylenNativeApi* api) {
    return SharePlugin::initialize(api);
}
