#include "WindowsBluetooth.hpp"

#include <array>
#include <charconv>
#include <cstring>
#include <format>
#include <string_view>
#include <utility>

#include <winrt/Windows.Devices.Radios.h>
#include <winrt/Windows.Foundation.Collections.h>

#include "BluetoothFailure.hpp"

using winrt::Windows::Devices::Bluetooth::BluetoothAdapter;
using winrt::Windows::Devices::Bluetooth::BluetoothCacheMode;
using winrt::Windows::Devices::Bluetooth::BluetoothConnectionStatus;
using winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisementType;
using winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisementWatcherStoppedEventArgs;
using winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEScanningMode;
using winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattClientCharacteristicConfigurationDescriptorValue;
using winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattValueChangedEventArgs;
using winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattWriteOption;
using winrt::Windows::Devices::Radios::RadioState;
using winrt::Windows::Foundation::IInspectable;
using winrt::Windows::Foundation::IReference;

WindowsBluetooth::WindowsBluetooth(const BluetoothBridge& owner) : bridge(owner) {}

void WindowsBluetooth::submit(BluetoothRequest request) {
    // clang-format off
    worker.post([this, request = std::move(request)] {
        run(request);
    });
    // clang-format on
}

void WindowsBluetooth::cancel(std::uint64_t call) {
    // clang-format off
    worker.post([this, call] {
        giveUp(call);
    });
    // clang-format on
}

// Answers the call with what the request gives, or with its failure, and lets no exception of the Windows Runtime leave the thread.
void WindowsBluetooth::run(const BluetoothRequest& request) {
    try {
        const std::optional<Answer> answer = dispatch(request);
        if (answer) {
            resolve(request.call, *answer);
        }
    } catch (const BluetoothFailure& failure) {
        bridge.fail(request.call, failure);
    } catch (const winrt::hresult_error& error) {
        bridge.fail(request.call, {"failed", "Windows refused the call: " + winrt::to_string(error.message())});
    }
}

// Runs the request, which needs a ready adapter unless it reads the permission, stops a scan or disconnects.
std::optional<WindowsBluetooth::Answer> WindowsBluetooth::dispatch(const BluetoothRequest& request) {
    if (request.kind == Kind::Permission) {
        return permission();
    }
    if (request.kind == Kind::StopScan) {
        endScan();
        return Answer{Json::object(), std::nullopt};
    }
    if (request.kind == Kind::Disconnect) {
        return disconnect(request.id);
    }

    ready();
    if (request.kind == Kind::Scan) {
        return scan(request);
    }
    if (request.kind == Kind::Connect) {
        return connect(request.call, request.id);
    }
    if (request.kind == Kind::Services) {
        return services(request.id);
    }
    if (request.kind == Kind::Characteristics) {
        return characteristics(request.id, request.service);
    }
    if (request.kind == Kind::Read) {
        return read(request);
    }
    if (request.kind == Kind::Write) {
        return write(request);
    }
    return setNotify(request, request.kind == Kind::Subscribe);
}

void WindowsBluetooth::resolve(std::uint64_t call, const Answer& answer) const {
    if (!answer.bytes) {
        bridge.succeed(call, answer.result);
        return;
    }
    bridge.succeedWithBytes(call, answer.result, *answer.bytes);
}

// The permission `bluetooth`, which Windows grants every desktop app on a computer with Bluetooth Low Energy, and a computer without it fails the call with the code `unsupported`.
WindowsBluetooth::Answer WindowsBluetooth::permission() {
    const BluetoothAdapter adapter = BluetoothAdapter::GetDefaultAsync().get();
    if (!adapter) {
        throw BluetoothFailure{"unsupported", "This computer has no Bluetooth adapter."};
    }
    if (!adapter.IsLowEnergySupported()) {
        throw BluetoothFailure{"unsupported", "The Bluetooth adapter of this computer has no Bluetooth Low Energy."};
    }
    return {Json("granted"), std::nullopt};
}

// Fails the call unless the computer has an adapter with Bluetooth Low Energy whose radio is on.
void WindowsBluetooth::ready() {
    const BluetoothAdapter adapter = BluetoothAdapter::GetDefaultAsync().get();
    if (!adapter || !adapter.IsLowEnergySupported()) {
        throw BluetoothFailure{"unsupported", "This computer has no Bluetooth Low Energy."};
    }
    const auto radio = adapter.GetRadioAsync().get();
    if (radio && radio.State() != RadioState::On) {
        throw BluetoothFailure{"poweredOff", "Bluetooth is off. The person turns it on in the settings of the system."};
    }
}

