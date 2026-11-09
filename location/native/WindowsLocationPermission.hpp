#pragma once

#include <string>

#include <windows.h>

#include <windows.security.authorization.appcapabilityaccess.h>
#include <wrl/client.h>

// The permissions `location`, `preciseLocation` and `backgroundLocation`, which the capability `location` of the privacy settings of Windows answers for all three. Windows shows its prompt only while the settings ask the person, and a Windows without `AppCapability` tells nothing until the app reads the location.
class WindowsLocationPermission final {
  public:
    struct Answer {
        std::string state;
        std::string message;
    };

    [[nodiscard]] static Answer check();
    // Shows the prompt of Windows while the settings ask the person, on the thread of the library, which waits for the answer.
    [[nodiscard]] static Answer request();

  private:
    using Status = ABI::Windows::Security::Authorization::AppCapabilityAccess::AppCapabilityAccessStatus;

    [[nodiscard]] static Microsoft::WRL::ComPtr<ABI::Windows::Security::Authorization::AppCapabilityAccess::IAppCapability> create();
    // The two refusals of `AppCapabilityAccessStatus` are the setting of the person and the one of the system or its policy.
    [[nodiscard]] static Answer answer(Status status);
};
