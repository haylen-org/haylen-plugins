#include "LinuxBluetooth.hpp"

#include <algorithm>
#include <array>
#include <cstddef>
#include <string_view>
#include <thread>
#include <utility>

void LinuxBluetooth::ConnectionRelease::operator()(DBusConnection* connection) const {
    dbus_connection_close(connection);
    dbus_connection_unref(connection);
}

void LinuxBluetooth::MessageRelease::operator()(DBusMessage* message) const {
    dbus_message_unref(message);
}

LinuxBluetooth::BusError::BusError() {
    dbus_error_init(&value);
}

LinuxBluetooth::BusError::~BusError() {
    dbus_error_free(&value);
}

bool LinuxBluetooth::BusError::isSet() const {
    return dbus_error_is_set(&value) != FALSE;
}

bool LinuxBluetooth::BusError::is(const char* name) const {
    return dbus_error_has_name(&value, name) != FALSE;
}

std::string LinuxBluetooth::BusError::text() const {
    return value.message != nullptr ? value.message : value.name;
}

LinuxBluetooth::LinuxBluetooth(const BluetoothBridge& owner) : bridge(owner) {
    connectBus();
}

void LinuxBluetooth::connectBus() {
    dbus_threads_init_default();

    BusError error;
    DBusConnection* connection = dbus_bus_get_private(DBUS_BUS_SYSTEM, &error.value);
    if (connection == nullptr) {
        busFailure = "The system bus is not reachable, so the app reaches no Bluetooth: " + error.text();
        return;
    }
    dbus_connection_set_exit_on_disconnect(connection, FALSE);
    dbus_bus_add_match(connection, kPropertiesMatch, nullptr);
    dbus_bus_add_match(connection, kAddedMatch, nullptr);
    dbus_connection_add_filter(connection, &LinuxBluetooth::filter, this, nullptr);
    bus.reset(connection);

    std::thread(&LinuxBluetooth::loop, this).detach();
}

void LinuxBluetooth::submit(BluetoothRequest request) {
    if (!bus) {
        answerWithoutBus(request);
        return;
    }

    const std::uint64_t call = request.call;
    if (!enqueue(std::move(request))) {
        bridge.fail(call, {"failed", kBusGone});
    }
}

void LinuxBluetooth::answerWithoutBus(const BluetoothRequest& request) const {
    if (request.kind == Kind::StopScan || request.kind == Kind::Disconnect) {
        bridge.succeed(request.call, Json::object());
        return;
    }
    bridge.fail(request.call, {"unsupported", busFailure});
}

void LinuxBluetooth::cancel(std::uint64_t call) {
    if (!bus) {
        return;
    }
    // A cancel that comes after the bus went away has nothing left to stop.
    enqueue(Cancel{call});
}

bool LinuxBluetooth::enqueue(Job job) {
    const std::lock_guard<std::mutex> guard(lock);
    if (busLost) {
        return false;
    }
    queue.push_back(std::move(job));
    return true;
}

std::deque<LinuxBluetooth::Job> LinuxBluetooth::takeAll() {
    const std::lock_guard<std::mutex> guard(lock);
    std::deque<Job> jobs;
    jobs.swap(queue);
    return jobs;
}

void LinuxBluetooth::loop() {
    while (dbus_connection_read_write_dispatch(bus.get(), kPollMilliseconds) != FALSE) {
        for (const Job& job : takeAll()) {
            if (const auto* cancelled = std::get_if<Cancel>(&job)) {
                cancelCall(cancelled->call);
                continue;
            }
            run(std::get<BluetoothRequest>(job));
        }
        checkDeadlines();
    }
    failQueue();
}

// Fails every request that waits once the system bus went away, so no call stays without an answer.
void LinuxBluetooth::failQueue() {
    {
        const std::lock_guard<std::mutex> guard(lock);
        busLost = true;
    }
    for (const Job& job : takeAll()) {
        if (const auto* request = std::get_if<BluetoothRequest>(&job)) {
            bridge.fail(request->call, {"failed", kBusGone});
        }
    }
}

void LinuxBluetooth::run(const BluetoothRequest& request) {
    try {
        switch (request.kind) {
        case Kind::StopScan:
            endScan(true);
            bridge.succeed(request.call, Json::object());
            break;
        case Kind::Disconnect:
            runDisconnect(request);
            break;
        case Kind::Permission:
            runPermission(request);
            break;
        case Kind::Scan:
        case Kind::Connect:
        case Kind::Services:
        case Kind::Characteristics:
        case Kind::Read:
        case Kind::Write:
        case Kind::Subscribe:
        case Kind::Unsubscribe:
            runReady(request);
            break;
        }
    } catch (const BluetoothFailure& failure) {
        bridge.fail(request.call, failure);
    }
}