// A scan that runs ends first, so its call gives its answer. The watcher scans actively, so the names that devices give in their scan responses reach the app.
std::optional<WindowsBluetooth::Answer> WindowsBluetooth::scan(const BluetoothRequest& request) {
    endScan();

    Scan& running = scanning.emplace();
    running.call = request.call;
    running.generation = ++scans;
    running.services.insert(request.services.begin(), request.services.end());
    running.watcher = Watcher();
    running.watcher.ScanningMode(BluetoothLEScanningMode::Active);

    const std::uint64_t generation = running.generation;
    // clang-format off
    running.received = running.watcher.Received(winrt::auto_revoke, [this, generation](const Watcher&, const Received& args) {
        worker.post([this, generation, args] { saw(generation, args); });
    });
    running.stopped = running.watcher.Stopped(winrt::auto_revoke, [this, generation](const Watcher&, const BluetoothLEAdvertisementWatcherStoppedEventArgs& args) {
        const BluetoothError error = args.Error();
        worker.post([this, generation, error] { stoppedScan(generation, error); });
    });
    // clang-format on
    running.watcher.Start();

    const auto duration = std::chrono::duration_cast<Clock::duration>(std::chrono::duration<double>(request.seconds));
    // clang-format off
    worker.postAfter(duration, [this, generation] {
        if (scanning && scanning->generation == generation) {
            endScan();
        }
    });
    // clang-format on
    return std::nullopt;
}

// Stops the scan that runs and answers its call with `{}`.
void WindowsBluetooth::endScan() {
    if (!scanning) {
        return;
    }
    const std::uint64_t call = scanning->call;
    dropScan();
    bridge.succeed(call, Json::object());
}

// Stops the watcher without answering, for a scan whose call the app gave up.
void WindowsBluetooth::dropScan() {
    Scan& running = *scanning;
    running.received.revoke();
    running.stopped.revoke();
    running.watcher.Stop();
    scanning.reset();
}

// A watcher that stops by itself ends its scan: one that Bluetooth turning off stops answers `{}`, as on the other platforms, and any other error fails the scan.
void WindowsBluetooth::stoppedScan(std::uint64_t generation, BluetoothError error) {
    if (!scanning || scanning->generation != generation) {
        return;
    }
    if (error == BluetoothError::Success || error == BluetoothError::RadioNotAvailable) {
        endScan();
        return;
    }
    const std::uint64_t call = scanning->call;
    dropScan();
    bridge.fail(call, {"scanFailed", "Windows stopped the scan with the error " + std::to_string(static_cast<int>(error)) + " of \"BluetoothError\"."});
}

// Gathers what the advertisements and scan responses of a device tell, and sends the device once per scan as soon as it matches the services of the scan, waiting a moment for the scan response that names a device whose advertisement has no name.
void WindowsBluetooth::saw(std::uint64_t generation, const Received& args) {
    if (!scanning || scanning->generation != generation) {
        return;
    }
    Scan& running = *scanning;
    const std::uint64_t address = args.BluetoothAddress();
    addressTypes[address] = args.BluetoothAddressType();

    auto [entry, added] = running.sightings.try_emplace(address);
    Sighting& sighting = entry->second;
    if (added) {
        sighting.first = Clock::now();
    }
    if (sighting.sent) {
        return;
    }

    const auto advertisement = args.Advertisement();
    const std::string localName = winrt::to_string(advertisement.LocalName());
    if (!localName.empty()) {
        sighting.name = localName;
    }
    for (const winrt::guid& service : advertisement.ServiceUuids()) {
        sighting.services.insert(formatUuid(service));
    }
    const auto makers = advertisement.ManufacturerData();
    if (!sighting.manufacturerData && makers.Size() > 0) {
        const std::uint16_t company = makers.GetAt(0).CompanyId();
        std::vector<std::uint8_t> data = {static_cast<std::uint8_t>(company & 0xFF), static_cast<std::uint8_t>(company >> 8)};
        const std::vector<std::uint8_t> rest = copyBytes(makers.GetAt(0).Data());
        data.insert(data.end(), rest.begin(), rest.end());
        sighting.manufacturerData = std::move(data);
    }
    sighting.rssi = args.RawSignalStrengthInDBm();
    const BluetoothLEAdvertisementType type = args.AdvertisementType();
    if (type == BluetoothLEAdvertisementType::ScanResponse) {
        sighting.responded = true;
    }

    if (!matches(running, sighting)) {
        return;
    }
    const bool scannable = type == BluetoothLEAdvertisementType::ConnectableUndirected || type == BluetoothLEAdvertisementType::ScannableUndirected;
    if (sighting.name.empty() && !sighting.responded && scannable && Clock::now() - sighting.first < kResponseBound) {
        return;
    }
    sighting.sent = true;
    sendFound(address, sighting);
}

