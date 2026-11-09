#include "WindowsCameraDevices.hpp"

#include <memory>

#include <mfapi.h>
#include <roapi.h>
#include <windows.devices.enumeration.h>
#include <wrl/wrappers/corewrappers.h>

#include "CameraPlugin.hpp"
#include "WindowsAsync.hpp"
#include "WindowsText.hpp"

using ABI::Windows::Devices::Enumeration::IDeviceInformation;
using ABI::Windows::Devices::Enumeration::IDeviceInformationStatics;
using ABI::Windows::Devices::Enumeration::IEnclosureLocation;
using ABI::Windows::Devices::Enumeration::Panel;
using ABI::Windows::Foundation::AsyncStatus;
using ABI::Windows::Foundation::IAsyncOperation;
using Microsoft::WRL::ComPtr;
using Microsoft::WRL::Wrappers::HStringReference;

std::vector<WindowsCameraDevices::Device> WindowsCameraDevices::list() {
    std::vector<Device> devices;
    ComPtr<IMFAttributes> attributes;
    if (FAILED(MFCreateAttributes(&attributes, 1)) || FAILED(attributes->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE, MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID))) {
        return devices;
    }
    IMFActivate** found = nullptr;
    UINT32 count = 0;
    if (FAILED(MFEnumDeviceSources(attributes.Get(), &found, &count))) {
        return devices;
    }
    const std::unique_ptr<IMFActivate*, decltype(&CoTaskMemFree)> activates(found, &CoTaskMemFree);

    for (UINT32 index = 0; index < count; ++index) {
        ComPtr<IMFActivate> activate;
        activate.Attach(activates.get()[index]);
        const std::wstring link = readString(activate.Get(), MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK);
        const std::wstring name = readString(activate.Get(), MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME);
        devices.push_back({.id = WindowsText::toUtf8(link), .name = WindowsText::toUtf8(name), .facing = facing(link), .activate = activate});
    }
    return devices;
}

nlohmann::json WindowsCameraDevices::describe(const Device& device) {
    return CameraPlugin::describe(device.id, device.name, device.facing);
}

std::wstring WindowsCameraDevices::readString(IMFActivate* activate, const GUID& key) {
    wchar_t* value = nullptr;
    UINT32 length = 0;
    if (FAILED(activate->GetAllocatedString(key, &value, &length))) {
        return {};
    }
    const std::unique_ptr<wchar_t, decltype(&CoTaskMemFree)> owned(value, &CoTaskMemFree);
    return std::wstring(owned.get(), length);
}

std::string WindowsCameraDevices::facing(const std::wstring& link) {
    ComPtr<IDeviceInformationStatics> statics;
    const HStringReference className(RuntimeClass_Windows_Devices_Enumeration_DeviceInformation);
    if (FAILED(RoGetActivationFactory(className.Get(), IID_PPV_ARGS(&statics)))) {
        return "external";
    }
    ComPtr<IAsyncOperation<ABI::Windows::Devices::Enumeration::DeviceInformation*>> operation;
    const HStringReference id(link.c_str(), static_cast<unsigned int>(link.size()));
    if (FAILED(statics->CreateFromIdAsync(id.Get(), &operation))) {
        return "external";
    }

    ComPtr<IDeviceInformation> information;
    if (WindowsAsync::wait(operation.Get()) != AsyncStatus::Completed || FAILED(operation->GetResults(&information))) {
        return "external";
    }
    ComPtr<IEnclosureLocation> enclosure;
    if (FAILED(information->get_EnclosureLocation(&enclosure)) || !enclosure) {
        return "external";
    }
    Panel panel = Panel::Panel_Unknown;
    if (FAILED(enclosure->get_Panel(&panel))) {
        return "external";
    }

    if (panel == Panel::Panel_Front) {
        return "front";
    }
    return panel == Panel::Panel_Back ? "back" : "external";
}