void LinuxBluetooth::cancelCall(std::uint64_t call) {
    if (scan && scan->call == call) {
        endScan(false);
    }
    const std::optional<Waiter> waiter = takeWaiter(call);
    if (waiter) {
        sendDisconnect(waiter->path);
    }
}

// Runs the requests that need a ready adapter, which is on, with the objects that BlueZ publishes now.
void LinuxBluetooth::runReady(const BluetoothRequest& request) {
    const std::vector<BluezObject> objects = load();
    const BluezObject& adapter = readyAdapter(objects);

    if (request.kind == Kind::Scan) {
        runScan(request, objects, adapter);
        return;
    }
    if (request.kind == Kind::Connect) {
        runConnect(request, objects, adapter);
        return;
    }
    if (request.kind == Kind::Services) {
        runServices(request, objects, adapter);
        return;
    }
    if (request.kind == Kind::Characteristics) {
        runCharacteristics(request, objects, adapter);
        return;
    }

    const BluezObject& characteristic = findCharacteristic(objects, adapter, request);
    if (request.kind == Kind::Read) {
        runRead(request, characteristic);
        return;
    }
    if (request.kind == Kind::Write) {
        runWrite(request, characteristic);
        return;
    }
    runNotify(request, characteristic);
}

// Starts a scan with a discovery filter of Bluetooth Low Energy and the services of the request, and sends the devices that the adapter already sees in a discovery. A scan that runs ends first, so its call gives its answer.
void LinuxBluetooth::runScan(const BluetoothRequest& request, const std::vector<BluezObject>& objects, const BluezObject& adapter) {
    endScan(true);

    try {
        query(filterMessage(adapter.path, request.services));
        query(newCall(adapter.path, BluezObject::kAdapterInterface, "StartDiscovery"));
    } catch (const BluetoothFailure& failure) {
        bridge.fail(request.call, {"scanFailed", "Bluetooth did not start the scan: " + failure.message});
        return;
    }

    const auto duration = std::chrono::duration_cast<Clock::duration>(std::chrono::duration<double>(request.seconds));
    scan = Scan{.call = request.call, .deadline = Clock::now() + duration, .adapter = adapter.path, .services = request.services, .found = {}};
    for (const BluezObject& object : objects) {
        if (object.kind == BluezObject::Kind::Device) {
            consider(object);
        }
    }
}

// A device that is connected and resolved answers at once. Any other device waits for both the reply of `Connect` and its resolved services, within `kConnectBound`.
void LinuxBluetooth::runConnect(const BluetoothRequest& request, const std::vector<BluezObject>& objects, const BluezObject& adapter) {
    const BluezObject& device = findDevice(objects, adapter, request.id);
    const bool ready = device.connected && device.resolved;
    Waiter waiter{
        .call = request.call,
        .path = device.path,
        .id = request.id,
        .name = device.has(BluezObject::kHasName) ? std::optional<std::string>(device.name) : std::nullopt,
        .replied = ready,
        .resolved = ready,
        .deadline = Clock::now() + kConnectBound,
    };
    waiters.push_back(std::move(waiter));

    if (ready) {
        finishConnect(request.call);
        return;
    }
    send(newCall(device.path, BluezObject::kDeviceInterface, "Connect"), Kind::Connect, request.call, device.path, request.id);
}

// A device that is not connected, or a computer without BlueZ or an adapter, answers at once. The app disconnects any other device, which the event `disconnected` tells with the reason that the app disconnected.
void LinuxBluetooth::runDisconnect(const BluetoothRequest& request) {
    std::vector<BluezObject> objects;
    try {
        objects = load();
    } catch (const BluetoothFailure& failure) {
        if (failure.code == "unsupported") {
            bridge.succeed(request.call, Json::object());
            return;
        }
        throw;
    }

    const BluezObject* adapter = firstAdapter(objects);
    if (adapter == nullptr) {
        bridge.succeed(request.call, Json::object());
        return;
    }
    const BluezObject& device = findDevice(objects, *adapter, request.id);
    if (!device.connected) {
        bridge.succeed(request.call, Json::object());
        return;
    }

    disconnecting.insert(device.path);
    send(newCall(device.path, BluezObject::kDeviceInterface, "Disconnect"), Kind::Disconnect, request.call, device.path, request.id);
}

void LinuxBluetooth::runServices(const BluetoothRequest& request, const std::vector<BluezObject>& objects, const BluezObject& adapter) const {
    const BluezObject& device = findConnectedDevice(objects, adapter, request.id);
    Json uuids = Json::array();
    for (const BluezObject& service : objects) {
        if (service.kind == BluezObject::Kind::Service && service.parent == device.path) {
            uuids.push_back(service.uuid);
        }
    }
    bridge.succeed(request.call, uuids);
}

