// The motion sensors of macOS and Linux, which give apps no readings of them, so the permission `motion` fails with the code `unsupported` and every start fails with the reason of the system.

#include "MotionDevice.hpp"
#include "MotionPlugin.hpp"

#include <string_view>

struct MotionDevice::System {
#if defined(__APPLE__)
    static constexpr std::string_view kReason = "A Mac gives apps no readings of motion sensors.";
#else
    static constexpr std::string_view kReason = "The Linux desktop gives apps no readings of motion sensors.";
#endif

    const MotionPlugin& plugin;
};

MotionDevice::MotionDevice(const MotionPlugin& owner) : system(std::make_unique<System>(System{.plugin = owner})) {}

MotionDevice::~MotionDevice() = default;

void MotionDevice::permission(std::uint64_t call) {
    system->plugin.fail(call, System::kReason, "unsupported");
}

// Fails the watch at once, so the session of the Lua API ends with the reason.
void MotionDevice::watch(std::uint64_t call, std::int64_t) {
    system->plugin.fail(call, System::kReason, "unsupported");
}

void MotionDevice::cancelWatch(std::uint64_t) {}

void MotionDevice::start(std::uint64_t call, std::int64_t, double, std::vector<std::string>) {
    system->plugin.fail(call, System::kReason, "unsupported");
}
