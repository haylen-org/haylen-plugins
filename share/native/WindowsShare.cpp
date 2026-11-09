#include "WindowsShare.hpp"

#include <shobjidl_core.h>

#include <fstream>
#include <string_view>
#include <system_error>
#include <utility>

#include "ShareAnswer.hpp"

const HaylenNativeApi* WindowsShare::api = nullptr;
WindowsShare::Session* WindowsShare::session = nullptr;

void WindowsShare::use(const HaylenNativeApi& value) {
    api = &value;
    session = new Session();
}

void WindowsShare::show(std::uint64_t call, const HaylenNativeWindow& window, ShareRequest request) {
    const auto handle = static_cast<HWND>(window.handle);
    {
        const std::scoped_lock lock(session->mutex);
        if (session->showing) {
            ShareAnswer::fail(call, "busy", "The share sheet already shows.");
            return;
        }
    }

    Showing showing{.call = call};
    if (request.text) {
        showing.text = winrt::to_hstring(*request.text).c_str();
    }
    if (request.url) {
        try {
            showing.url = Uri(winrt::to_hstring(*request.url));
        } catch (const winrt::hresult_error&) {
            ShareAnswer::fail(call, "invalidUrl", "The url \"" + *request.url + "\" of the share is not valid.");
            return;
        }
    }
    showing.files = std::move(request.files);

    // Windows refuses a share without a title, so a share without one takes the title of the window of the app.
    showing.title = request.title ? std::wstring(winrt::to_hstring(*request.title).c_str()) : readTitle(handle);

    try {
        present(handle, std::move(showing));
    } catch (const winrt::hresult_error& error) {
        {
            const std::scoped_lock lock(session->mutex);
            session->showing.reset();
        }
        ShareAnswer::fail(call, "failed", "Windows did not show its share UI: " + winrt::to_string(error.message()));
    }
}

// The frame thread joins a single-threaded apartment of COM if it is in none yet, which the share UI of the window needs. The data manager of a window lives as long as the window, so the library hears its events once per window, and each event serves the share that shows.
void WindowsShare::present(HWND window, Showing showing) {
    const HRESULT joined = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(joined) && joined != RPC_E_CHANGED_MODE) {
        winrt::throw_hresult(joined);
    }
    const auto interop = winrt::get_activation_factory<DataTransferManager, IDataTransferManagerInterop>();
    if (session->window != window) {
        DataTransferManager manager{nullptr};
        winrt::check_hresult(interop->GetForWindow(window, winrt::guid_of<DataTransferManager>(), winrt::put_abi(manager)));
        // clang-format off
        manager.DataRequested([](const DataTransferManager&, const DataRequestedEventArgs& args) {
            requested(args);
        });
        manager.TargetApplicationChosen([](const DataTransferManager&, const winrt::Windows::ApplicationModel::DataTransfer::TargetApplicationChosenEventArgs& args) {
            const std::scoped_lock lock(session->mutex);
            if (session->showing) {
                session->showing->target = winrt::to_string(args.ApplicationName());
            }
        });
        // clang-format on
        session->manager = manager;
        session->window = window;
    }

    {
        const std::scoped_lock lock(session->mutex);
        session->showing = std::move(showing);
    }
    api->coverApp();
    const HRESULT shown = interop->ShowShareUIForWindow(window);
    if (FAILED(shown)) {
        api->uncoverApp();
        winrt::throw_hresult(shown);
    }
}

// Windows asks for the data on a thread that must not block, so the library fills it on its own thread under a deferral.
void WindowsShare::requested(const DataRequestedEventArgs& args) {
    const DataRequestDeferral deferral = args.Request().GetDeferral();
    session->worker.post([args, deferral] { fill(args, deferral); });
}

