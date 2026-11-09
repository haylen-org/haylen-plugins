#pragma once

#include <string>
#include <vector>

#include <nlohmann/json.hpp>

#include <windows.h>

#include <mfidl.h>
#include <wrl/client.h>

// The cameras of Media Foundation, whose symbolic links are their ids, and the way each one faces, which the enclosure of its device interface tells where the computer knows it.
class WindowsCameraDevices final {
  public:
    // A camera with the activation object that opens it.
    struct Device {
        std::string id;
        std::string name;
        std::string facing;
        Microsoft::WRL::ComPtr<IMFActivate> activate;
    };

    // Lists the cameras in the order of Media Foundation, which lists the default camera of Windows first.
    [[nodiscard]] static std::vector<Device> list();

    [[nodiscard]] static nlohmann::json describe(const Device& device);

  private:
    [[nodiscard]] static std::wstring readString(IMFActivate* activate, const GUID& key);
    [[nodiscard]] static std::string facing(const std::wstring& link);
};
