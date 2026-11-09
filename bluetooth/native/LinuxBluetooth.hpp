#pragma once

#include <chrono>
#include <cstdint>
#include <deque>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <span>
#include <string>
#include <variant>
#include <vector>

#include <dbus/dbus.h>
#include <nlohmann/json.hpp>

#include "BluetoothBridge.hpp"
#include "BluetoothFailure.hpp"
#include "BluetoothRequest.hpp"
#include "BluezObject.hpp"

// The central of Bluetooth Low Energy on Linux, through BlueZ, the Bluetooth service of Linux, on the system bus: the adapter `org.bluez.Adapter1` scans with a discovery filter, `org.bluez.Device1` connects, and the objects `org.bluez.GattService1` and `org.bluez.GattCharacteristic1` that BlueZ publishes under a connected device read, write and notify. One thread of the library owns a connection of its own to the system bus and does all the work with it, so the frame thread never waits for BlueZ: the handlers queue their requests for it, and it answers the calls once BlueZ replied. The thread lives as long as the process and ends when the system bus goes away.
class LinuxBluetooth final {
  public:
    // Connects to the system bus and starts the thread of the bus. A failure keeps the reason, which every call then answers.
    explicit LinuxBluetooth(const BluetoothBridge& owner);

    // Answers what needs no bus at once when the library has no system bus, and queues every other request for the thread of the bus. It runs on the frame thread.
    void submit(BluetoothRequest request);

    // Stops the scan or the attempt of a connection whose call the app gave up, with a cancel or the timeout of the call.
    void cancel(std::uint64_t call);

  private:
    using Json = nlohmann::json;
    using Kind = BluetoothRequest::Kind;
    using Clock = std::chrono::steady_clock;

    struct ConnectionRelease {
        void operator()(DBusConnection* connection) const;
    };

    struct MessageRelease {
        void operator()(DBusMessage* message) const;
    };

    using Connection = std::unique_ptr<DBusConnection, ConnectionRelease>;
    using Message = std::unique_ptr<DBusMessage, MessageRelease>;

    // An error of the bus that frees itself.
    class BusError final {
      public:
        BusError();
        ~BusError();
        BusError(const BusError&) = delete;
        BusError& operator=(const BusError&) = delete;

        [[nodiscard]] bool isSet() const;
        [[nodiscard]] bool is(const char* name) const;
        // The message of the error, or its name without one.
        [[nodiscard]] std::string text() const;

        DBusError value;
    };

    // A call that the app gave up.
    struct Cancel {
        std::uint64_t call;
    };

    using Job = std::variant<BluetoothRequest, Cancel>;

    // A connection that waits for BlueZ to answer `Connect` and to resolve the services of the device.
    struct Waiter {
        std::uint64_t call;
        std::string path;
        std::string id;
        std::optional<std::string> name;
        bool replied = false;
        bool resolved = false;
        Clock::time_point deadline;
    };

    // A characteristic that the app subscribed to.
    struct Subscription {
        std::string id;
        std::string service;
        std::string characteristic;
    };

    // A call that waits for the reply of BlueZ to one operation, which the bus owns until it replied.
    struct Pending {
        LinuxBluetooth* owner;
        Kind kind;
        std::uint64_t call;
        std::string path;
        std::string id;
    };

    // The scan that runs, with the services that it looks for and the devices that it found.
    struct Scan {
        std::uint64_t call;
        Clock::time_point deadline;
        std::string adapter;
        std::vector<std::string> services;
        std::set<std::string> found;
    };

    static constexpr const char* kService = "org.bluez";
    static constexpr const char* kPropertiesInterface = "org.freedesktop.DBus.Properties";
    static constexpr const char* kObjectManagerInterface = "org.freedesktop.DBus.ObjectManager";
    static constexpr const char* kPropertiesMatch = "type='signal',sender='org.bluez',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged'";
    static constexpr const char* kAddedMatch = "type='signal',sender='org.bluez',interface='org.freedesktop.DBus.ObjectManager',member='InterfacesAdded'";

    // The milliseconds that the thread of the bus waits for a message before it looks at its queue and its deadlines again.
    static constexpr int kPollMilliseconds = 50;

    // The milliseconds that a query of the objects or of a property may take, and that an operation on a device may take.
    static constexpr int kQueryMilliseconds = 5000;
    static constexpr int kOperationMilliseconds = 30000;

    // The time that a connection may take until BlueZ resolved the services of the device.
    static constexpr std::chrono::seconds kConnectBound{30};

    static constexpr const char* kBusGone = "The system bus went away, so BlueZ cannot be reached.";

    void connectBus();
    void answerWithoutBus(const BluetoothRequest& request) const;
    bool enqueue(Job job);
    [[nodiscard]] std::deque<Job> takeAll();
    void loop();
    void failQueue();

