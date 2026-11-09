#include "NotificationsActivator.hpp"

#include "WindowsNotifications.hpp"

HRESULT __stdcall NotificationsActivator::Factory::CreateInstance(IUnknown* outer, REFIID interfaceId, void** object) noexcept {
    *object = nullptr;
    if (outer != nullptr) {
        return CLASS_E_NOAGGREGATION;
    }
    return winrt::make<NotificationsActivator>().as<IUnknown>()->QueryInterface(interfaceId, object);
}

HRESULT __stdcall NotificationsActivator::Factory::LockServer(BOOL) noexcept {
    return S_OK;
}

HRESULT __stdcall NotificationsActivator::Activate(LPCWSTR, LPCWSTR invokedArgs, const NOTIFICATION_USER_INPUT_DATA*, ULONG) noexcept {
    if (invokedArgs != nullptr) {
        WindowsNotifications::opened(winrt::to_string(invokedArgs));
    }
    return S_OK;
}
