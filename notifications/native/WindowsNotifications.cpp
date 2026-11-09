#include "WindowsNotifications.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <utility>

#include <winrt/Windows.Foundation.Collections.h>

#include "NotificationsActivator.hpp"
#include "NotificationsShortcut.hpp"

using winrt::Windows::UI::Notifications::NotificationSetting;
using winrt::Windows::UI::Notifications::ScheduledToastNotification;
using winrt::Windows::UI::Notifications::ToastNotification;
using winrt::Windows::UI::Notifications::ToastNotificationManager;

int WindowsNotifications::initialize(const HaylenNativeApi* engine) {
    if (engine->version != HAYLEN_NATIVE_API_VERSION) {
        return 1;
    }
    instance = new WindowsNotifications(*engine);

    for (const char* method : {"notifications.configure", "notifications.schedule", "notifications.cancel", "notifications.cancelAll", "notifications.pending", "notifications.delivered", "notifications.permission", "notifications.requestPermission"}) {
        engine->registerHandler(method, &WindowsNotifications::handle, nullptr, instance);
    }
    engine->registerPlugin("notifications");
    return 0;
}

WindowsNotifications::WindowsNotifications(const HaylenNativeApi& engine) : api(engine) {}

void WindowsNotifications::opened(std::string_view launch) {
    const Json notification = Json::parse(launch, nullptr, false);
    const auto id = notification.find("id");
    if (!notification.is_object() || id == notification.end() || !id->is_string()) {
        return;
    }

    const auto data = notification.find("data");
    const Json payload = {{"id", *id}, {"data", data != notification.end() ? *data : Json(nullptr)}};
    const std::string text = write(payload);
    instance->api.emit("notifications.opened", text.c_str(), nullptr, 0, HAYLEN_NATIVE_EMIT_RETAIN);
}

void WindowsNotifications::handle(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer*, std::size_t) {
    auto& library = *static_cast<WindowsNotifications*>(user);
    std::string name = std::string(method).substr(std::string_view("notifications.").size());
    std::string params = paramsJson;
    // clang-format off
    library.worker.post([&library, call, name = std::move(name), params = std::move(params)] {
        library.run(call, name, params);
    });
    // clang-format on
}

std::string WindowsNotifications::write(const Json& value) {
    return value.dump(-1, ' ', false, Json::error_handler_t::replace);
}

std::string WindowsNotifications::text(const Json& params, const char* key) {
    const auto found = params.find(key);
    if (!params.is_object() || found == params.end() || !found->is_string()) {
        throw Failure{"invalidParams", "The call needs \"" + std::string(key) + "\" as a string.", nullptr};
    }
    return found->get<std::string>();
}

// The name of the executable of the app without its extension, which the shortcut of the installer starts.
std::wstring WindowsNotifications::executableName() {
    std::wstring path(MAX_PATH, L'\0');
    path.resize(GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size())));
    return std::filesystem::path(path).stem().wstring();
}

std::wstring WindowsNotifications::escapeXml(std::string_view text) {
    const winrt::hstring wide = winrt::to_hstring(text);
    std::wstring escaped;
    for (const wchar_t character : std::wstring_view(wide)) {
        switch (character) {
        case L'&':
            escaped += L"&amp;";
            break;
        case L'<':
            escaped += L"&lt;";
            break;
        case L'>':
            escaped += L"&gt;";
            break;
        case L'"':
            escaped += L"&quot;";
            break;
        default:
            escaped += character;
        }
    }
    return escaped;
}

double WindowsNotifications::now() {
    return std::chrono::duration<double>(std::chrono::system_clock::now().time_since_epoch()).count();
}

double WindowsNotifications::dateOf(const Json& notification) {
    const auto date = notification.find("date");
    if (!notification.is_object() || date == notification.end() || !date->is_number()) {
        return 0;
    }
    return date->get<double>();
}

// The JSON of the notification that a toast carries in its launch arguments.
WindowsNotifications::Json WindowsNotifications::launchOf(const XmlDocument& content) {
    const std::string launch = winrt::to_string(content.DocumentElement().GetAttribute(L"launch"));
    return Json::parse(launch, nullptr, false);
}

// Lists the notifications in the order of their dates.
WindowsNotifications::Json WindowsNotifications::list(std::vector<Json> notifications) {
    std::ranges::sort(notifications, {}, &WindowsNotifications::dateOf);
    Json result = Json::array();
    for (Json& notification : notifications) {
        result.push_back(std::move(notification));
    }
    return result;
}

// Windows asks the person for nothing, and the settings of the system turn the notifications of the app or of every app off. Windows keeps those settings for an app only once it showed its first toast, and until then the notifier tells nothing, which is the state `unknown`.
std::string WindowsNotifications::state(const ToastNotifier& notifier) {
    NotificationSetting setting = NotificationSetting::Enabled;
    try {
        setting = notifier.Setting();
    } catch (const winrt::hresult_error& error) {
        if (error.code() != HRESULT_FROM_WIN32(ERROR_NOT_FOUND)) {
            throw;
        }
        return "unknown";
    }

    switch (setting) {
    case NotificationSetting::Enabled:
        return "granted";
    case NotificationSetting::DisabledForApplication:
    case NotificationSetting::DisabledForUser:
    case NotificationSetting::DisabledByGroupPolicy:
        return "denied";
    case NotificationSetting::DisabledByManifest:
        return "unsupported";
    }
    return "unknown";
}