void LinuxBluetooth::runCharacteristics(const BluetoothRequest& request, const std::vector<BluezObject>& objects, const BluezObject& adapter) const {
    const BluezObject& device = findConnectedDevice(objects, adapter, request.id);
    const BluezObject& service = findService(objects, device, request.service);
    Json characteristics = Json::array();
    for (const BluezObject& characteristic : objects) {
        if (characteristic.kind == BluezObject::Kind::Characteristic && characteristic.parent == service.path) {
            characteristics.push_back({{"uuid", characteristic.uuid}, {"properties", propertyNames(characteristic.flags)}});
        }
    }
    bridge.succeed(request.call, characteristics);
}

void LinuxBluetooth::runRead(const BluetoothRequest& request, const BluezObject& characteristic) {
    Message message = newCall(characteristic.path, BluezObject::kCharacteristicInterface, "ReadValue");
    DBusMessageIter arguments;
    dbus_message_iter_init_append(message.get(), &arguments);
    appendEmptyOptions(&arguments);
    send(std::move(message), Kind::Read, request.call, characteristic.path, request.id);
}

// Writes with the type `request`, which the device confirms, or `command`, which it does not.
void LinuxBluetooth::runWrite(const BluetoothRequest& request, const BluezObject& characteristic) {
    Message message = newCall(characteristic.path, BluezObject::kCharacteristicInterface, "WriteValue");
    DBusMessageIter arguments;
    DBusMessageIter bytes;
    DBusMessageIter options;
    const std::uint8_t* data = request.value.data();
    const char* type = request.response ? "request" : "command";
    dbus_message_iter_init_append(message.get(), &arguments);
    dbus_message_iter_open_container(&arguments, DBUS_TYPE_ARRAY, "y", &bytes);
    dbus_message_iter_append_fixed_array(&bytes, DBUS_TYPE_BYTE, &data, static_cast<int>(request.value.size()));
    dbus_message_iter_close_container(&arguments, &bytes);
    dbus_message_iter_open_container(&arguments, DBUS_TYPE_ARRAY, "{sv}", &options);
    appendOption(&options, "type", DBUS_TYPE_STRING, "s", &type);
    dbus_message_iter_close_container(&arguments, &options);
    send(std::move(message), Kind::Write, request.call, characteristic.path, request.id);
}

// The app subscribes once per characteristic. A subscription counts before BlueZ answers, since the first value may come before the reply.
void LinuxBluetooth::runNotify(const BluetoothRequest& request, const BluezObject& characteristic) {
    if ((characteristic.flags & (BluezObject::kNotifies | BluezObject::kIndicates)) == 0) {
        throw BluetoothFailure{"notSupported", "The characteristic \"" + request.characteristic + "\" neither notifies nor indicates."};
    }
    const bool subscribe = request.kind == Kind::Subscribe;
    if (subscriptions.contains(characteristic.path) == subscribe) {
        bridge.succeed(request.call, Json::object());
        return;
    }

    if (subscribe) {
        subscriptions.emplace(characteristic.path, Subscription{.id = request.id, .service = request.service, .characteristic = request.characteristic});
    } else {
        subscriptions.erase(characteristic.path);
    }
    send(newCall(characteristic.path, BluezObject::kCharacteristicInterface, subscribe ? "StartNotify" : "StopNotify"), request.kind, request.call, characteristic.path, request.id);
}

// Answers the permission `bluetooth`. BlueZ shows no prompt, so the app holds the permission while BlueZ runs with an adapter and the policy of the bus lets the app reach it, and a computer without BlueZ or an adapter fails the call with the code `unsupported`.
void LinuxBluetooth::runPermission(const BluetoothRequest& request) const {
    std::vector<BluezObject> objects;
    try {
        objects = load();
    } catch (const BluetoothFailure& failure) {
        if (failure.code == "denied") {
            bridge.succeed(request.call, Json("denied"));
        } else if (failure.code == "unsupported") {
            bridge.fail(request.call, failure);
        } else {
            bridge.succeed(request.call, Json("unknown"));
        }
        return;
    }

    if (firstAdapter(objects) == nullptr) {
        bridge.fail(request.call, {"unsupported", "This computer has no Bluetooth adapter."});
        return;
    }
    bridge.succeed(request.call, Json("granted"));
}

LinuxBluetooth::Message LinuxBluetooth::newCall(const std::string& path, const char* interface, const char* member) {
    return Message(dbus_message_new_method_call(kService, path.c_str(), interface, member));
}

LinuxBluetooth::Message LinuxBluetooth::query(Message message) const {
    BusError error;
    Message reply(dbus_connection_send_with_reply_and_block(bus.get(), message.get(), kQueryMilliseconds, &error.value));
    if (!reply) {
        throw describe(error);
    }
    return reply;
}

void LinuxBluetooth::send(Message message, Kind kind, std::uint64_t call, const std::string& path, const std::string& id) {
    auto pending = std::make_unique<Pending>(Pending{.owner = this, .kind = kind, .call = call, .path = path, .id = id});
    DBusPendingCall* waiting = nullptr;
    if (dbus_connection_send_with_reply(bus.get(), message.get(), &waiting, kOperationMilliseconds) == FALSE || waiting == nullptr) {
        bridge.fail(call, {"failed", "The system bus is gone, so BlueZ cannot be reached."});
        return;
    }
    dbus_pending_call_set_notify(waiting, &LinuxBluetooth::replied, pending.release(), &LinuxBluetooth::releasePending);
}

