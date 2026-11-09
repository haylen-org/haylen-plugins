#if defined(_WIN32)
#include "WindowsNotifications.hpp"
#define NOTIFICATIONS_EXPORT __declspec(dllexport)
#else
#include "LinuxNotifications.hpp"
#define NOTIFICATIONS_EXPORT __attribute__((visibility("default")))
#endif

// The init function that `native.load('notifications', {init = 'notifications_haylen_init'})` finds by its C name, which forwards to the library of the system.
extern "C" NOTIFICATIONS_EXPORT int notifications_haylen_init(const HaylenNativeApi* api) {
#if defined(_WIN32)
    return WindowsNotifications::initialize(api);
#else
    return LinuxNotifications::initialize(api);
#endif
}
