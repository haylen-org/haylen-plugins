#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

class MotionPlugin;

// The motion sensors of the system, which the file of each system implements: `MotionDeviceWindows.cpp` with `Windows.Devices.Sensors` of C++/WinRT, and `MotionDevice.cpp` on macOS and Linux, which give apps no readings of motion sensors. Its methods run on the frame thread and answer each call once through the plugin. The call of `watch` lasts while the sensors of its session run, until the app gives it up.
class MotionDevice final {
  public:
    explicit MotionDevice(const MotionPlugin& owner);
    ~MotionDevice();
    MotionDevice(const MotionDevice&) = delete;
    MotionDevice& operator=(const MotionDevice&) = delete;

    void permission(std::uint64_t call);
    void watch(std::uint64_t call, std::int64_t session);
    void cancelWatch(std::uint64_t call);
    void start(std::uint64_t call, std::int64_t session, double rate, std::vector<std::string> sensors);

  private:
    // The sensors and the thread of the system, which the file of each system defines.
    struct System;

    std::unique_ptr<System> system;
};
