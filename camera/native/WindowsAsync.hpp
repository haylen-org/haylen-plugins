#pragma once

#include <windows.foundation.h>
#include <wrl/event.h>
#include <wrl/wrappers/corewrappers.h>

// Waits on the thread of the library for an asynchronous operation of the Windows Runtime and returns its status, which `GetResults` follows.
class WindowsAsync final {
  public:
    template <typename Result> static ABI::Windows::Foundation::AsyncStatus wait(ABI::Windows::Foundation::IAsyncOperation<Result>* operation) {
        using ABI::Windows::Foundation::AsyncStatus;
        using ABI::Windows::Foundation::IAsyncOperation;
        using ABI::Windows::Foundation::IAsyncOperationCompletedHandler;

        Microsoft::WRL::Wrappers::Event finished(CreateEventExW(nullptr, nullptr, CREATE_EVENT_MANUAL_RESET, EVENT_ALL_ACCESS));
        AsyncStatus outcome = AsyncStatus::Error;
        // clang-format off
        const auto completed = Microsoft::WRL::Callback<IAsyncOperationCompletedHandler<Result>>([&finished, &outcome](IAsyncOperation<Result>*, AsyncStatus status) {
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