void LinuxBluetooth::sendDisconnect(const std::string& path) const {
    const Message message = newCall(path, BluezObject::kDeviceInterface, "Disconnect");
    dbus_message_set_no_reply(message.get(), TRUE);
    dbus_connection_send(bus.get(), message.get(), nullptr);
}

// Turns an error of the bus into the failure of a call: BlueZ that does not run, a policy of the bus that refuses the app, or the error of BlueZ.
BluetoothFailure LinuxBluetooth::describe(const BusError& error) {
    if (error.is(DBUS_ERROR_SERVICE_UNKNOWN) || error.is(DBUS_ERROR_NAME_HAS_NO_OWNER)) {
        return {"unsupported", "BlueZ does not run on the system bus, so the app reaches no Bluetooth. The service \"bluetooth\" of the system runs it."};
    }
    if (error.is(DBUS_ERROR_ACCESS_DENIED)) {
        return {"denied", "The policy of the system bus does not let the app use BlueZ. The administrator of the computer allows it, such as with the group \"bluetooth\" on some systems."};
    }
    return {"failed", "BlueZ answered with an error: " + error.text()};
}

// Reads every object of BlueZ through `GetManagedObjects`.
std::vector<BluezObject> LinuxBluetooth::load() const {
    const Message reply = query(newCall("/", kObjectManagerInterface, "GetManagedObjects"));
    std::vector<BluezObject> objects;
    DBusMessageIter arguments;
    DBusMessageIter entry;
    dbus_message_iter_init(reply.get(), &arguments);
    dbus_message_iter_recurse(&arguments, &entry);
    while (dbus_message_iter_get_arg_type(&entry) == DBUS_TYPE_DICT_ENTRY) {
        DBusMessageIter pair;
        const char* path = nullptr;
        dbus_message_iter_recurse(&entry, &pair);
        dbus_message_iter_get_basic(&pair, &path);
        dbus_message_iter_next(&pair);

        BluezObject object;
        object.path = path;
        object.readInterfaces(&pair);
        if (object.kind != BluezObject::Kind::Other) {
            objects.push_back(std::move(object));
        }
        dbus_message_iter_next(&entry);
    }
    return objects;
}

// The adapter of the computer, which must be on.
const BluezObject& LinuxBluetooth::readyAdapter(const std::vector<BluezObject>& objects) const {
    const BluezObject* adapter = firstAdapter(objects);
    if (adapter == nullptr) {
        throw BluetoothFailure{"unsupported", "This computer has no Bluetooth adapter."};
    }
    if (!adapter->powered) {
        throw BluetoothFailure{"poweredOff", "Bluetooth is off. The person turns it on in the settings of the system."};
    }
    return *adapter;
}

const BluezObject* LinuxBluetooth::find(const std::vector<BluezObject>& objects, BluezObject::Kind kind, const std::string& parent, const std::string& key) {
    for (const BluezObject& object : objects) {
        if (object.kind != kind || object.parent != parent) {
            continue;
        }
        const std::string& value = kind == BluezObject::Kind::Device ? object.address : object.uuid;
        if (value == key) {
            return &object;
        }
    }
    return nullptr;
}

// The adapter of the computer, the first that BlueZ lists by path, such as `/org/bluez/hci0`.
const BluezObject* LinuxBluetooth::firstAdapter(const std::vector<BluezObject>& objects) {
    const BluezObject* first = nullptr;
    for (const BluezObject& object : objects) {
        if (object.kind == BluezObject::Kind::Adapter && (first == nullptr || object.path < first->path)) {
            first = &object;
        }
    }
    return first;
}

const BluezObject& LinuxBluetooth::findDevice(const std::vector<BluezObject>& objects, const BluezObject& adapter, const std::string& id) {
    const BluezObject* device = find(objects, BluezObject::Kind::Device, adapter.path, id);
    if (device == nullptr) {
        throw BluetoothFailure{"unknownDevice", "No device has the id \"" + id + "\". Scan for it first."};
    }
    return *device;
}

const BluezObject& LinuxBluetooth::findConnectedDevice(const std::vector<BluezObject>& objects, const BluezObject& adapter, const std::string& id) {
    const BluezObject& device = findDevice(objects, adapter, id);
    if (!device.connected) {
        throw BluetoothFailure{"notConnected", "The device \"" + id + "\" is not connected. Connect to it first."};
    }
    return device;
}

