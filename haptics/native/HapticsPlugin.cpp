#include "HapticsPlugin.hpp"

#include <string>

#include <nlohmann/json.hpp>

#if defined(__APPLE__)
#include "MacTrackpad.hpp"
#endif

int HapticsPlugin::initialize(const HaylenNativeApi* given) {
    if (given->version != HAYLEN_NATIVE_API_VERSION) {
        return 1;
    }
    api = given;

    api->registerHandler("haptics.vibrate", &HapticsPlugin::vibrate, nullptr, nullptr);
    api->registerHandler("haptics.impact", &HapticsPlugin::impact, nullptr, nullptr);
    api->registerHandler("haptics.selection", &HapticsPlugin::selection, nullptr, nullptr);
    api->registerHandler("haptics.notification", &HapticsPlugin::notification, nullptr, nullptr);
    api->registerPlugin("haptics");
    return 0;
}

void HapticsPlugin::vibrate(void*, std::uint64_t call, const char*, const char*, const HaylenNativeBuffer*, std::size_t) {
#if defined(__APPLE__)
    failUnsupported(call, "A Mac has no vibration motor.");
#elif defined(_WIN32)
    failUnsupported(call, "Windows gives apps no vibration motor.");
#else
    failUnsupported(call, "Linux gives apps no vibration motor.");
#endif
}

// A Mac plays one generic feedback for every strength of an impact, and only while a finger rests on a Force Touch trackpad, which the system does not tell an app.
void HapticsPlugin::impact(void*, std::uint64_t call, const char*, const char*, const HaylenNativeBuffer*, std::size_t) {
#if defined(__APPLE__)
    MacTrackpad::perform(MacTrackpad::Pattern::Generic);
    succeed(call);
#elif defined(_WIN32)
    failUnsupported(call, "Windows gives apps no haptic engine.");
#else
    failUnsupported(call, "Linux gives apps no haptic engine.");
#endif
}

void HapticsPlugin::selection(void*, std::uint64_t call, const char*, const char*, const HaylenNativeBuffer*, std::size_t) {
#if defined(__APPLE__)
    MacTrackpad::perform(MacTrackpad::Pattern::Alignment);
    succeed(call);
#elif defined(_WIN32)
    failUnsupported(call, "Windows gives apps no haptic engine.");
#else
    failUnsupported(call, "Linux gives apps no haptic engine.");
#endif
}

void HapticsPlugin::notification(void*, std::uint64_t call, const char*, const char*, const HaylenNativeBuffer*, std::size_t) {
#if defined(__APPLE__)
    failUnsupported(call, "The trackpad of a Mac has no feedback of a notification.");
#elif defined(_WIN32)
    failUnsupported(call, "Windows gives apps no haptic engine.");
#else
    failUnsupported(call, "Linux gives apps no haptic engine.");
#endif
}

void HapticsPlugin::succeed(std::uint64_t call) {
    const std::string text = nlohmann::json(true).dump();
    api->resolve(call, 1, text.c_str(), nullptr, 0);
}

void HapticsPlugin::failUnsupported(std::uint64_t call, std::string_view message) {
    const nlohmann::json failure = {{"message", message}, {"code", "unsupported"}};
    const std::string text = failure.dump(-1, ' ', false, nlohmann::json::error_handler_t::replace);
    api->resolve(call, 0, text.c_str(), nullptr, 0);
}
