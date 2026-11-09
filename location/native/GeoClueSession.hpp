#pragma once

#include <chrono>
#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <string_view>

#include <dbus/dbus.h>
#include <nlohmann/json.hpp>

// A client of GeoClue, the location service of Linux, on a private connection to the system bus of D-Bus, which one thread uses alone: the client that the agent of the desktop lets the app start, the places of its updates, and what its signals tell, an agent that took the client away or GeoClue that left the bus.
class GeoClueSession final {
  public:
    using Json = nlohmann::json;

    // Why a client did not start, with the code of the plugin and its sentence. The code `cancelled` tells that the app gave the location up while the client started.
    struct Failure {
        std::string code;
        std::string message;
    };

    // A place of the client: a new one from its last update, or the last one again.
    struct Place {
        Json value;
        bool updated;
    };

    static constexpr std::string_view kMissingService = "GeoClue, the location service of Linux, does not run on this system, so the plugin cannot tell the location there.";
    static constexpr std::string_view kMissingBus = "The system bus of D-Bus does not run, so GeoClue, the location service of Linux, cannot tell the location.";

    GeoClueSession() = default;
    GeoClueSession(const GeoClueSession&) = delete;
    GeoClueSession& operator=(const GeoClueSession&) = delete;
    ~GeoClueSession();

    // Tells why GeoClue cannot serve the app, or nothing when it runs on the system bus or starts there when asked.
    [[nodiscard]] static std::optional<std::string_view> findMissing();

    // Connects to the system bus, makes the client of the app that GeoClue knows by `desktopId` and starts it, which makes the agent of the desktop ask the person. It asks `isWanted` while it waits, and stops once the app no longer wants the location.
    [[nodiscard]] std::optional<Failure> begin(const std::string& desktopId, std::uint32_t distance, const std::function<bool()>& isWanted);
    // Stops the client and closes the connection, after which the session begins again.
    void end();

    [[nodiscard]] bool isOpen() const;
    [[nodiscard]] bool isRevoked() const;
    [[nodiscard]] bool hasVanished() const;
    bool setDistance(std::uint32_t distance);
    // Returns the place of a new update, or the last place where no update came since, or nothing before the first place. A new update whose place GeoClue cannot read gives nothing.
    [[nodiscard]] std::optional<Place> takePlace();
    // Waits a moment for the bus and runs the signals that arrived, and returns false once the connection closed.
    bool dispatch();

  private:
    // How a call that waits for the app ended: with its reply, unanswered within its bound or unsent, or abandoned because the app no longer wants the location.
    enum class Waited { Answered, Unanswered, Abandoned };

    struct ConnectionClose {
        void operator()(DBusConnection* connection) const;
    };
    struct MessageRelease {
        void operator()(DBusMessage* message) const;
    };
    struct PendingRelease {
        void operator()(DBusPendingCall* pending) const;
    };
    using Connection = std::unique_ptr<DBusConnection, ConnectionClose>;
    using Message = std::unique_ptr<DBusMessage, MessageRelease>;
    using Pending = std::unique_ptr<DBusPendingCall, PendingRelease>;

    // An error of D-Bus, which frees what a failed call wrote into it.
    struct BusError {
        DBusError value{};

        BusError();
        BusError(const BusError&) = delete;
        BusError& operator=(const BusError&) = delete;
        ~BusError();

        [[nodiscard]] bool is(const char* name) const;
        [[nodiscard]] std::string describe() const;
    };

    static constexpr const char* kService = "org.freedesktop.GeoClue2";
    static constexpr const char* kManager = "/org/freedesktop/GeoClue2/Manager";
    static constexpr const char* kManagerInterface = "org.freedesktop.GeoClue2.Manager";
    static constexpr const char* kClientInterface = "org.freedesktop.GeoClue2.Client";
    static constexpr const char* kLocationInterface = "org.freedesktop.GeoClue2.Location";
    static constexpr const char* kProperties = "org.freedesktop.DBus.Properties";
    static constexpr std::string_view kMissingAgent = "GeoClue, the location service of Linux, gives the location only through the agent of the desktop that asks the person, and no agent of this session registered within 10 seconds.";
    static constexpr std::string_view kNoLongerWanted = "The app no longer wanted the location.";
    static constexpr int kCallMilliseconds = 5000;
    static constexpr int kDispatchMilliseconds = 100;
    static constexpr std::chrono::seconds kAgentSeconds{10};
    static constexpr std::uint32_t kAccuracyExact = 8;

    [[nodiscard]] static Connection connectSystemBus(BusError& error);
    [[nodiscard]] static Message method(const char* path, const char* interface, const char* member);
    // Sends a method call and waits for its reply a bounded time.
    [[nodiscard]] static Message call(DBusConnection* bus, const Message& message, DBusError* error);
    [[nodiscard]] static double now();
    static DBusHandlerResult filter(DBusConnection* bus, DBusMessage* message, void* user);

    [[nodiscard]] std::optional<Failure> start(const std::string& desktopId, std::uint32_t distance, const std::function<bool()>& isWanted);
    [[nodiscard]] Waited wait(const Message& message, std::chrono::duration<double> bound, const std::function<bool()>& isWanted, Message& reply);
    bool setProperty(const char* path, const char* interface, const char* name, int type, const void* value, DBusError* error);
    // Reads a property of a basic type into `value`, and returns false when the call fails or the property has another type.
    bool getProperty(const char* path, const char* interface, const char* name, int type, void* value, DBusError* error);
    [[nodiscard]] std::optional<Json> readPlace(const std::string& path);
    DBusHandlerResult receive(DBusMessage* message);

    Connection connection;
    std::string client;
    std::string updated;
    std::string delivered;
    std::optional<Json> place;
    bool filtering = false;
    bool revoked = false;
    bool vanished = false;
};
