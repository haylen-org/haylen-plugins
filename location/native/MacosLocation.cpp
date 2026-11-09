#include "MacosLocation.hpp"

#include "LocationBridge.hpp"

// Registers the methods of the plugin with a bridge that lives as long as the process, since the engine may call the library until the process ends, and declares the library the native part of `location`.
int MacosLocation::initialize(const HaylenNativeApi* api) {
    if (api->version != HAYLEN_NATIVE_API_VERSION) {
        return 1;
    }
    auto* bridge = new LocationBridge(*api);

    api->registerHandler("location.reset", &MacosLocation::handleReset, nullptr, bridge);
    api->registerHandler("location.current", &MacosLocation::handleUnsupported, nullptr, bridge);
    api->registerHandler("location.watch", &MacosLocation::handleUnsupported, nullptr, bridge);
    api->registerHandler("location.stop", &MacosLocation::handleReset, nullptr, bridge);
    api->registerHandler("location.permission", &MacosLocation::handlePermission, nullptr, bridge);
    api->registerHandler("location.requestPermission", &MacosLocation::handlePermission, nullptr, bridge);
    api->registerPlugin("location");
    return 0;
}

void MacosLocation::handleUnsupported(void* user, std::uint64_t call, const char*, const char*, const HaylenNativeBuffer*, std::size_t) {
    const auto& bridge = *static_cast<const LocationBridge*>(user);
    bridge.fail(call, kWithoutBundle, "unsupported");
}

void MacosLocation::handlePermission(void* user, std::uint64_t call, const char*, const char*, const HaylenNativeBuffer*, std::size_t) {
    const auto& bridge = *static_cast<const LocationBridge*>(user);
    bridge.fail(call, kWithoutBundle, "unsupported");
}

void MacosLocation::handleReset(void* user, std::uint64_t call, const char*, const char*, const HaylenNativeBuffer*, std::size_t) {
    const auto& bridge = *static_cast<const LocationBridge*>(user);
    bridge.succeed(call, nullptr);
}
