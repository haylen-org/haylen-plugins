#include "MediaSessionPlugin.hpp"

// The init function that `native.load('media-session', {init = 'media_session_haylen_init'})` finds by its C name, which forwards to the plugin.
extern "C" __declspec(dllexport) int media_session_haylen_init(const HaylenNativeApi* api) {
    return MediaSessionPlugin::initialize(api);
}