// Writes the files of the share, opens them as storage files and hands Windows the data, on the thread of the library. The package of each share answers the call of that share alone.
void WindowsShare::fill(const DataRequestedEventArgs& args, const DataRequestDeferral& deferral) {
    std::optional<Showing> showing;
    {
        const std::scoped_lock lock(session->mutex);
        showing = session->showing;
    }
    if (!showing) {
        deferral.Complete();
        return;
    }

    const std::uint64_t call = showing->call;
    try {
        const DataPackage package = args.Request().Data();
        package.Properties().Title(showing->title);
        if (showing->text) {
            package.SetText(*showing->text);
        }
        if (showing->url) {
            package.SetWebLink(*showing->url);
        }
        if (!showing->files.empty()) {
            package.SetStorageItems(stage(showing->files));
        }
        // clang-format off
        package.ShareCompleted([call](const DataPackage&, const winrt::Windows::ApplicationModel::DataTransfer::ShareCompletedEventArgs& completion) {
            const auto shareTarget = completion.ShareTarget();
            finish(call, true, shareTarget ? winrt::to_string(shareTarget.AppUserModelId()) : std::string());
        });
        package.ShareCanceled([call](const DataPackage&, const winrt::Windows::Foundation::IInspectable&) {
            finish(call, false, std::string());
        });
        // clang-format on
        deferral.Complete();
    } catch (const winrt::hresult_error& error) {
        refuse(args, deferral, call, "The files of the share could not be written: " + winrt::to_string(error.message()));
    } catch (const std::filesystem::filesystem_error& error) {
        refuse(args, deferral, call, std::string("The files of the share could not be written: ") + error.what());
    }
}

// Tells the share UI why the data is missing and fails the call.
void WindowsShare::refuse(const DataRequestedEventArgs& args, const DataRequestDeferral& deferral, std::uint64_t call, const std::string& message) {
    args.Request().FailWithDisplayText(winrt::to_hstring(message));
    deferral.Complete();
    if (end(call)) {
        ShareAnswer::fail(call, "failed", message);
    }
}

std::wstring WindowsShare::readTitle(HWND window) {
    std::wstring caption(static_cast<std::size_t>(GetWindowTextLengthW(window)) + 1, L'\0');
    caption.resize(static_cast<std::size_t>(GetWindowTextW(window, caption.data(), static_cast<int>(caption.size()))));
    return caption;
}

// The folder `share` of the app in the temporary folder, named after the executable of the app, since the temporary folder of Windows belongs to every app of the person.
std::filesystem::path WindowsShare::getFolder() {
    std::wstring executable(MAX_PATH, L'\0');
    executable.resize(GetModuleFileNameW(nullptr, executable.data(), static_cast<DWORD>(executable.size())));
    return std::filesystem::temp_directory_path() / (std::filesystem::path(executable).stem().wstring() + L"-share");
}

WindowsShare::StorageItems WindowsShare::stage(const std::vector<ShareRequest::File>& files) {
    const std::filesystem::path folder = getFolder();
    std::filesystem::remove_all(folder);
    std::filesystem::create_directories(folder);

    StorageItems items = winrt::single_threaded_vector<winrt::Windows::Storage::IStorageItem>();
    for (const ShareRequest::File& file : files) {
        const winrt::hstring name = winrt::to_hstring(file.name);
        const std::filesystem::path path = folder / std::wstring_view(name);
        std::ofstream stream(path, std::ios::binary);
        stream.write(reinterpret_cast<const char*>(file.bytes.data()), static_cast<std::streamsize>(file.bytes.size()));
        stream.close();
        if (!stream) {
            throw std::filesystem::filesystem_error("The file did not write", path, std::make_error_code(std::errc::io_error));
        }
        items.Append(winrt::Windows::Storage::StorageFile::GetFileFromPathAsync(path.wstring()).get());
    }
    return items;
}

// Ends the share of the call, if it still shows, and uncovers the app.
bool WindowsShare::end(std::uint64_t call) {
    {
        const std::scoped_lock lock(session->mutex);
        if (!session->showing || session->showing->call != call) {
            return false;
        }
        session->showing.reset();
    }
    api->uncoverApp();
    return true;
}

// Answers the call with whether the person shared and where, the app that the person picked or the identity of the target that Windows reports.
void WindowsShare::finish(std::uint64_t call, bool shared, const std::string& reported) {
    std::string target;
    {
        const std::scoped_lock lock(session->mutex);
        if (session->showing && session->showing->call == call) {
            target = session->showing->target.empty() ? reported : session->showing->target;
        }
    }
    if (!end(call)) {
        return;
    }
    ShareAnswer::finish(call, shared, target);
}