const BluezObject& LinuxBluetooth::findService(const std::vector<BluezObject>& objects, const BluezObject& device, const std::string& uuid) {
    const BluezObject* service = find(objects, BluezObject::Kind::Service, device.path, uuid);
    if (service == nullptr) {
        throw BluetoothFailure{"unknownService", "The device has no service \"" + uuid + "\"."};
    }
    return *service;
}

// Finds the characteristic that a request names on a connected device.
const BluezObject& LinuxBluetooth::findCharacteristic(const std::vector<BluezObject>& objects, const BluezObject& adapter, const BluetoothRequest& request) {
    const BluezObject& device = findConnectedDevice(objects, adapter, request.id);
    const BluezObject& service = findService(objects, device, request.service);
    const BluezObject* characteristic = find(objects, BluezObject::Kind::Characteristic, service.path, request.characteristic);
    if (characteristic == nullptr) {
        throw BluetoothFailure{"unknownCharacteristic", "The service \"" + request.service + "\" has no characteristic \"" + request.characteristic + "\"."};
    }
    return *characteristic;
}

LinuxBluetooth::Json LinuxBluetooth::propertyNames(unsigned flags) {
    static const std::array<std::pair<unsigned, std::string_view>, 5> kNames{{
        {BluezObject::kReads, "read"},
        {BluezObject::kWrites, "write"},
        {BluezObject::kWritesWithoutResponse, "writeWithoutResponse"},
        {BluezObject::kNotifies, "notify"},
        {BluezObject::kIndicates, "indicate"},
    }};
    Json names = Json::array();
    for (const auto& [flag, name] : kNames) {
        if ((flags & flag) != 0) {
            names.push_back(name);
        }
    }
    return names;
}

// Whether a path names a device, whose last part is `dev_` and the address with underscores, such as `/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF`.
bool LinuxBluetooth::isDevicePath(const std::string& path) {
    const std::size_t last = path.rfind('/');
    return last != std::string::npos && std::string_view(path).substr(last + 1).starts_with("dev_");
}

// Writes an entry of a dictionary of names and variants with a basic value.
void LinuxBluetooth::appendOption(DBusMessageIter* dictionary, const char* key, int type, const char* signature, const void* value) {
    DBusMessageIter entry;
    DBusMessageIter variant;
    dbus_message_iter_open_container(dictionary, DBUS_TYPE_DICT_ENTRY, nullptr, &entry);
    dbus_message_iter_append_basic(&entry, DBUS_TYPE_STRING, &key);
    dbus_message_iter_open_container(&entry, DBUS_TYPE_VARIANT, signature, &variant);
    dbus_message_iter_append_basic(&variant, type, value);
    dbus_message_iter_close_container(&entry, &variant);
    dbus_message_iter_close_container(dictionary, &entry);
}

void LinuxBluetooth::appendEmptyOptions(DBusMessageIter* arguments) {
    DBusMessageIter options;
    dbus_message_iter_open_container(arguments, DBUS_TYPE_ARRAY, "{sv}", &options);
    dbus_message_iter_close_container(arguments, &options);
}

LinuxBluetooth::Message LinuxBluetooth::filterMessage(const std::string& adapter, const std::vector<std::string>& services) {
    Message message = newCall(adapter, BluezObject::kAdapterInterface, "SetDiscoveryFilter");
    DBusMessageIter arguments;
    DBusMessageIter options;
    const char* transport = "le";
    const dbus_bool_t duplicates = FALSE;
    dbus_message_iter_init_append(message.get(), &arguments);
    dbus_message_iter_open_container(&arguments, DBUS_TYPE_ARRAY, "{sv}", &options);
    appendOption(&options, "Transport", DBUS_TYPE_STRING, "s", &transport);
    appendOption(&options, "DuplicateData", DBUS_TYPE_BOOLEAN, "b", &duplicates);

    if (!services.empty()) {
        DBusMessageIter entry;
        DBusMessageIter variant;
        DBusMessageIter list;
        const char* key = "UUIDs";
        dbus_message_iter_open_container(&options, DBUS_TYPE_DICT_ENTRY, nullptr, &entry);
        dbus_message_iter_append_basic(&entry, DBUS_TYPE_STRING, &key);
        dbus_message_iter_open_container(&entry, DBUS_TYPE_VARIANT, "as", &variant);
        dbus_message_iter_open_container(&variant, DBUS_TYPE_ARRAY, "s", &list);
        for (const std::string& service : services) {
            const char* uuid = service.c_str();
            dbus_message_iter_append_basic(&list, DBUS_TYPE_STRING, &uuid);
        }
        dbus_message_iter_close_container(&variant, &list);
        dbus_message_iter_close_container(&entry, &variant);
        dbus_message_iter_close_container(&options, &entry);
    }
    dbus_message_iter_close_container(&arguments, &options);
    return message;
}

