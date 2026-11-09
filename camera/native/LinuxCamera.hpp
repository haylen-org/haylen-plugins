#pragma once

#include <cstdint>
#include <memory>
#include <optional>

#include <nlohmann/json.hpp>

#include "LinuxCameraDevices.hpp"

class CameraPlugin;
class LinuxCapture;

// The cameras of Video4Linux on Linux. Linux gates no camera for an app outside a sandbox, so the permission is granted, while the files of the devices may still keep a person out, which the start then tells. Linux offers no JPEG encoder in its system API, so the library takes no photos. The handlers run on the frame thread, and a thread of each capture reads its frames.
class LinuxCamera final {
  public:
    explicit LinuxCamera(const CameraPlugin& owner);
    ~LinuxCamera();

    LinuxCamera(const LinuxCamera&) = delete;
    LinuxCamera& operator=(const LinuxCamera&) = delete;

    void cameras(std::uint64_t call) const;
    void start(std::uint64_t call, const nlohmann::json& params);
    void stop(std::uint64_t call);
    void takePhoto(std::uint64_t call) const;
    void permission(std::uint64_t call) const;
    void requestPermission(std::uint64_t call) const;

  private:
    // Finds the camera that the parameters name by its id, by the way it faces, which on Linux is always "external", or the first one, or fails the call with the code `noCamera`.
    [[nodiscard]] std::optional<LinuxCameraDevices::Device> find(std::uint64_t call, const nlohmann::json& params) const;

    [[nodiscard]] static nlohmann::json describe(const LinuxCameraDevices::Device& device);

    const CameraPlugin& plugin;
    std::unique_ptr<LinuxCapture> capture;
};
