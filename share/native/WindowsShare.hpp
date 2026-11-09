#pragma once

#include <windows.h>

#include <winrt/Windows.ApplicationModel.DataTransfer.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.h>

#include <cstdint>
#include <filesystem>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

#include "ShareRequest.hpp"
#include "WindowsShareWorker.hpp"
#include "haylen/platform/native/HaylenNative.h"

// The share of Windows: the share UI of `IDataTransferManagerInterop` over the window of the app, called with C++/WinRT. The handler runs on the frame thread, which owns the window of the app, and shows the UI there. Windows asks for the data once the UI shows, and the library hands it over with a deferral from a thread of its own, which writes the files of the share into a folder of its own in the temporary folder, emptied before every share, and opens them as storage files. The anchor of a share changes nothing, since Windows places its share UI itself.
class WindowsShare final {
  public:
    static void use(const HaylenNativeApi& value);

    // Called on the frame thread.
    static void show(std::uint64_t call, const HaylenNativeWindow& window, ShareRequest request);

  private:
    using DataPackage = winrt::Windows::ApplicationModel::DataTransfer::DataPackage;
    using DataRequestDeferral = winrt::Windows::ApplicationModel::DataTransfer::DataRequestDeferral;
    using DataRequestedEventArgs = winrt::Windows::ApplicationModel::DataTransfer::DataRequestedEventArgs;
    using DataTransferManager = winrt::Windows::ApplicationModel::DataTransfer::DataTransferManager;
    using Uri = winrt::Windows::Foundation::Uri;
    using StorageItems = winrt::Windows::Foundation::Collections::IVector<winrt::Windows::Storage::IStorageItem>;

    // The share that shows, with what the share UI hands the app that the person picks, which answers its call once the person shared or closed the UI.
    struct Showing {
        std::uint64_t call = 0;
        std::wstring title;
        std::optional<std::wstring> text;
        std::optional<Uri> url;
        std::vector<ShareRequest::File> files;
        std::string target;
    };

    // The thread of the library and the share that shows, which live as long as the process, since Windows may still call the library while the process exits.
    struct Session {
        WindowsShareWorker worker;
        std::mutex mutex;
        std::optional<Showing> showing;
        HWND window = nullptr;
        DataTransferManager manager{nullptr};
    };

    static const HaylenNativeApi* api;
    static Session* session;

    static void present(HWND window, Showing showing);
    static void requested(const DataRequestedEventArgs& args);
    static void fill(const DataRequestedEventArgs& args, const DataRequestDeferral& deferral);
    static void refuse(const DataRequestedEventArgs& args, const DataRequestDeferral& deferral, std::uint64_t call, const std::string& message);
    [[nodiscard]] static std::wstring readTitle(HWND window);
    [[nodiscard]] static std::filesystem::path getFolder();
    [[nodiscard]] static StorageItems stage(const std::vector<ShareRequest::File>& files);
    [[nodiscard]] static bool end(std::uint64_t call);
    static void finish(std::uint64_t call, bool shared, const std::string& reported);
};
