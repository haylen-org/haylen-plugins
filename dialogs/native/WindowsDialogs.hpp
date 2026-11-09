#pragma once

#include <windows.h>

#include <cstdint>
#include <deque>
#include <mutex>
#include <string>
#include <string_view>
#include <vector>

#include "DialogsRequest.hpp"
#include "haylen/platform/native/HaylenNative.h"

struct IFileDialog;
struct IShellItem;

// The dialogs of Windows, which a thread of the library shows one after the other, owned by the window of the app, so the frame thread never waits for them. A message is a task dialog, and the pickers are the file dialogs of the shell. The thread lives in a single-threaded COM apartment with a message-only window, which receives the requests and closes a dialog that the app gave up, even while a dialog runs its modal loop.
class WindowsDialogs final {
  public:
    static void use(const HaylenNativeApi& value) noexcept;

    // Called on the frame thread.
    static void show(std::uint64_t call, DialogsRequest request);

    // Closes a dialog that the app gave up, or forgets it while it still waits for its turn.
    static void cancel(std::uint64_t call);

  private:
    static constexpr UINT kShowMessage = WM_APP + 1;
    static constexpr UINT kCancelMessage = WM_APP + 2;
    static constexpr int kFirstButton = 100;
    static constexpr const wchar_t* kWindowClass = L"HaylenDialogsPlugin";

    struct Queued {
        std::uint64_t call = 0;
        DialogsRequest request;
        HWND owner = nullptr;
        std::wstring ownerTitle;
    };

    // The dialog that shows, with the window of a task dialog once it exists or the file dialog that shows.
    struct Active {
        std::uint64_t call = 0;
        bool cancelled = false;
        HWND taskDialog = nullptr;
        IFileDialog* fileDialog = nullptr;
    };

    static const HaylenNativeApi* api;
    static std::mutex& mutex;
    static std::deque<Queued>& queue;
    static Active active;
    static HWND window;
    static bool started;
    static bool showing;

    static void run();
    static void showQueued();
    static void closeActive();
    static void showDialog(const Queued& queued);
    static void showMessage(const Queued& queued);
    static void showOpenFiles(const Queued& queued, const std::vector<DialogsRequest::Filter>& filters, IShellItem* folder);
    static void showSaveFile(const Queued& queued);
    static void showOpenFolder(const Queued& queued);
    static void prepare(IFileDialog& dialog, const std::string& title, const std::vector<DialogsRequest::Filter>& filters);
    [[nodiscard]] static HRESULT showFileDialog(IFileDialog& dialog, HWND owner);
    [[nodiscard]] static std::wstring readPath(IShellItem& item);
    static void fail(std::uint64_t call, const std::string& message, HRESULT result);
    [[nodiscard]] static std::wstring toWide(std::string_view text);
    [[nodiscard]] static std::string toUtf8(std::wstring_view text);
    static HRESULT CALLBACK taskDialogCallback(HWND dialog, UINT notification, WPARAM wParam, LPARAM lParam, LONG_PTR data);
    static LRESULT CALLBACK windowProcedure(HWND handle, UINT message, WPARAM wParam, LPARAM lParam);
};
