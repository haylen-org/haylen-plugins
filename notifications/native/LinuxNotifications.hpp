#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <string_view>
#include <vector>

#include <dbus/dbus.h>
#include <nlohmann/json.hpp>

#include "haylen/platform/native/HaylenNative.h"

// The desktop part of the Notifications plugin on Linux, which shows notifications through the notification server of the session bus, `org.freedesktop.Notifications`, and sends the taps and the closes of the person as the events `notifications.activated` and `notifications.closed`. The Lua module `notifications.linux` waits for the notifications that the app schedules and calls `notifications.show` when each one is due. One thread of the library does all the work with the bus, so the frame thread never waits for the server: the handlers queue their work for it, and it answers the calls once the server replied.
class LinuxNotifications final {
  public:
    // Creates the library, which lives as long as the process, since its thread of the bus may reach it until the process ends, connects it to the session bus and registers its methods. Returns 1 when the engine hands a native API of another version.
    [[nodiscard]] static int initialize(const HaylenNativeApi* api);

  private:
    using Json = nlohmann::json;
    using Message = std::unique_ptr<DBusMessage, decltype(&dbus_message_unref)>;

    enum class Work { Show, ShowSilent, Close, Permission };

    // The work that a handler hands the thread of the bus, with copies of the texts of the call.
    struct Job {
        LinuxNotifications* owner;
        Work work;
        std::uint64_t call;
        std::string title;
        std::string body;
        std::string appName;
        std::string desktopEntry;
        dbus_uint32_t serverId;
    };

    static constexpr const char* kService = "org.freedesktop.Notifications";
    static constexpr const char* kPath = "/org/freedesktop/Notifications";
    static constexpr const char* kMatch = "type='signal',interface='org.freedesktop.Notifications'";

    // The milliseconds that the thread of the bus waits for a message before it looks at its queue again.
    static constexpr int kPollMilliseconds = 50;

    // The milliseconds that a call to the server may take before it fails.
    static constexpr int kReplyMilliseconds = 5000;

    explicit LinuxNotifications(const HaylenNativeApi& engine);

    static void handleShow(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void handleClose(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void handlePermission(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void replied(DBusPendingCall* pending, void* user);
    static void releaseJob(void* user);
    static DBusHandlerResult filter(DBusConnection* connection, DBusMessage* message, void* user);

    [[nodiscard]] static std::string write(const Json& value);
    [[nodiscard]] static Message notifyMessage(const Job& job);
    [[nodiscard]] static Message messageOf(const Job& job);

    void connect();
    void loop();
    [[nodiscard]] std::unique_ptr<Job> newJob(Work work, std::uint64_t call);
    void enqueue(std::unique_ptr<Job> job);
    void run(std::unique_ptr<Job> job);
    void answer(const Job& job, DBusMessage* reply);
    void succeed(std::uint64_t call, const Json& result) const;
    void fail(std::uint64_t call, std::string_view message, std::string_view code) const;
    void failJob(const Job& job, const std::string& message) const;
    void emit(const char* event, const Json& payload) const;

    const HaylenNativeApi& api;
    DBusConnection* bus = nullptr;
    std::string busFailure;
    std::mutex lock;
    std::vector<std::unique_ptr<Job>> queue;
};
