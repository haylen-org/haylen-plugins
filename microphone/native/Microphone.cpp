#include "MicrophonePlugin.hpp"

#if defined(_WIN32)
#define MICROPHONE_EXPORT __declspec(dllexport)
#else
#define MICROPHONE_EXPORT __attribute__((visibility("default")))
#endif

// The init function that `native.load('microphone', {init = 'microphone_haylen_init'})` finds by its C name, which forwards to the plugin.
extern "C" MICROPHONE_EXPORT int microphone_haylen_init(const HaylenNativeApi* api) {
    return MicrophonePlugin::initialize(api);
}
