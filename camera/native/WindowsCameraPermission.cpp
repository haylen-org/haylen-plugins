#include "WindowsCameraPermission.hpp"

#include <roapi.h>
#include <wrl/wrappers/corewrappers.h>

#include "WindowsAsync.hpp"

using ABI::Windows::Foundation::AsyncStatus;
using ABI::Windows::Foundation::IAsyncOperation;
using ABI::Windows::Security::Authorization::AppCapabilityAccess::IAppCapabilityStatics;
using Microsoft::WRL::ComPtr;
using Microsoft::WRL::Wrappers::HStringReference;

WindowsCameraPermission::Answer WindowsCameraPermission::check() {
    const ComPtr<Capability> capability = create();
    Status status{};
    if (!capability || FAILED(capability->CheckAccess(&status))) {
        return {.state = "unknown", .message = ""};
    }
    return answer(status);
}

WindowsCameraPermission::Answer WindowsCameraPermission::request() {
    const ComPtr<Capability> capability = create();
    Status status{};
    if (!capability || FAILED(capability->CheckAccess(&status))) {
        return {.state = "unknown", .message = ""};
    }
    if (status != Status::AppCapabilityAccessStatus_UserPromptRequired) {
        return answer(status);
    }

    ComPtr<IAsyncOperation<Status>> operation;
    if (FAILED(capability->RequestAccessAsync(&operation))) {
        return {.state = "prompt", .message = ""};
    }
    if (WindowsAsync::wait(operation.Get()) != AsyncStatus::Completed || FAILED(operation->GetResults(&status))) {
        return {.state = "unknown", .message = ""};
    }
    return answer(status);
}

ComPtr<WindowsCameraPermission::Capability> WindowsCameraPermission::create() {
    ComPtr<IAppCapabilityStatics> statics;
    const HStringReference className(RuntimeClass_Windows_Security_Authorization_AppCapabilityAccess_AppCapability);
    if (FAILED(RoGetActivationFactory(className.Get(), IID_PPV_ARGS(&statics)))) {
        return nullptr;
    }

    ComPtr<Capability> capability;
    if (FAILED(statics->Create(HStringReference(L"webcam").Get(), &capability))) {
        return nullptr;
    }
    return capability;
}

WindowsCameraPermission::Answer WindowsCameraPermission::answer(Status status) {
    switch (status) {
    case Status::AppCapabilityAccessStatus_Allowed:
        return {.state = "granted", .message = ""};
    case Status::AppCapabilityAccessStatus_UserPromptRequired:
        return {.state = "prompt", .message = ""};
    case Status::AppCapabilityAccessStatus_DeniedByUser:
    case Status::AppCapabilityAccessStatus_DeniedBySystem:
        return {.state = "denied", .message = ""};
    case Status::AppCapabilityAccessStatus_NotDeclaredByApp:
        return {.state = "unsupported", .message = "The app does not declare the capability \"webcam\" of Windows."};
    }
    return {.state = "unknown", .message = ""};
}
