#pragma once

#include <string>

#include <windows.h>

#include <windows.security.authorization.appcapabilityaccess.h>
#include <wrl/client.h>

// The permission `camera`, which the capability `webcam` of the privacy settings of Windows answers. Windows shows its prompt only while the settings ask the person, and a Windows without `AppCapability` tells nothing until the app opens the camera.
class WindowsCameraPermission final {
  public:
    struct Answer {
        std::string state;
        std::string message;
    };

    [[nodiscard]] static Answer check();
    [[nodiscard]] static Answer request();

  private:
    using Capability = ABI::Windows::Security::Authorization::AppCapabilityAccess::IAppCapability;
    using Status = ABI::Windows::Security::Authorization::AppCapabilityAccess::AppCapabilityAccessStatus;

    [[nodiscard]] static Microsoft::WRL::ComPtr<Capability> create();

    // The two refusals of `AppCapabilityAccessStatus` are the setting of the person and the one of the system or its policy.
    [[nodiscard]] static Answer answer(Status status);
};
