#pragma once

#include <atomic>
#include <cstdint>
#include <memory>
#include <string>
#include <thread>
#include <variant>
#include <vector>

#include "LinuxCameraDevices.hpp"
#include "LinuxDescriptor.hpp"
#include "LinuxMapping.hpp"
#include "haylen/platform/native/HaylenNative.h"

class CameraPlugin;

// The capture of one camera, whose YUYV frames a thread of its own turns into RGBA pixels and pushes into the video stream `camera`. The frame thread opens and ends it, and the thread reads only what never changes while it runs, besides the flag that stops it.
class LinuxCapture final {
  public:
    using Opened = std::variant<std::unique_ptr<LinuxCapture>, std::string>;

    // Opens the camera for frames of YUYV of the size it offers closest to the one the app asks for and starts its thread, or returns the reason it cannot.
    [[nodiscard]] static Opened open(const CameraPlugin& plugin, const LinuxCameraDevices::Device& camera, int wantedWidth, int wantedHeight);

    ~LinuxCapture();

    LinuxCapture(const LinuxCapture&) = delete;
    LinuxCapture& operator=(const LinuxCapture&) = delete;

    [[nodiscard]] int getWidth() const;
    [[nodiscard]] int getHeight() const;

  private:
    static constexpr unsigned kBufferCount = 4;
    static constexpr int kPollMilliseconds = 200;

    LinuxCapture(const CameraPlugin& owner, LinuxDescriptor node, std::string cameraName);

    // Picks the size of YUYV frames closest to the one the app asks for, among the sizes the driver lists, or inside the range it allows.
    static void closestSize(const LinuxDescriptor& node, int& frameWidth, int& frameHeight);
    static std::uint8_t clamp(int value);

    // Sets the format and the buffers of the camera and starts its stream and its thread, or returns the reason it cannot.
    [[nodiscard]] std::string configure(int wantedWidth, int wantedHeight);

    // Turns each two pixels of YUYV into RGBA with the integer coefficients of BT.601.
    void convert(const std::uint8_t* frame);

    // Waits for each frame of the driver, pushes it and hands its buffer back, until the frame thread ends the capture or the camera goes away.
    void readFrames();

    const CameraPlugin& plugin;
    LinuxDescriptor device;
    std::string name;
    int width = 0;
    int height = 0;
    int stride = 0;
    std::vector<LinuxMapping> buffers;
    std::vector<std::uint8_t> pixels;
    HaylenNativeVideoStream* stream = nullptr;
    bool streaming = false;
    std::atomic<bool> running = false;
    std::thread thread;
};
