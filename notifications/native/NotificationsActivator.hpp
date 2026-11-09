#pragma once

#include <windows.h>

#include <NotificationActivationCallback.h>

#include <winrt/Windows.Foundation.h>

// The COM class of the toast activator, whose `Activate` Windows calls with the launch arguments of the toast that the person tapped, the JSON of the notification that the library wrote.
struct NotificationsActivator : winrt::implements<NotificationsActivator, INotificationActivationCallback> {
    // The class factory that the library registers with COM for the class of the activator while the app runs.
    struct Factory : winrt::implements<Factory, IClassFactory> {
        HRESULT __stdcall CreateInstance(IUnknown* outer, REFIID interfaceId, void** object) noexcept final;
        HRESULT __stdcall LockServer(BOOL) noexcept final;
    };

    HRESULT __stdcall Activate(LPCWSTR, LPCWSTR invokedArgs, const NOTIFICATION_USER_INPUT_DATA*, ULONG) noexcept final;
};