    void run(const BluetoothRequest& request);
    void runReady(const BluetoothRequest& request);
    void runScan(const BluetoothRequest& request, const std::vector<BluezObject>& objects, const BluezObject& adapter);
    void runConnect(const BluetoothRequest& request, const std::vector<BluezObject>& objects, const BluezObject& adapter);
    void runDisconnect(const BluetoothRequest& request);
    void runServices(const BluetoothRequest& request, const std::vector<BluezObject>& objects, const BluezObject& adapter) const;
    void runCharacteristics(const BluetoothRequest& request, const std::vector<BluezObject>& objects, const BluezObject& adapter) const;
    void runRead(const BluetoothRequest& request, const BluezObject& characteristic);
    void runWrite(const BluetoothRequest& request, const BluezObject& characteristic);
    void runNotify(const BluetoothRequest& request, const BluezObject& characteristic);
    void runPermission(const BluetoothRequest& request) const;
    void cancelCall(std::uint64_t call);

    [[nodiscard]] static Message newCall(const std::string& path, const char* interface, const char* member);
    // Sends a query to BlueZ and waits for its reply within `kQueryMilliseconds`, or throws the failure.
    Message query(Message message) const;
    // Sends an operation to BlueZ whose reply answers the call, within `kOperationMilliseconds`.
    void send(Message message, Kind kind, std::uint64_t call, const std::string& path, const std::string& id);
    void sendDisconnect(const std::string& path) const;
    [[nodiscard]] static BluetoothFailure describe(const BusError& error);

    [[nodiscard]] std::vector<BluezObject> load() const;
    [[nodiscard]] const BluezObject& readyAdapter(const std::vector<BluezObject>& objects) const;
    [[nodiscard]] static const BluezObject* find(const std::vector<BluezObject>& objects, BluezObject::Kind kind, const std::string& parent, const std::string& key);
    [[nodiscard]] static const BluezObject* firstAdapter(const std::vector<BluezObject>& objects);
    [[nodiscard]] static const BluezObject& findDevice(const std::vector<BluezObject>& objects, const BluezObject& adapter, const std::string& id);
    [[nodiscard]] static const BluezObject& findConnectedDevice(const std::vector<BluezObject>& objects, const BluezObject& adapter, const std::string& id);
    [[nodiscard]] static const BluezObject& findService(const std::vector<BluezObject>& objects, const BluezObject& device, const std::string& uuid);
    [[nodiscard]] static const BluezObject& findCharacteristic(const std::vector<BluezObject>& objects, const BluezObject& adapter, const BluetoothRequest& request);
    [[nodiscard]] static Json propertyNames(unsigned flags);
    [[nodiscard]] static bool isDevicePath(const std::string& path);

    static void appendOption(DBusMessageIter* dictionary, const char* key, int type, const char* signature, const void* value);
    static void appendEmptyOptions(DBusMessageIter* arguments);
    [[nodiscard]] static Message filterMessage(const std::string& adapter, const std::vector<std::string>& services);

    void consider(const BluezObject& device);
    void endScan(bool answering);

    [[nodiscard]] Waiter* findWaiter(std::uint64_t call);
    std::optional<Waiter> takeWaiter(std::uint64_t call);
    [[nodiscard]] std::vector<std::uint64_t> waitersOf(const std::string& path, bool repliedOnly) const;
    void finishConnect(std::uint64_t call);
    void failConnect(std::uint64_t call, const std::string& reason);
    void checkResolved(Waiter& waiter) const;

    static void replied(DBusPendingCall* waiting, void* user);
    static void releasePending(void* user);
    void answer(const Pending& pending, DBusMessage* reply, const BusError& error);
    void answerConnect(const Pending& pending, const BusError& error);
    void answerRead(std::uint64_t call, DBusMessage* reply) const;

    static DBusHandlerResult filter(DBusConnection* connection, DBusMessage* message, void* user);
    DBusHandlerResult route(DBusMessage* message);
    void deviceChanged(const std::string& path, DBusMessageIter* changes);
    void valueChanged(const std::string& path, DBusMessageIter* changes) const;
    void seen(const std::string& path);
    void ended(const std::string& path);
    void checkDeadlines();

    const BluetoothBridge& bridge;
    Connection bus;
    std::string busFailure;

    std::mutex lock;
    std::deque<Job> queue;
    bool busLost = false;

    // The state that only the thread of the bus touches.
    std::vector<Waiter> waiters;
    std::map<std::string, std::string> connected;
    std::set<std::string> disconnecting;
    std::map<std::string, Subscription> subscriptions;
    std::optional<Scan> scan;
};
