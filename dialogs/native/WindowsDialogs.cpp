#include "WindowsDialogs.hpp"

#include <commctrl.h>
#include <knownfolders.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <filesystem>
#include <format>
#include <fstream>
#include <system_error>
#include <thread>
#include <utility>

#include "DialogsAnswer.hpp"

const HaylenNativeApi* WindowsDialogs::api = nullptr;
std::mutex& WindowsDialogs::mutex = *new std::mutex();
std::deque<WindowsDialogs::Queued>& WindowsDialogs::queue = *new std::deque<Queued>();
WindowsDialogs::Active WindowsDialogs::active{};
HWND WindowsDialogs::window = nullptr;
bool WindowsDialogs::started = false;
bool WindowsDialogs::showing = false;

void WindowsDialogs::use(const HaylenNativeApi& value) noexcept {
    api = &value;
}

// The thread starts with the first dialog and shows what waits once its window exists, so a request never needs the window before it does.
void WindowsDialogs::show(std::uint64_t call, DialogsRequest request) {
    HaylenNativeWindow app{};
    if (api->getWindow(&app) == 0) {
        DialogsAnswer::fail(call, "failed", "The app has no window to show the dialog on.");
        return;
    }
    const auto owner = static_cast<HWND>(app.handle);
    std::wstring ownerTitle(static_cast<std::size_t>(GetWindowTextLengthW(owner)) + 1, L'\0');
    ownerTitle.resize(static_cast<std::size_t>(GetWindowTextW(owner, ownerTitle.data(), static_cast<int>(ownerTitle.size()))));

    HWND target = nullptr;
    {
        const std::scoped_lock lock(mutex);
        queue.push_back({.call = call, .request = std::move(request), .owner = owner, .ownerTitle = std::move(ownerTitle)});
        target = window;
    }
    if (!started) {
        started = true;
        std::thread(run).detach();
        return;
    }
    if (target != nullptr) {
        PostMessageW(target, kShowMessage, 0, 0);
    }
}

void WindowsDialogs::cancel(std::uint64_t call) {
    const std::scoped_lock lock(mutex);
    // clang-format off
    const std::size_t forgotten = std::erase_if(queue, [call](const Queued& queued) {
        return queued.call == call;
    });
    // clang-format on
    if (forgotten > 0 || active.call != call) {
        return;
    }
    active.cancelled = true;
    PostMessageW(window, kCancelMessage, 0, 0);
}

