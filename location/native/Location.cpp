#if defined(_WIN32)
#include "WindowsLocation.hpp"
#define LOCATION_EXPORT __declspec(dllexport)
#elif defined(__APPLE__)
#include "MacosLocation.hpp"
#define LOCATION_EXPORT __attribute__((visibility("default")))
#else
#include "LinuxLocation.hpp"
#define LOCATION_EXPORT __attribute__((visibility("default")))
#endif

// The init function that `native.load('location', {init = 'location_haylen_init'})` finds by its C name, which forwards to the location of the system that the library is built for.
extern "C" LOCATION_EXPORT int location_haylen_init(const HaylenNativeApi* api) {
#if defined(_WIN32)
    return WindowsLocation::initialize(api);
#elif defined(__APPLE__)
    return MacosLocation::initialize(api);
#else
    return LinuxLocation::initialize(api);
#endif
}
