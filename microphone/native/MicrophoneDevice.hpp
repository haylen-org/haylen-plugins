#pragma once

#include <cstdint>
#include <memory>

class MicrophonePlugin;

// The microphone of the system, which the file of each system implements: `MicrophoneDevice.mm` with AVAudioEngine on macOS, `MicrophoneDeviceWindows.cpp` with WASAPI and `MicrophoneDeviceLinux.cpp` with ALSA. Its methods run on the frame thread and answer each call once through the plugin. A recording pushes mono floats into the audio stream `microphone-<rate>` and stops with the event `microphone.stopped` when the input goes away.
class MicrophoneDevice final {
  public:
    explicit MicrophoneDevice(const MicrophonePlugin& owner);
    ~MicrophoneDevice();
    MicrophoneDevice(const MicrophoneDevice&) = delete;
    MicrophoneDevice& operator=(const MicrophoneDevice&) = delete;

    // Stops a recording that runs and starts one at the rate, once the permission `microphone` allows it.
    void start(std::uint64_t call, int sampleRate);
    void stop(std::uint64_t call);
    void permission(std::uint64_t call);
    void requestPermission(std::uint64_t call);

  private:
    // The recording and the threads of the system, which the file of each system defines.
    struct System;

    std::unique_ptr<System> system;
};