// Sends a device that the scan sees as the batched event `found`, once per scan, when it belongs to the adapter of the scan, was seen during it and advertises one of the services of the scan.
void LinuxBluetooth::consider(const BluezObject& device) {
    if (!scan || device.parent != scan->adapter || !device.has(BluezObject::kHasRssi) || device.address.empty()) {
        return;
    }
    if (scan->found.contains(device.path)) {
        return;
    }

    bool matches = scan->services.empty();
    for (const std::string& wanted : scan->services) {
        if (std::ranges::find(device.uuids, wanted) != device.uuids.end()) {
            matches = true;
        }
    }
    if (!matches) {
        return;
    }

    scan->found.insert(device.path);
    const Json name = device.has(BluezObject::kHasName) ? Json(device.name) : Json(nullptr);
    const Json maker = device.maker.empty() ? Json(nullptr) : Json{{"$bytes", 0}};
    const Json payload = {{"id", device.address}, {"name", name}, {"rssi", device.rssi}, {"services", device.uuids}, {"manufacturerData", maker}};
    if (device.maker.empty()) {
        bridge.emit("bluetooth.found", payload, HAYLEN_NATIVE_EMIT_BATCHED);
        return;
    }
    bridge.emitWithBytes("bluetooth.found", payload, device.maker, HAYLEN_NATIVE_EMIT_BATCHED);
}

// Ends the scan that runs, and answers its call with `{}` unless the app gave the call up.
void LinuxBluetooth::endScan(bool answering) {
    if (!scan) {
        return;
    }
    const Scan ended = std::move(*scan);
    scan.reset();

    try {
        query(newCall(ended.adapter, BluezObject::kAdapterInterface, "StopDiscovery"));
    } catch (const BluetoothFailure& failure) {
        bridge.log(HAYLEN_NATIVE_LOG_WARNING, "The scan of Bluetooth did not stop cleanly: " + failure.message);
    }
    if (answering) {
        bridge.succeed(ended.call, Json::object());
    }
}

LinuxBluetooth::Waiter* LinuxBluetooth::findWaiter(std::uint64_t call) {
    const auto found = std::ranges::find(waiters, call, &Waiter::call);
    return found != waiters.end() ? &*found : nullptr;
}

std::optional<LinuxBluetooth::Waiter> LinuxBluetooth::takeWaiter(std::uint64_t call) {
    const auto found = std::ranges::find(waiters, call, &Waiter::call);
    if (found == waiters.end()) {
        return std::nullopt;
    }
    Waiter waiter = std::move(*found);
    waiters.erase(found);
    return waiter;
}

// The calls of the connections that wait on a device, so the caller can end them while the list changes.
std::vector<std::uint64_t> LinuxBluetooth::waitersOf(const std::string& path, bool repliedOnly) const {
    std::vector<std::uint64_t> calls;
    for (const Waiter& waiter : waiters) {
        if (waiter.path == path && (waiter.replied || !repliedOnly)) {
            calls.push_back(waiter.call);
        }
    }
    return calls;
}

// Answers a connection once BlueZ answered `Connect` and resolved the services of the device, and remembers the device as connected by the app.
void LinuxBluetooth::finishConnect(std::uint64_t call) {
    const Waiter* waiting = findWaiter(call);
    if (waiting == nullptr || !waiting->replied || !waiting->resolved) {
        return;
    }
    const Waiter waiter = *takeWaiter(call);
    connected.try_emplace(waiter.path, waiter.id);

    const Json name = waiter.name ? Json(*waiter.name) : Json(nullptr);
    bridge.succeed(call, {{"id", waiter.id}, {"name", name}});
}

void LinuxBluetooth::failConnect(std::uint64_t call, const std::string& reason) {
    if (!takeWaiter(call)) {
        return;
    }
    bridge.fail(call, {"connectFailed", "The device did not connect: " + reason});
}

// Reads whether BlueZ resolved the services of a device whose `Connect` returned, since the change may have come before.
void LinuxBluetooth::checkResolved(Waiter& waiter) const {
    Message message = newCall(waiter.path, kPropertiesInterface, "Get");
    const char* interface = BluezObject::kDeviceInterface;
    const char* property = "ServicesResolved";
    dbus_message_append_args(message.get(), DBUS_TYPE_STRING, &interface, DBUS_TYPE_STRING, &property, DBUS_TYPE_INVALID);

    Message reply;
    try {
        reply = query(std::move(message));
    } catch (const BluetoothFailure&) {
        return;
    }
    DBusMessageIter arguments;
    DBusMessageIter value;
    dbus_message_iter_init(reply.get(), &arguments);
    dbus_message_iter_recurse(&arguments, &value);
    waiter.resolved = BluezObject::readBool(&value);
}

// Answers the call of an operation once BlueZ replied, on the thread of the bus.
void LinuxBluetooth::replied(DBusPendingCall* waiting, void* user) {
    const auto& pending = *static_cast<const Pending*>(user);
    const Message reply(dbus_pending_call_steal_reply(waiting));
    BusError error;
    if (!reply) {
        dbus_set_error_const(&error.value, DBUS_ERROR_NO_REPLY, "BlueZ gave no reply.");
    } else {
        dbus_set_error_from_message(&error.value, reply.get());
    }

    pending.owner->answer(pending, reply.get(), error);
    dbus_pending_call_unref(waiting);
}