void WindowsDialogs::run() {
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    WNDCLASSEXW windowClass{};
    windowClass.cbSize = sizeof(windowClass);
    windowClass.lpfnWndProc = windowProcedure;
    windowClass.hInstance = GetModuleHandleW(nullptr);
    windowClass.lpszClassName = kWindowClass;
    RegisterClassExW(&windowClass);
    const HWND created = CreateWindowExW(0, kWindowClass, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, windowClass.hInstance, nullptr);
    {
        const std::scoped_lock lock(mutex);
        window = created;
    }

    showQueued();
    MSG message{};
    while (GetMessageW(&message, nullptr, 0, 0) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
}

// The modal loop of a dialog dispatches the requests that arrive meanwhile, which wait for the dialog to close instead of showing over it.
void WindowsDialogs::showQueued() {
    if (showing) {
        return;
    }
    showing = true;
    for (;;) {
        std::unique_lock lock(mutex);
        if (queue.empty()) {
            break;
        }
        const Queued next = std::move(queue.front());
        queue.pop_front();
        active = {.call = next.call};
        lock.unlock();

        showDialog(next);
        lock.lock();
        active = {};
    }
    showing = false;
}

// A task dialog closes as if the person pressed Escape and a file dialog as if the person cancelled it. A task dialog that the app gave up before its window existed closes once it does.
void WindowsDialogs::closeActive() {
    HWND taskDialog = nullptr;
    IFileDialog* fileDialog = nullptr;
    {
        const std::scoped_lock lock(mutex);
        if (!active.cancelled) {
            return;
        }
        taskDialog = active.taskDialog;
        fileDialog = active.fileDialog;
    }
    if (taskDialog != nullptr) {
        SendMessageW(taskDialog, TDM_CLICK_BUTTON, IDCANCEL, 0);
        return;
    }
    if (fileDialog != nullptr) {
        fileDialog->Close(HRESULT_FROM_WIN32(ERROR_CANCELLED));
    }
}

void WindowsDialogs::showDialog(const Queued& queued) {
    switch (queued.request.method) {
    case DialogsRequest::Method::Message:
        showMessage(queued);
        return;
    case DialogsRequest::Method::OpenFiles:
        showOpenFiles(queued, queued.request.filters, nullptr);
        return;
    case DialogsRequest::Method::SaveFile:
        showSaveFile(queued);
        return;
    case DialogsRequest::Method::OpenFolder:
        showOpenFolder(queued);
        return;
    case DialogsRequest::Method::OpenPhotos: {
        // The photos of Windows are image files, so the dialog of images opens in the Pictures folder.
        DialogsRequest::Filter images{.name = "Images", .extensions = {}};
        images.extensions.assign(std::begin(DialogsRequest::kImageExtensions), std::end(DialogsRequest::kImageExtensions));
        Microsoft::WRL::ComPtr<IShellItem> pictures;
        SHGetKnownFolderItem(FOLDERID_Pictures, KF_FLAG_DEFAULT, nullptr, IID_PPV_ARGS(pictures.GetAddressOf()));
        showOpenFiles(queued, {images}, pictures.Get());
        return;
    }
    }
}

// The task dialog lives in version 6 of the Common Controls, which the application manifest of Haylen apps selects, so it is looked up when a message shows. Escape and the close button dismiss it without a button.
void WindowsDialogs::showMessage(const Queued& queued) {
    const DialogsRequest& request = queued.request;
    const HMODULE controls = LoadLibraryW(L"comctl32.dll");
    // The address of a function of a library comes without its type, which the cast through a function without parameters restores.
    const auto found = controls != nullptr ? reinterpret_cast<void (*)()>(GetProcAddress(controls, "TaskDialogIndirect")) : nullptr;
    const auto showTaskDialog = reinterpret_cast<decltype(&TaskDialogIndirect)>(found);
    if (showTaskDialog == nullptr) {
        DialogsAnswer::fail(queued.call, "failed", "Message dialogs need version 6 of the Common Controls, which the application manifest of Haylen apps selects.");
        return;
    }

    const std::wstring title = toWide(request.title);
    const std::wstring text = toWide(request.text);
    std::vector<std::wstring> labels;
    std::vector<TASKDIALOG_BUTTON> buttons;
    labels.reserve(request.buttons.size());
    for (const std::string& label : request.buttons) {
        labels.push_back(toWide(label));
        buttons.push_back({.nButtonID = kFirstButton + static_cast<int>(buttons.size()), .pszButtonText = labels.back().c_str()});
    }

    TASKDIALOGCONFIG config{};
    config.cbSize = sizeof(config);
    config.hwndParent = queued.owner;
    config.dwFlags = TDF_ALLOW_DIALOG_CANCELLATION | TDF_POSITION_RELATIVE_TO_WINDOW;
    config.pszWindowTitle = queued.ownerTitle.empty() ? nullptr : queued.ownerTitle.c_str();
    switch (request.kind) {
    case DialogsRequest::Kind::Info:
        config.pszMainIcon = TD_INFORMATION_ICON;
        break;
    case DialogsRequest::Kind::Warning:
        config.pszMainIcon = TD_WARNING_ICON;
        break;
    case DialogsRequest::Kind::Error:
        config.pszMainIcon = TD_ERROR_ICON;
        break;
    }
    config.pszMainInstruction = title.empty() ? nullptr : title.c_str();
    config.pszContent = text.c_str();
    config.cButtons = static_cast<UINT>(buttons.size());
    config.pButtons = buttons.data();
    config.nDefaultButton = kFirstButton;
    config.pfCallback = taskDialogCallback;

    int pressed = 0;
    const HRESULT result = showTaskDialog(&config, &pressed, nullptr, nullptr);
    if (FAILED(result)) {
        fail(queued.call, "The message could not be shown.", result);
        return;
    }
    const int index = pressed - kFirstButton;
    if (index < 0 || index >= static_cast<int>(buttons.size())) {
        DialogsAnswer::dismissed(queued.call);
        return;
    }
    DialogsAnswer::button(queued.call, static_cast<std::size_t>(index) + 1);
}

void WindowsDialogs::showOpenFiles(const Queued& queued, const std::vector<DialogsRequest::Filter>& filters, IShellItem* folder) {
    Microsoft::WRL::ComPtr<IFileOpenDialog> dialog;
    HRESULT result = CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(dialog.GetAddressOf()));
    if (FAILED(result)) {
        fail(queued.call, "The file dialog could not be created.", result);
        return;
    }
    FILEOPENDIALOGOPTIONS options = 0;
    dialog->GetOptions(&options);
    options |= FOS_FORCEFILESYSTEM | FOS_FILEMUSTEXIST;
    if (queued.request.multiple) {
        options |= FOS_ALLOWMULTISELECT;
    }
    dialog->SetOptions(options);
    prepare(*dialog.Get(), queued.request.title, filters);
    if (folder != nullptr) {
        dialog->SetDefaultFolder(folder);
    }

    result = showFileDialog(*dialog.Get(), queued.owner);
    if (result == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
        DialogsAnswer::dismissed(queued.call);
        return;
    }
    Microsoft::WRL::ComPtr<IShellItemArray> items;
    DWORD count = 0;
    if (SUCCEEDED(result)) {
        result = dialog->GetResults(items.GetAddressOf());
    }
    if (SUCCEEDED(result)) {
        result = items->GetCount(&count);
    }
    if (FAILED(result)) {
        fail(queued.call, "The file dialog failed.", result);
        return;
    }

    std::vector<DialogsAnswer::File> files;
    for (DWORD index = 0; index < count; ++index) {
        Microsoft::WRL::ComPtr<IShellItem> item;
        if (SUCCEEDED(items->GetItemAt(index, item.GetAddressOf()))) {
            const std::filesystem::path path = readPath(*item.Get());
            files.push_back({.name = toUtf8(path.filename().native()), .path = toUtf8(path.native())});
        }
    }
    DialogsAnswer::files(queued.call, files);
}

