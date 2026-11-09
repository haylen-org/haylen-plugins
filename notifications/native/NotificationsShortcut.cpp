#include "NotificationsShortcut.hpp"

#include <propkey.h>
#include <propvarutil.h>
#include <shlobj_core.h>
#include <shobjidl_core.h>

#include <iterator>
#include <memory>
#include <system_error>

#include <winrt/Windows.Foundation.h>

std::optional<GUID> NotificationsShortcut::find(const std::wstring& identifier) {
    for (const KNOWNFOLDERID& folder : {FOLDERID_Programs, FOLDERID_CommonPrograms}) {
        PWSTR found = nullptr;
        const HRESULT result = SHGetKnownFolderPath(folder, KF_FLAG_DEFAULT, nullptr, &found);
        const std::unique_ptr<wchar_t, decltype(&CoTaskMemFree)> path(found, &CoTaskMemFree);
        if (FAILED(result)) {
            continue;
        }

        const std::filesystem::path programs(path.get());
        std::error_code error;
        for (auto entry = std::filesystem::recursive_directory_iterator(programs, error); !error && entry != std::filesystem::recursive_directory_iterator(); entry.increment(error)) {
            if (entry->path().extension() != L".lnk") {
                continue;
            }
            const std::optional<GUID> activator = read(entry->path(), identifier);
            if (activator) {
                return activator;
            }
        }
    }
    return std::nullopt;
}

bool NotificationsShortcut::isRegistered(const GUID& activator) {
    wchar_t text[64];
    StringFromGUID2(activator, text, static_cast<int>(std::size(text)));
    const std::wstring key = std::wstring(L"CLSID\\") + text + L"\\LocalServer32";
    return RegGetValueW(HKEY_CLASSES_ROOT, key.c_str(), nullptr, RRF_RT_REG_SZ | RRF_RT_REG_EXPAND_SZ, nullptr, nullptr, nullptr) == ERROR_SUCCESS;
}

std::optional<GUID> NotificationsShortcut::read(const std::filesystem::path& file, const std::wstring& identifier) {
    winrt::com_ptr<IShellLinkW> link;
    if (FAILED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(link.put())))) {
        return std::nullopt;
    }
    const auto persisted = link.try_as<IPersistFile>();
    const auto properties = link.try_as<IPropertyStore>();
    if (!persisted || !properties || FAILED(persisted->Load(file.c_str(), STGM_READ))) {
        return std::nullopt;
    }

    PROPVARIANT value;
    PropVariantInit(&value);
    const bool matches = SUCCEEDED(properties->GetValue(PKEY_AppUserModel_ID, &value)) && value.vt == VT_LPWSTR && identifier == value.pwszVal;
    PropVariantClear(&value);
    if (!matches) {
        return std::nullopt;
    }

    GUID activator = GUID_NULL;
    if (SUCCEEDED(properties->GetValue(PKEY_AppUserModel_ToastActivatorCLSID, &value)) && value.vt == VT_CLSID && value.puuid != nullptr) {
        activator = *value.puuid;
    }
    PropVariantClear(&value);
    return activator;
}