void LinuxBluetooth::releasePending(void* user) {
    delete static_cast<Pending*>(user);
}

void LinuxBluetooth::answer(const Pending& pending, DBusMessage* reply, const BusError& error) {
    if (pending.kind == Kind::Connect) {
        answerConnect(pending, error);
        return;
    }

    if (error.isSet()) {
        if (pending.kind == Kind::Subscribe) {
            subscriptions.erase(pending.path);
        }
        if (error.is("org.bluez.Error.NotConnected")) {
            bridge.fail(pending.call, {"notConnected", "The device \"" + pending.id + "\" is not connected. Connect to it first."});
            return;
        }
        bridge.fail(pending.call, {"failed", "The device answered with an error: " + error.text()});
        return;
    }

    if (pending.kind == Kind::Read) {
        answerRead(pending.call, reply);
        return;
    }
    bridge.succeed(pending.call, Json::object());
}

void LinuxBluetooth::answerConnect(const Pending& pending, const BusError& error) {
    Waiter* waiter = findWaiter(pending.call);
    if (waiter == nullptr) {
        return;
    }
    if (error.isSet() && !error.is("org.bluez.Error.AlreadyConnected")) {
        failConnect(pending.call, error.text());
        return;
    }

    waiter->replied = true;
    if (!waiter->resolved) {
        checkResolved(*waiter);
    }
    finishConnect(pending.call);
}

void LinuxBluetooth::answerRead(std::uint64_t call, DBusMessage* reply) const {
    DBusMessageIter arguments;
    DBusMessageIter bytes;
    dbus_message_iter_init(reply, &arguments);
    if (dbus_message_iter_get_arg_type(&arguments) != DBUS_TYPE_ARRAY || dbus_message_iter_get_element_type(&arguments) != DBUS_TYPE_BYTE) {
        bridge.fail(call, {"failed", "BlueZ answered the read without bytes."});
        return;
    }

    const std::uint8_t* data = nullptr;
    int length = 0;
    dbus_message_iter_recurse(&arguments, &bytes);
    dbus_message_iter_get_fixed_array(&bytes, &data, &length);
    bridge.succeedWithBytes(call, {{"value", {{"$bytes", 0}}}}, std::span(data, static_cast<std::size_t>(length)));
}

DBusHandlerResult LinuxBluetooth::filter(DBusConnection*, DBusMessage* message, void* user) {
    return static_cast<LinuxBluetooth*>(user)->route(message);
}

// Follows the objects of BlueZ: devices that a scan finds, connections that resolve or end, the adapter that turns off and the values of subscribed characteristics.
DBusHandlerResult LinuxBluetooth::route(DBusMessage* message) {
    DBusMessageIter arguments;
    const char* path = dbus_message_get_path(message);
    if (path == nullptr || dbus_message_iter_init(message, &arguments) == FALSE) {
        return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
    }

    if (dbus_message_is_signal(message, kObjectManagerInterface, "InterfacesAdded") != FALSE) {
        if (!scan || dbus_message_iter_get_arg_type(&arguments) != DBUS_TYPE_OBJECT_PATH) {
            return DBUS_HANDLER_RESULT_HANDLED;
        }
        const char* added = nullptr;
        dbus_message_iter_get_basic(&arguments, &added);
        dbus_message_iter_next(&arguments);
        BluezObject object;
        object.path = added;
        object.readInterfaces(&arguments);
        if (object.kind == BluezObject::Kind::Device) {
            consider(object);
        }
        return DBUS_HANDLER_RESULT_HANDLED;
    }

    if (dbus_message_is_signal(message, kPropertiesInterface, "PropertiesChanged") == FALSE || dbus_message_iter_get_arg_type(&arguments) != DBUS_TYPE_STRING) {
        return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
    }
    const char* interface = nullptr;
    dbus_message_iter_get_basic(&arguments, &interface);
    dbus_message_iter_next(&arguments);
    if (dbus_message_iter_get_arg_type(&arguments) != DBUS_TYPE_ARRAY) {
        return DBUS_HANDLER_RESULT_HANDLED;
    }

    const std::string changed(path);
    const std::string_view name(interface);
    if (name == BluezObject::kDeviceInterface && isDevicePath(changed)) {
        deviceChanged(changed, &arguments);
        return DBUS_HANDLER_RESULT_HANDLED;
    }
    if (name == BluezObject::kCharacteristicInterface) {
        valueChanged(changed, &arguments);
        return DBUS_HANDLER_RESULT_HANDLED;
    }
    if (name == BluezObject::kAdapterInterface && scan && changed == scan->adapter) {
        BluezObject change;
        change.readProperties(&arguments);
        if (change.has(BluezObject::kHasPowered) && !change.powered) {
            endScan(true);
        }
    }
    return DBUS_HANDLER_RESULT_HANDLED;
}

