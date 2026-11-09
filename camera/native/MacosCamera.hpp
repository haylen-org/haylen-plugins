#pragma once

#include <cstdint>
#include <functional>
#include <memory>

#include <nlohmann/json.hpp>

class CameraPlugin;

// The cameras of AVFoundation on macOS for the desktop player, which runs without a bundle of its own, so macOS asks for the camera in the name of the app that started it, such as the terminal. The handlers run on the frame thread, which is the main thread of AppKit, and the prompt of the system answers on another thread, which hands its answer back to the main thread.
class MacosCamera final {
  public:
    explicit MacosCamera(const CameraPlugin& owner);
    ~MacosCamera();

    MacosCamera(const MacosCamera&) = delete;
    MacosCamera& operator=(const MacosCamera&) = delete;

    void cameras(std::uint64_t call);
    void start(std::uint64_t call, const nlohmann::json& params);
    void stop(std::uint64_t call);
    void takePhoto(std::uint64_t call);
    void permission(std::uint64_t call) const;
    void requestPermission(std::uint64_t call) const;

  private:
    // The capture that runs, an Objective-C object that only the implementation names.
    struct Session;

    // Runs `granted` on the main thread once the process holds the camera, after the prompt of the system where it does not hold it yet, and fails the call with the code `denied` otherwise.
    void require(std::uint64_t call, std::function<void()> granted) const;

    void listCameras(std::uint64_t call) const;
    void open(std::uint64_t call, const nlohmann::json& params);
    void stopCapture();

    const CameraPlugin& plugin;
    std::unique_ptr<Session> session;
};