void WindowsNotifications::registerActivator(const GUID& activator) {
    DWORD cookie = 0;
    const auto factory = winrt::make<NotificationsActivator::Factory>();
    winrt::check_hresult(CoRegisterClassObject(activator, factory.as<IUnknown>().get(), CLSCTX_LOCAL_SERVER, REGCLS_MULTIPLEUSE, &cookie));
}

// Answers a call on the thread of the library. The parameters arrive as JSON text, which the library reads without exceptions, and every failure becomes an answer, since no exception may cross the C interface of the engine.
void WindowsNotifications::run(std::uint64_t call, const std::string& name, const std::string& paramsJson) {
    try {
        const std::string result = write(dispatch(name, Json::parse(paramsJson, nullptr, false)));
        api.resolve(call, 1, result.c_str(), nullptr, 0);
    } catch (const Failure& failure) {
        Json answer = {{"message", failure.message}, {"code", failure.code}};
        if (!failure.data.is_null()) {
            answer["data"] = failure.data;
        }
        const std::string text = write(answer);
        api.resolve(call, 0, text.c_str(), nullptr, 0);
    } catch (const winrt::hresult_error& error) {
        const std::string text = write({{"message", "Windows refused the call: " + winrt::to_string(error.message())}, {"code", "failed"}});
        api.resolve(call, 0, text.c_str(), nullptr, 0);
    }
}

WindowsNotifications::Json WindowsNotifications::dispatch(const std::string& name, const Json& params) {
    if (name == "configure") {
        configure(params);
        return Json::object();
    }
    if (name == "permission" || name == "requestPermission") {
        return permission();
    }

    const ToastNotifier notifier = ready();
    if (name == "schedule") {
        return schedule(notifier, params);
    }
    if (name == "cancel") {
        cancel(notifier, text(params, "id"));
        return Json::object();
    }
    if (name == "cancelAll") {
        cancelAll(notifier);
        return Json::object();
    }
    if (name == "pending") {
        return pending(notifier);
    }
    if (name == "delivered") {
        return delivered();
    }
    throw Failure{"failed", "The library of notifications has no method \"" + name + "\".", nullptr};
}

// Takes the identifier of the app, which the Lua API sends as it loads, as the AppUserModelID of its toasts.
void WindowsNotifications::configure(const Json& params) {
    identifier = winrt::to_hstring(text(params, "identifier")).c_str();
    isReady = false;
}

std::optional<WindowsNotifications::Json> WindowsNotifications::missing() {
    if (isReady) {
        return std::nullopt;
    }
    if (identifier.empty()) {
        throw Failure{"failed", "The Lua API of the plugin did not configure the library.", nullptr};
    }

    const std::optional<GUID> activator = NotificationsShortcut::find(identifier);
    if (activator && *activator != GUID_NULL && NotificationsShortcut::isRegistered(*activator)) {
        registerActivator(*activator);
        isReady = true;
        return std::nullopt;
    }

    const std::string name = winrt::to_string(identifier);
    const std::string executable = winrt::to_string(executableName());
    const std::string snippet = "Name: \"{autoprograms}\\<name>\"; Filename: \"{app}\\" + executable + ".exe\"; AppUserModelID: \"" + name + "\"; AppUserModelToastActivatorCLSID: \"<clsid>\" in [Icons], and Root: HKA; Subkey: \"Software\\Classes\\CLSID\\{{<clsid>}\\LocalServer32\"; ValueType: string; ValueData: \"\"\"{app}\\" + executable + ".exe\"\"\"; Flags: uninsdeletekey in [Registry]";
    if (!logged) {
        logged = true;
        const std::string line = "The notifications of Windows need a shortcut of the Start menu whose AppUserModelID is \"" + name + "\", with a toast activator that the installer registers. Add " + snippet + " to the Inno Setup script of the installer, as the README of the Notifications plugin describes, and run the app that it installs.";
        api.log(HAYLEN_NATIVE_LOG_WARNING, line.c_str());
    }

    const Json shortcut = {{"kind", "shortcut"}, {"name", name}, {"file", "platform/windows/notifications.iss"}, {"snippet", snippet}};
    Json absent = Json::array();
    absent.push_back(shortcut);
    return absent;
}

// Answers the name of the state, and fails with the code `unsupported` where the project lacks the shortcut or the settings of the system turn the notifications off.
WindowsNotifications::Json WindowsNotifications::permission() {
    if (const std::optional<Json> absent = missing()) {
        throw Failure{"unsupported", std::string(kNoShortcut), {{"missing", *absent}}};
    }

    const std::string answer = state(ToastNotificationManager::CreateToastNotifier(identifier));
    if (answer == "unsupported") {
        throw Failure{"unsupported", std::string(kRefused), nullptr};
    }
    return answer;
}