bool WindowsBluetooth::matches(const Scan& running, const Sighting& sighting) {
    if (running.services.empty()) {
        return true;
    }
    for (const std::string& service : sighting.services) {
        if (running.services.contains(service)) {
            return true;
        }
    }
    return false;
}

void WindowsBluetooth::sendFound(std::uint64_t address, const Sighting& sighting) const {
    Json payload = {{"id", formatAddress(address)}, {"rssi", sighting.rssi}, {"services", sighting.services}};
    if (!sighting.name.empty()) {
        payload["name"] = sighting.name;
    }
    if (!sighting.manufacturerData) {
        bridge.emit("bluetooth.found", payload, HAYLEN_NATIVE_EMIT_BATCHED);
        return;
    }
    payload["manufacturerData"] = {{"$bytes", 0}};
    bridge.emitWithBytes("bluetooth.found", payload, *sighting.manufacturerData, HAYLEN_NATIVE_EMIT_BATCHED);
}

// Opens a session that maintains the connection, which Windows makes and keeps while the session lives, and answers once the device connected, within the bound of a connection.
std::optional<WindowsBluetooth::Answer> WindowsBluetooth::connect(std::uint64_t call, const std::string& id) {
    const auto found = devices.find(id);
    if (found != devices.end() && found->second.connected) {
        return connectedAnswer(found->second);
    }
    if (found != devices.end()) {
        found->second.connecting.push_back(call);
        return std::nullopt;
    }

    Connection entry;
    entry.id = id;
    entry.device = openDevice(id);
    entry.attempt = ++attempts;
    entry.connecting.push_back(call);
    // clang-format off
    entry.statusChanges = entry.device.ConnectionStatusChanged(winrt::auto_revoke, [this, id](const Device& device, const IInspectable&) {
        const bool isConnected = device.ConnectionStatus() == BluetoothConnectionStatus::Connected;
        worker.post([this, id, isConnected] { changedStatus(id, isConnected); });
    });
    // clang-format on
    entry.session = Session::FromDeviceIdAsync(entry.device.BluetoothDeviceId()).get();
    entry.session.MaintainConnection(true);

    const std::uint64_t attempt = entry.attempt;
    const bool alreadyConnected = entry.device.ConnectionStatus() == BluetoothConnectionStatus::Connected;
    devices.emplace(id, std::move(entry));
    if (alreadyConnected) {
        changedStatus(id, true);
        return std::nullopt;
    }
    // clang-format off
    worker.postAfter(kConnectBound, [this, id, attempt] {
        const auto waiting = devices.find(id);
        if (waiting == devices.end() || waiting->second.attempt != attempt || waiting->second.connected) {
            return;
        }
        const std::vector<std::uint64_t> calls = waiting->second.connecting;
        close(id);
        for (const std::uint64_t pending : calls) {
            bridge.fail(pending, {"connectFailed", "The device did not connect within 30 seconds."});
        }
    });
    // clang-format on
    return std::nullopt;
}

WindowsBluetooth::Answer WindowsBluetooth::connectedAnswer(const Connection& entry) {
    Json result = {{"id", entry.id}};
    const std::string deviceName = winrt::to_string(entry.device.Name());
    if (!deviceName.empty()) {
        result["name"] = deviceName;
    }
    return {result, std::nullopt};
}