// The dialog adds the extension of the chosen type to a name typed without one, and asks before it replaces a file.
void WindowsDialogs::showSaveFile(const Queued& queued) {
    const DialogsRequest& request = queued.request;
    Microsoft::WRL::ComPtr<IFileSaveDialog> dialog;
    HRESULT result = CoCreateInstance(CLSID_FileSaveDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(dialog.GetAddressOf()));
    if (FAILED(result)) {
        fail(queued.call, "The file dialog could not be created.", result);
        return;
    }
    FILEOPENDIALOGOPTIONS options = 0;
    dialog->GetOptions(&options);
    dialog->SetOptions(options | FOS_FORCEFILESYSTEM | FOS_OVERWRITEPROMPT);
    prepare(*dialog.Get(), request.title, request.filters);
    dialog->SetFileName(toWide(request.name).c_str());
    if (!request.filters.empty()) {
        dialog->SetDefaultExtension(toWide(request.filters.front().extensions.front()).c_str());
    }

    result = showFileDialog(*dialog.Get(), queued.owner);
    if (result == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
        DialogsAnswer::dismissed(queued.call);
        return;
    }
    Microsoft::WRL::ComPtr<IShellItem> item;
    if (SUCCEEDED(result)) {
        result = dialog->GetResult(item.GetAddressOf());
    }
    if (FAILED(result)) {
        fail(queued.call, "The file dialog failed.", result);
        return;
    }

    const std::filesystem::path path = readPath(*item.Get());
    const std::string name = toUtf8(path.filename().native());
    std::ofstream stream(path, std::ios::binary | std::ios::trunc);
    stream.write(reinterpret_cast<const char*>(request.bytes.data()), static_cast<std::streamsize>(request.bytes.size()));
    stream.close();
    if (!stream) {
        DialogsAnswer::fail(queued.call, "failed", std::format("The file \"{}\" could not be written.", name));
        return;
    }
    DialogsAnswer::saved(queued.call, {.name = name, .path = toUtf8(path.native())});
}

