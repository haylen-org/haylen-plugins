#pragma once

#include <cstdint>
#include <memory>
#include <optional>

#include <nlohmann/json.hpp>

#include "WindowsCameraDevices.hpp"
#include "WindowsCameraPermission.hpp"
#include "WindowsWorker.hpp"

class CameraPlugin;
class WindowsCapture;

// The cameras of Media Foundation on Windows, with photos through WIC and the permission `camera`, which the capability `webcam` of the privacy settings of Windows answers. The handlers run on the frame thread and hand their work to a thread of the library in the multithreaded apartment of COM, which alone touches the capture and answers the calls, and each capture reads its frames on a thread of its own.
class WindowsCamera final {
  public:
    explicit WindowsCamera(const CameraPlugin& owner);
    ~WindowsCamera();

    WindowsCamera(const WindowsCamera&) = delete;
    WindowsCamera& operator=(const WindowsCamera&) = delete;

    void cameras(std::uint64_t call);
    void start(std::uint64_t call, const nlohmann::json& params);
    void stop(std::uint64_t call);
    void takePhoto(std::uint64_t call);
    void permission(std::uint64_t call);
    void requestPermission(std::uint64_t call);

  private:
    // Answers `camera.permission` and `camera.requestPermission` with the name of the state, or fails them with the code `unsupported` and the reason.
    void answerPermission(std::uint64_t call, const WindowsCameraPermission::Answer& given) const;

    // Asks for the camera where the app does not hold it yet, and fails the call where the person or the system refuses it. A Windows that tells nothing lets the use try.
    [[nodiscard]] bool require(std::uint64_t call) const;

    // Finds the camera that the parameters name by its id, by the way it faces, or the first one, which Windows lists first as its default, or fails the call with the code `noCamera`.
    [[nodiscard]] std::optional<WindowsCameraDevices::Device> find(std::uint64_t call, const nlohmann::json& params) const;

    void listCameras(std::uint64_t call) const;
    void open(std::uint64_t call, const nlohmann::json& params);
    void closeCapture(std::uint64_t call);
    void photograph(std::uint64_t call) const;

    const CameraPlugin& plugin;
    std::unique_ptr<WindowsCapture> capture;
    WindowsWorker worker;
};
