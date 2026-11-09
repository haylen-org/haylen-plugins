#include "LinksPlugin.hpp"

#if defined(_WIN32)
#define LINKS_EXPORT __declspec(dllexport)
#else
#define LINKS_EXPORT __attribute__((visibility("default")))
#endif

// The init function that `native.load('links', {init = 'links_haylen_init'})` finds by its C name, which forwards to the plugin.
extern "C" LINKS_EXPORT int links_haylen_init(const HaylenNativeApi* api) {
    return LinksPlugin::initialize(api);
}