void LinuxBluetooth::deviceChanged(const std::string& path, DBusMessageIter* changes) {
    BluezObject change;
    change.readProperties(changes);

    if (change.has(BluezObject::kHasResolved) && change.resolved) {
        for (const std::uint64_t call : waitersOf(path, false)) {
            findWaiter(call)->resolved = true;
            finishConnect(call);
        }
    }
    if (change.has(BluezObject::kHasConnected) && !change.connected) {
        ended(path);
    }
    if (scan && change.has(BluezObject::kHasRssi | BluezObject::kHasName | BluezObject::kHasAdvertisement)) {
        seen(path);
    }
}

// Sends a new value of a characteristic that the app subscribed to as the batched event `changed`.
void LinuxBluetooth::valueChanged(const std::string& path, DBusMessageIter* changes) const {
    const auto subscription = subscriptions.find(path);
    if (subscription == subscriptions.end()) {
        return;
    }

    DBusMessageIter entry;
    dbus_message_iter_recurse(changes, &entry);
    while (dbus_message_iter_get_arg_type(&entry) == DBUS_TYPE_DICT_ENTRY) {
        DBusMessageIter pair;
        DBusMessageIter value;
        const char* key = nullptr;
        dbus_message_iter_recurse(&entry, &pair);
        dbus_message_iter_get_basic(&pair, &key);
        dbus_message_iter_next(&pair);
        dbus_message_iter_recurse(&pair, &value);

        const bool bytes = dbus_message_iter_get_arg_type(&value) == DBUS_TYPE_ARRAY && dbus_message_iter_get_element_type(&value) == DBUS_TYPE_BYTE;
        if (std::string_view(key) == "Value" && bytes) {
            DBusMessageIter items;
            const std::uint8_t* data = nullptr;
            int length = 0;
            dbus_message_iter_recurse(&value, &items);
            dbus_message_iter_get_fixed_array(&items, &data, &length);

            const Subscription& subscribed = subscription->second;
            const Json payload = {{"id", subscribed.id}, {"service", subscribed.service}, {"characteristic", subscribed.characteristic}, {"value", {{"$bytes", 0}}}};
            bridge.emitWithBytes("bluetooth.changed", payload, std::span(data, static_cast<std::size_t>(length)), HAYLEN_NATIVE_EMIT_BATCHED);
        }
        dbus_message_iter_next(&entry);
    }
}

// Reads every property of a device that changed during a scan and considers it for the scan.
void LinuxBluetooth::seen(const std::string& path) {
    if (scan->found.contains(path)) {
        return;
    }
    Message message = newCall(path, kPropertiesInterface, "GetAll");
    const char* interface = BluezObject::kDeviceInterface;
    dbus_message_append_args(message.get(), DBUS_TYPE_STRING, &interface, DBUS_TYPE_INVALID);

    Message reply;
    try {
        reply = query(std::move(message));
    } catch (const BluetoothFailure&) {
        return;
    }
    BluezObject device;
    device.kind = BluezObject::Kind::Device;
    device.path = path;
    DBusMessageIter arguments;
    dbus_message_iter_init(reply.get(), &arguments);
    device.readProperties(&arguments);
    consider(device);
}

// Ends what waits on a device whose connection ended: connections that BlueZ already answered fail, the subscriptions of the device end, and a device that the app connected sends `disconnected`.
void LinuxBluetooth::ended(const std::string& path) {
    for (const std::uint64_t call : waitersOf(path, true)) {
        failConnect(call, "it disconnected before BlueZ resolved its services.");
    }

    const std::string children = path + "/";
    std::erase_if(subscriptions, [&children](const auto& entry) { return entry.first.starts_with(children); });

    const bool leaving = disconnecting.erase(path) > 0;
    const auto found = connected.find(path);
    if (found == connected.end()) {
        return;
    }
    const std::string reason = leaving ? "The app disconnected." : "The device ended the connection, went out of range or Bluetooth turned off.";
    const Json payload = {{"id", found->second}, {"reason", reason}};
    connected.erase(found);
    bridge.emit("bluetooth.disconnected", payload, 0);
}

// Ends the scan whose seconds passed and fails the connections whose bound passed, which also stops their attempts.
void LinuxBluetooth::checkDeadlines() {
    const Clock::time_point now = Clock::now();
    if (scan && now >= scan->deadline) {
        endScan(true);
    }

    std::vector<Waiter> expired;
    for (const Waiter& waiter : waiters) {
        if (now >= waiter.deadline) {
            expired.push_back(waiter);
        }
    }
    for (const Waiter& waiter : expired) {
        sendDisconnect(waiter.path);
        failConnect(waiter.call, "it did not answer within 30 seconds.");
    }
}