// Opens the device of an id that a scan found, with the type of address that its advertisements gave.
WindowsBluetooth::Device WindowsBluetooth::openDevice(const std::string& id) const {
    const std::optional<std::uint64_t> address = parseAddress(id);
    const BluetoothFailure unknown{"unknownDevice", "No device has the id \"" + id + "\". Scan for it first."};
    if (!address) {
        throw unknown;
    }
    Device device{nullptr};
    const auto type = addressTypes.find(*address);
    if (type == addressTypes.end()) {
        device = Device::FromBluetoothAddressAsync(*address).get();
    } else {
        device = Device::FromBluetoothAddressAsync(*address, type->second).get();
    }
    if (!device) {
        throw unknown;
    }
    return device;
}

// Answers the connections that wait once the device connected, and tells the app when a connected device went away, after which Windows stops trying to connect, as on the other platforms.
void WindowsBluetooth::changedStatus(const std::string& id, bool isConnected) {
    const auto found = devices.find(id);
    if (found == devices.end() || found->second.connected == isConnected) {
        return;
    }
    Connection& entry = found->second;
    if (isConnected) {
        entry.connected = true;
        const Answer answer = connectedAnswer(entry);
        const std::vector<std::uint64_t> calls = std::exchange(entry.connecting, {});
        for (const std::uint64_t call : calls) {
            resolve(call, answer);
        }
        return;
    }
    close(id);
    bridge.emit("bluetooth.disconnected", {{"id", id}, {"reason", "The device ended the connection or went out of range."}}, 0);
}

// Releases every object of the device, after which Windows ends the connection unless another app holds it.
void WindowsBluetooth::close(const std::string& id) {
    const auto found = devices.find(id);
    if (found == devices.end()) {
        return;
    }
    Connection entry = std::move(found->second);
    devices.erase(found);
    entry.statusChanges.revoke();
    entry.subscriptions.clear();
    entry.characteristics.clear();
    for (auto& [uuid, service] : entry.services) {
        service.Close();
    }
    entry.services.clear();
    if (entry.session) {
        entry.session.Close();
    }
    entry.device.Close();
}

std::optional<WindowsBluetooth::Answer> WindowsBluetooth::disconnect(const std::string& id) {
    const auto found = devices.find(id);
    if (found == devices.end()) {
        return Answer{Json::object(), std::nullopt};
    }
    const bool wasConnected = found->second.connected;
    const std::vector<std::uint64_t> calls = found->second.connecting;
    close(id);
    for (const std::uint64_t call : calls) {
        bridge.fail(call, {"connectFailed", "The app disconnected before the device connected."});
    }
    if (wasConnected) {
        bridge.emit("bluetooth.disconnected", {{"id", id}, {"reason", "The app disconnected."}}, 0);
    }
    return Answer{Json::object(), std::nullopt};
}

void WindowsBluetooth::giveUp(std::uint64_t call) {
    if (scanning && scanning->call == call) {
        dropScan();
        return;
    }
    for (auto& [id, entry] : devices) {
        if (std::erase(entry.connecting, call) == 0) {
            continue;
        }
        if (!entry.connected && entry.connecting.empty()) {
            const std::string abandoned = id;
            close(abandoned);
        }
        return;
    }
}

WindowsBluetooth::Connection& WindowsBluetooth::connectedDevice(const std::string& id) {
    const auto found = devices.find(id);
    if (found == devices.end() || !found->second.connected) {
        throw BluetoothFailure{"notConnected", "The device \"" + id + "\" is not connected. Connect to it first."};
    }
    return found->second;
}

// Fails with the meaning of a status of GATT that is not a success.
void WindowsBluetooth::check(Status status, const IReference<std::uint8_t>& protocolError, const std::string& id) {
    if (status == Status::Success) {
        return;
    }
    if (status == Status::Unreachable) {
        throw BluetoothFailure{"notConnected", "The device \"" + id + "\" cannot be reached. It went out of range or ended the connection."};
    }
    if (status == Status::AccessDenied) {
        throw BluetoothFailure{"failed", "The device \"" + id + "\" refused the operation, or another app holds it alone."};
    }
    const int code = protocolError ? protocolError.Value() : 0;
    throw BluetoothFailure{"failed", "The device \"" + id + "\" answered with the error " + std::to_string(code) + " of the attribute protocol."};
}