// Fails the call where the project lacks the shortcut or the settings of the system turn the notifications off, and lets it try while Windows tells nothing.
WindowsNotifications::ToastNotifier WindowsNotifications::ready() {
    if (const std::optional<Json> absent = missing()) {
        throw Failure{"unsupported", std::string(kNoShortcut), {{"missing", *absent}}};
    }

    const ToastNotifier notifier = ToastNotificationManager::CreateToastNotifier(identifier);
    const std::string answer = state(notifier);
    if (answer == "unsupported") {
        throw Failure{"unsupported", std::string(kRefused), nullptr};
    }
    if (answer == "denied") {
        throw Failure{"denied", "The person has not allowed notifications. Ask for it with \"notifications.requestPermission('notifications')\", which shows the prompt of the system while the system still asks, or the person allows it in the settings of the system.", nullptr};
    }
    return notifier;
}

// Schedules the toast with the JSON of the notification as its launch arguments, which the lists and the taps read back, and replaces a notification of the same id. The date keeps whole milliseconds.
WindowsNotifications::Json WindowsNotifications::schedule(const ToastNotifier& notifier, const Json& params) {
    const std::string id = text(params, "id");
    if (winrt::to_hstring(id).size() > 64) {
        throw Failure{"invalidParams", "Windows takes ids of notifications of at most 64 characters, and \"" + id + "\" is longer.", nullptr};
    }

    const auto seconds = params.find("seconds");
    const auto date = params.find("date");
    double when = 0;
    if (seconds != params.end() && seconds->is_number()) {
        when = now() + seconds->get<double>();
    } else if (date != params.end() && date->is_number()) {
        when = date->get<double>();
    } else {
        throw Failure{"invalidParams", "The notification \"" + id + "\" needs either \"seconds\" or \"date\".", nullptr};
    }
    when = std::round(when * 1000) / 1000;

    const std::string title = text(params, "title");
    const auto body = params.find("body");
    const std::string bodyText = body != params.end() && body->is_string() ? body->get<std::string>() : "";
    const auto data = params.find("data");
    const auto sound = params.find("sound");
    const bool silent = sound != params.end() && sound->is_boolean() && !sound->get<bool>();
    const Json launch = {{"id", id}, {"title", title}, {"body", bodyText}, {"date", when}, {"data", data != params.end() ? *data : Json(nullptr)}};

    std::wstring xml = L"<toast launch=\"" + escapeXml(write(launch)) + L"\"><visual><binding template=\"ToastGeneric\"><text>" + escapeXml(title) + L"</text>";
    if (!bodyText.empty()) {
        xml += L"<text>" + escapeXml(bodyText) + L"</text>";
    }
    xml += L"</binding></visual>";
    if (silent) {
        xml += L"<audio silent=\"true\"/>";
    }
    xml += L"</toast>";
    XmlDocument content;
    content.LoadXml(xml);

    cancel(notifier, id);
    const auto delivery = std::chrono::system_clock::time_point(std::chrono::duration_cast<std::chrono::system_clock::duration>(std::chrono::duration<double>(when)));
    ScheduledToastNotification toast(content, winrt::clock::from_sys(delivery));
    toast.Tag(winrt::to_hstring(id));
    toast.Group(kGroup);
    notifier.AddToSchedule(toast);
    return {{"id", id}, {"date", when}};
}

void WindowsNotifications::cancel(const ToastNotifier& notifier, const std::string& id) {
    const winrt::hstring tag = winrt::to_hstring(id);
    for (const ScheduledToastNotification& toast : notifier.GetScheduledToastNotifications()) {
        if (toast.Tag() == tag && toast.Group() == kGroup) {
            notifier.RemoveFromSchedule(toast);
        }
    }
    ToastNotificationManager::History().Remove(tag, kGroup, identifier);
}

void WindowsNotifications::cancelAll(const ToastNotifier& notifier) {
    for (const ScheduledToastNotification& toast : notifier.GetScheduledToastNotifications()) {
        if (toast.Group() == kGroup) {
            notifier.RemoveFromSchedule(toast);
        }
    }
    ToastNotificationManager::History().RemoveGroup(kGroup, identifier);
}

WindowsNotifications::Json WindowsNotifications::pending(const ToastNotifier& notifier) {
    std::vector<Json> notifications;
    for (const ScheduledToastNotification& toast : notifier.GetScheduledToastNotifications()) {
        if (toast.Group() == kGroup) {
            notifications.push_back(launchOf(toast.Content()));
        }
    }
    return list(std::move(notifications));
}

WindowsNotifications::Json WindowsNotifications::delivered() {
    std::vector<Json> notifications;
    for (const ToastNotification& toast : ToastNotificationManager::History().GetHistory(identifier)) {
        if (toast.Group() == kGroup) {
            notifications.push_back(launchOf(toast.Content()));
        }
    }
    return list(std::move(notifications));
}
