#pragma once

#include <windows.h>

#include <windows.foundation.h>
#include <wrl/client.h>
#include <wrl/event.h>
#include <wrl/wrappers/corewrappers.h>

// Waits on the thread of the library for an asynchronous operation of the Windows Runtime.
class WindowsLocationAsync final {
  public:
    // Returns the status that the operation ended with, which its `GetResults` follows.
    template <typename Result> static ABI::Windows::Foundation::AsyncStatus wait(ABI::Windows::Foundation::IAsyncOperation<Result>* operation) {
        using ABI::Windows::Foundation::AsyncStatus;
        using Completed = ABI::Windows::Foundation::IAsyncOperationCompletedHandler<Result>;

        Microsoft::WRL::Wrappers::Event finished(CreateEventExW(nullptr, nullptr, CREATE_EVENT_MANUAL_RESET, EVENT_ALL_ACCESS));
        AsyncStatus outcome = AsyncStatus::Error;
        // clang-format off
        const auto completed = Microsoft::WRL::Callback<Completed>([&finished, &outcome](ABI::Windows::Foundation::IAsyncOperation<Result>*, AsyncStatus status) {
            outcome = status;
            SetEvent(finished.Get());
            return S_OK;
        });
        // clang-format on
        if (FAILED(operation->put_Completed(completed.Get()))) {
            return AsyncStatus::Error;
        }
        WaitForSingleObject(finished.Get(), INFINITE);
        return outcome;
    }
};