// Finds the services of the device, which Windows reads from the device each time, and keeps them for the calls that follow.
void WindowsBluetooth::discoverServices(Connection& entry) {
    const auto result = entry.device.GetGattServicesAsync(BluetoothCacheMode::Uncached).get();
    check(result.Status(), result.ProtocolError(), entry.id);
    for (auto& [uuid, service] : entry.services) {
        service.Close();
    }
    entry.services.clear();
    entry.characteristics.clear();
    for (const Service& service : result.Services()) {
        entry.services.emplace(formatUuid(service.Uuid()), service);
    }
}

WindowsBluetooth::Answer WindowsBluetooth::services(const std::string& id) {
    Connection& entry = connectedDevice(id);
    discoverServices(entry);
    Json uuids = Json::array();
    for (const auto& [uuid, service] : entry.services) {
        uuids.push_back(uuid);
    }
    return {uuids, std::nullopt};
}

WindowsBluetooth::Service& WindowsBluetooth::findService(Connection& entry, const std::string& uuid) {
    if (!entry.services.contains(uuid)) {
        discoverServices(entry);
    }
    const auto found = entry.services.find(uuid);
    if (found == entry.services.end()) {
        throw BluetoothFailure{"unknownService", "The device has no service \"" + uuid + "\"."};
    }
    return found->second;
}

std::map<std::string, WindowsBluetooth::Characteristic>& WindowsBluetooth::discoverCharacteristics(Connection& entry, const std::string& serviceUuid) {
    Service& service = findService(entry, serviceUuid);
    const auto result = service.GetCharacteristicsAsync(BluetoothCacheMode::Uncached).get();
    check(result.Status(), result.ProtocolError(), entry.id);
    std::map<std::string, Characteristic>& known = entry.characteristics[serviceUuid];
    known.clear();
    for (const Characteristic& characteristic : result.Characteristics()) {
        known.emplace(formatUuid(characteristic.Uuid()), characteristic);
    }
    return known;
}

bool WindowsBluetooth::has(Properties properties, Properties flag) {
    return (static_cast<std::uint32_t>(properties) & static_cast<std::uint32_t>(flag)) != 0;
}

WindowsBluetooth::Answer WindowsBluetooth::characteristics(const std::string& id, const std::string& service) {
    static const std::array<std::pair<Properties, std::string_view>, 5> kNames{{
        {Properties::Read, "read"},
        {Properties::Write, "write"},
        {Properties::WriteWithoutResponse, "writeWithoutResponse"},
        {Properties::Notify, "notify"},
        {Properties::Indicate, "indicate"},
    }};
    Connection& entry = connectedDevice(id);
    Json list = Json::array();
    for (const auto& [uuid, characteristic] : discoverCharacteristics(entry, service)) {
        const Properties properties = characteristic.CharacteristicProperties();
        Json names = Json::array();
        for (const auto& [flag, name] : kNames) {
            if (has(properties, flag)) {
                names.push_back(name);
            }
        }
        list.push_back({{"uuid", uuid}, {"properties", names}});
    }
    return {list, std::nullopt};
}

WindowsBluetooth::Characteristic WindowsBluetooth::findCharacteristic(Connection& entry, const std::string& service, const std::string& uuid) {
    const auto known = entry.characteristics.find(service);
    if (known != entry.characteristics.end() && known->second.contains(uuid)) {
        return known->second.at(uuid);
    }
    std::map<std::string, Characteristic>& discovered = discoverCharacteristics(entry, service);
    const auto found = discovered.find(uuid);
    if (found == discovered.end()) {
        throw BluetoothFailure{"unknownCharacteristic", "The service \"" + service + "\" has no characteristic \"" + uuid + "\"."};
    }
    return found->second;
}

WindowsBluetooth::Answer WindowsBluetooth::read(const BluetoothRequest& request) {
    Connection& entry = connectedDevice(request.id);
    const Characteristic characteristic = findCharacteristic(entry, request.service, request.characteristic);
    const auto result = characteristic.ReadValueAsync(BluetoothCacheMode::Uncached).get();
    check(result.Status(), result.ProtocolError(), request.id);
    return {{{"value", {{"$bytes", 0}}}}, copyBytes(result.Value())};
}

