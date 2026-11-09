#pragma once

#include <windows.h>

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include <nlohmann/json.hpp>
#include <winrt/Windows.Data.Xml.Dom.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.UI.Notifications.h>

#include "NotificationsWorker.hpp"
#include "haylen/platform/native/HaylenNative.h"

// The desktop part of the Notifications plugin on Windows, which schedules the toasts of the app with `Windows.UI.Notifications`, called with C++/WinRT, and Windows keeps them while the app is closed. A desktop app shows toasts only under the AppUserModelID of a shortcut of the Start menu, and Windows hands the tap on a toast to the COM class that the shortcut names as its toast activator, starting the app for it when the app is closed. The installer of the app creates the shortcut and registers the class, and the library checks both, registers the class while the app runs and sends each tap as the retained event `notifications.opened`. The handlers run on the frame thread and hand their work to a thread of the library in the multithreaded apartment.
class WindowsNotifications final {
  public:
    // Creates the library, which lives as long as the process, since Windows may still call the activator while the process exits, and registers its methods. Returns 1 when the engine hands a native API of another version.
    [[nodiscard]] static int initialize(const HaylenNativeApi* api);

    // Sends the tap on a toast as `{id, data}`, retained, so the tap that started the app reaches the first listener.
    static void opened(std::string_view launch);

  private:
    using Json = nlohmann::json;
    using ToastNotifier = winrt::Windows::UI::Notifications::ToastNotifier;
    using XmlDocument = winrt::Windows::Data::Xml::Dom::XmlDocument;

    // A failure that a call answers with its code, its sentence and its data, which is null when it has none.
    struct Failure {
        std::string code;
        std::string message;
        Json data;
    };

    // The group of every toast of the plugin, so the plugin cancels only its own.
    static constexpr wchar_t kGroup[] = L"notifications";
    static constexpr std::string_view kNoShortcut = "The app has no shortcut of the Start menu with its AppUserModelID and its toast activator, which the notifications of Windows need.";
    static constexpr std::string_view kRefused = "Windows does not let the app show notifications.";

    static inline WindowsNotifications* instance = nullptr;

    explicit WindowsNotifications(const HaylenNativeApi& engine);

    static void handle(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);

    [[nodiscard]] static std::string write(const Json& value);
    [[nodiscard]] static std::string text(const Json& params, const char* key);
    [[nodiscard]] static std::wstring executableName();
    [[nodiscard]] static std::wstring escapeXml(std::string_view text);
    [[nodiscard]] static double now();
    [[nodiscard]] static double dateOf(const Json& notification);
    [[nodiscard]] static Json launchOf(const XmlDocument& content);
    [[nodiscard]] static Json list(std::vector<Json> notifications);
    [[nodiscard]] static std::string state(const ToastNotifier& notifier);
    static void registerActivator(const GUID& activator);

    void run(std::uint64_t call, const std::string& name, const std::string& paramsJson);
    [[nodiscard]] Json dispatch(const std::string& name, const Json& params);
    void configure(const Json& params);

    // Checks the shortcut of the app and its toast activator once they exist, logs once what is missing, and registers the activator for the taps while the app runs. Returns what is missing, or nothing once the app is ready.
    [[nodiscard]] std::optional<Json> missing();

    [[nodiscard]] Json permission();
    [[nodiscard]] ToastNotifier ready();
    [[nodiscard]] Json schedule(const ToastNotifier& notifier, const Json& params);
    void cancel(const ToastNotifier& notifier, const std::string& id);
    void cancelAll(const ToastNotifier& notifier);
    [[nodiscard]] Json pending(const ToastNotifier& notifier);
    [[nodiscard]] Json delivered();

    const HaylenNativeApi& api;
    NotificationsWorker worker;
    std::wstring identifier;
    bool isReady = false;
    bool logged = false;
};
