#include "DialogsPlugin.hpp"

#if defined(_WIN32)
#define DIALOGS_EXPORT __declspec(dllexport)
#else
#define DIALOGS_EXPORT __attribute__((visibility("default")))
#endif

// The init function that `native.load('dialogs', {init = 'dialogs_haylen_init'})` finds by its C name, which forwards to the plugin.
extern "C" DIALOGS_EXPORT int dialogs_haylen_init(const HaylenNativeApi* api) {
    return DialogsPlugin::initialize(api);
}