WindowsBluetooth::Answer WindowsBluetooth::write(const BluetoothRequest& request) {
    Connection& entry = connectedDevice(request.id);
    const Characteristic characteristic = findCharacteristic(entry, request.service, request.characteristic);

    const std::vector<std::uint8_t>& data = request.value;
    winrt::Windows::Storage::Streams::Buffer buffer(static_cast<std::uint32_t>(data.size()));
    buffer.Length(static_cast<std::uint32_t>(data.size()));
    if (!data.empty()) {
        std::memcpy(buffer.data(), data.data(), data.size());
    }
    const GattWriteOption option = request.response ? GattWriteOption::WriteWithResponse : GattWriteOption::WriteWithoutResponse;
    const auto result = characteristic.WriteValueWithResultAsync(buffer, option).get();
    check(result.Status(), result.ProtocolError(), request.id);
    return {Json::object(), std::nullopt};
}

WindowsBluetooth::Answer WindowsBluetooth::setNotify(const BluetoothRequest& request, bool enabled) {
    Connection& entry = connectedDevice(request.id);
    const Characteristic characteristic = findCharacteristic(entry, request.service, request.characteristic);
    const Properties properties = characteristic.CharacteristicProperties();
    const bool notifies = has(properties, Properties::Notify);
    if (!notifies && !has(properties, Properties::Indicate)) {
        throw BluetoothFailure{"notSupported", "The characteristic \"" + request.characteristic + "\" neither notifies nor indicates."};
    }
    const std::string key = request.service + "/" + request.characteristic;
    if (entry.subscriptions.contains(key) == enabled) {
        return {Json::object(), std::nullopt};
    }

    GattClientCharacteristicConfigurationDescriptorValue configuration = GattClientCharacteristicConfigurationDescriptorValue::None;
    if (enabled) {
        configuration = notifies ? GattClientCharacteristicConfigurationDescriptorValue::Notify : GattClientCharacteristicConfigurationDescriptorValue::Indicate;
    }
    const auto result = characteristic.WriteClientCharacteristicConfigurationDescriptorWithResultAsync(configuration).get();
    check(result.Status(), result.ProtocolError(), request.id);
    if (!enabled) {
        entry.subscriptions.erase(key);
        return {Json::object(), std::nullopt};
    }

    const Json payload = {{"id", request.id}, {"service", request.service}, {"characteristic", request.characteristic}, {"value", {{"$bytes", 0}}}};
    Subscription subscription;
    subscription.characteristic = characteristic;
    // clang-format off
    subscription.changes = characteristic.ValueChanged(winrt::auto_revoke, [this, payload](const Characteristic&, const GattValueChangedEventArgs& args) {
        const std::vector<std::uint8_t> value = copyBytes(args.CharacteristicValue());
        bridge.emitWithBytes("bluetooth.changed", payload, value, HAYLEN_NATIVE_EMIT_BATCHED);
    });
    // clang-format on
    entry.subscriptions.emplace(key, std::move(subscription));
    return {Json::object(), std::nullopt};
}

std::string WindowsBluetooth::formatUuid(const winrt::guid& value) {
    return std::format("{:08x}-{:04x}-{:04x}-{:02x}{:02x}-{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}", value.Data1, value.Data2, value.Data3, value.Data4[0], value.Data4[1], value.Data4[2], value.Data4[3], value.Data4[4], value.Data4[5], value.Data4[6], value.Data4[7]);
}

std::string WindowsBluetooth::formatAddress(std::uint64_t value) {
    return std::format("{:02X}:{:02X}:{:02X}:{:02X}:{:02X}:{:02X}", (value >> 40) & 0xFF, (value >> 32) & 0xFF, (value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF);
}

std::optional<std::uint64_t> WindowsBluetooth::parseAddress(std::string_view text) {
    if (text.size() != 17) {
        return std::nullopt;
    }
    std::uint64_t value = 0;
    for (std::size_t index = 0; index < 6; ++index) {
        const std::size_t at = index * 3;
        if (index > 0 && text[at - 1] != ':') {
            return std::nullopt;
        }
        unsigned int byte = 0;
        const auto parsed = std::from_chars(text.data() + at, text.data() + at + 2, byte, 16);
        if (parsed.ptr != text.data() + at + 2) {
            return std::nullopt;
        }
        value = (value << 8) | byte;
    }
    return value;
}

std::vector<std::uint8_t> WindowsBluetooth::copyBytes(const Buffer& buffer) {
    if (!buffer) {
        return {};
    }
    return std::vector<std::uint8_t>(buffer.data(), buffer.data() + buffer.Length());
}