void WindowsDialogs::showOpenFolder(const Queued& queued) {
    Microsoft::WRL::ComPtr<IFileOpenDialog> dialog;
    HRESULT result = CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(dialog.GetAddressOf()));
    if (FAILED(result)) {
        fail(queued.call, "The folder dialog could not be created.", result);
        return;
    }
    FILEOPENDIALOGOPTIONS options = 0;
    dialog->GetOptions(&options);
    dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM);
    prepare(*dialog.Get(), queued.request.title, {});

    result = showFileDialog(*dialog.Get(), queued.owner);
    if (result == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
        DialogsAnswer::dismissed(queued.call);
        return;
    }
    Microsoft::WRL::ComPtr<IShellItem> item;
    if (SUCCEEDED(result)) {
        result = dialog->GetResult(item.GetAddressOf());
    }
    if (FAILED(result)) {
        fail(queued.call, "The folder dialog failed.", result);
        return;
    }
    DialogsAnswer::folder(queued.call, toUtf8(readPath(*item.Get())));
}

// The dialog copies the names and patterns of the file types, so they only live while it takes them.
void WindowsDialogs::prepare(IFileDialog& dialog, const std::string& title, const std::vector<DialogsRequest::Filter>& filters) {
    if (!title.empty()) {
        dialog.SetTitle(toWide(title).c_str());
    }
    std::vector<std::wstring> names;
    std::vector<std::wstring> patterns;
    for (const DialogsRequest::Filter& filter : filters) {
        names.push_back(toWide(filter.name));
        std::wstring pattern;
        for (const std::string& extension : filter.extensions) {
            pattern += (pattern.empty() ? L"*." : L";*.") + toWide(extension);
        }
        patterns.push_back(std::move(pattern));
    }

    std::vector<COMDLG_FILTERSPEC> types;
    for (std::size_t index = 0; index < names.size(); ++index) {
        types.push_back({.pszName = names[index].c_str(), .pszSpec = patterns[index].c_str()});
    }
    if (!types.empty()) {
        dialog.SetFileTypes(static_cast<UINT>(types.size()), types.data());
    }
}

// The dialog becomes the active one while it shows, so a cancel that arrives during its modal loop closes it.
HRESULT WindowsDialogs::showFileDialog(IFileDialog& dialog, HWND owner) {
    {
        const std::scoped_lock lock(mutex);
        if (active.cancelled) {
            return HRESULT_FROM_WIN32(ERROR_CANCELLED);
        }
        active.fileDialog = &dialog;
    }
    const HRESULT result = dialog.Show(owner);
    const std::scoped_lock lock(mutex);
    active.fileDialog = nullptr;
    return result;
}

std::wstring WindowsDialogs::readPath(IShellItem& item) {
    PWSTR path = nullptr;
    if (FAILED(item.GetDisplayName(SIGDN_FILESYSPATH, &path))) {
        return {};
    }
    std::wstring text(path);
    CoTaskMemFree(path);
    return text;
}

void WindowsDialogs::fail(std::uint64_t call, const std::string& message, HRESULT result) {
    DialogsAnswer::fail(call, "failed", std::format("{} Windows reported \"{}\".", message, std::system_category().message(static_cast<int>(result))));
}

std::wstring WindowsDialogs::toWide(std::string_view text) {
    if (text.empty()) {
        return {};
    }
    const int size = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
    std::wstring wide(static_cast<std::size_t>(size), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), wide.data(), size);
    return wide;
}

std::string WindowsDialogs::toUtf8(std::wstring_view text) {
    if (text.empty()) {
        return {};
    }
    const int size = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
    std::string narrow(static_cast<std::size_t>(size), '\0');
    WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), narrow.data(), size, nullptr, nullptr);
    return narrow;
}

HRESULT CALLBACK WindowsDialogs::taskDialogCallback(HWND dialog, UINT notification, WPARAM, LPARAM, LONG_PTR) {
    const std::scoped_lock lock(mutex);
    switch (notification) {
    case TDN_CREATED:
        active.taskDialog = dialog;
        if (active.cancelled) {
            PostMessageW(dialog, TDM_CLICK_BUTTON, IDCANCEL, 0);
        }
        break;
    case TDN_DESTROYED:
        active.taskDialog = nullptr;
        break;
    default:
        break;
    }
    return S_OK;
}

LRESULT CALLBACK WindowsDialogs::windowProcedure(HWND handle, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case kShowMessage:
        showQueued();
        return 0;
    case kCancelMessage:
        closeActive();
        return 0;
    default:
        return DefWindowProcW(handle, message, wParam, lParam);
    }
}
