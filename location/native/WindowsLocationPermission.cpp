#include "WindowsLocationPermission.hpp"

#include <roapi.h>
#include <wrl/wrappers/corewrappers.h>

#include "WindowsLocationAsync.hpp"

using ABI::Windows::Foundation::AsyncStatus;
using ABI::Windows::Foundation::IAsyncOperation;
using ABI::Windows::Security::Authorization::AppCapabilityAccess::AppCapabilityAccessStatus;
using ABI::Windows::Security::Authorization::AppCapabilityAccess::IAppCapability;
using ABI::Windows::Security::Authorization::AppCapabilityAccess::IAppCapabilityStatics;
using Microsoft::WRL::ComPtr;
using Microsoft::WRL::Wrappers::HStringReference;

WindowsLocationPermission::Answer WindowsLocationPermission::check() {
    const ComPtr<IAppCapability> capability = create();
    AppCapabilityAccessStatus status{};
    if (!capability || FAILED(capability->CheckAccess(&status))) {
        return {.state = "unknown", .message = ""};
    }
    return answer(status);
}

WindowsLocationPermission::Answer WindowsLocationPermission::request() {
    const ComPtr<IAppCapability> capability = create();
    AppCapabilityAccessStatus status{};
    if (!capability || FAILED(capability->CheckAccess(&status))) {
        return {.state = "unknown", .message = ""};
    }
    if (status != AppCapabilityAccessStatus::AppCapabilityAccessStatus_UserPromptRequired) {
        return answer(status);
    }

    ComPtr<IAsyncOperation<AppCapabilityAccessStatus>> operation;
    if (FAILED(capability->RequestAccessAsync(&operation))) {
        return {.state = "prompt", .message = ""};
    }
    if (WindowsLocationAsync::wait(operation.Get()) != AsyncStatus::Completed || FAILED(operation->GetResults(&status))) {
        return {.state = "unknown", .message = ""};
    }
    return answer(status);
}

ComPtr<IAppCapability> WindowsLocationPermission::create() {
    ComPtr<IAppCapabilityStatics> statics;
    const HStringReference className(RuntimeClass_Windows_Security_Authorization_AppCapabilityAccess_AppCapability);
    if (FAILED(RoGetActivationFactory(className.Get(), IID_PPV_ARGS(&statics)))) {
        return nullptr;
    }
    ComPtr<IAppCapability> capability;
    if (FAILED(statics->Create(HStringReference(L"location").Get(), &capability))) {
        return nullptr;
    }
    return capability;
}

WindowsLocationPermission::Answer WindowsLocationPermission::answer(Status status) {
    switch (status) {
    case AppCapabilityAccessStatus::AppCapabilityAccessStatus_Allowed:
        return {.state = "granted", .message = ""};
    case AppCapabilityAccessStatus::AppCapabilityAccessStatus_UserPromptRequired:
        return {.state = "prompt", .message = ""};
    case AppCapabilityAccessStatus::AppCapabilityAccessStatus_DeniedByUser:
    case AppCapabilityAccessStatus::AppCapabilityAccessStatus_DeniedBySystem:
        return {.state = "denied", .message = ""};
    case AppCapabilityAccessStatus::AppCapabilityAccessStatus_NotDeclaredByApp:
        return {.state = "unsupported", .message = "The app does not declare the capability \"location\" of Windows."};
    }
    return {.state = "unknown", .message = ""};
}
