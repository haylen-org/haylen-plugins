#pragma once

#include <chrono>
#include <cstdint>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <vector>

#include <nlohmann/json.hpp>
#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.Streams.h>

#include "BluetoothBridge.hpp"
#include "BluetoothRequest.hpp"
#include "WindowsBluetoothWorker.hpp"

// The central of Bluetooth Low Energy on Windows, through the Windows Runtime, called with C++/WinRT, whose headers come with the Windows SDK: `BluetoothLEAdvertisementWatcher` scans, a `GattSession` that maintains its connection connects, and the GATT objects of `BluetoothLEDevice` read, write and notify. Windows gates Bluetooth Low Energy behind no permission for desktop apps, so the permission `bluetooth` tells whether the computer has an adapter with Bluetooth Low Energy. The requests run on a thread of the library in the multithreaded apartment, which alone touches the state of the library, and the events of the Windows Runtime post their work to that thread too.
class WindowsBluetooth final {
  public:
    explicit WindowsBluetooth(const BluetoothBridge& owner);

    // Hands the request to the thread of the library. It runs on the frame thread.
    void submit(BluetoothRequest request);

    // Gives up a scan or a connection whose call the app cancelled or whose timeout passed. A connection that the app gives up stops its attempt.
    void cancel(std::uint64_t call);

  private:
    using Json = nlohmann::json;
    using Clock = WindowsBluetoothWorker::Clock;
    using Kind = BluetoothRequest::Kind;
    using Device = winrt::Windows::Devices::Bluetooth::BluetoothLEDevice;
    using AddressType = winrt::Windows::Devices::Bluetooth::BluetoothAddressType;
    using BluetoothError = winrt::Windows::Devices::Bluetooth::BluetoothError;
    using Watcher = winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisementWatcher;
    using Received = winrt::Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisementReceivedEventArgs;
    using Characteristic = winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattCharacteristic;
    using Properties = winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattCharacteristicProperties;
    using Status = winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattCommunicationStatus;
    using Service = winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattDeviceService;
    using Session = winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattSession;
    using Buffer = winrt::Windows::Storage::Streams::IBuffer;

    // The answer of a call that succeeds, with the bytes that its JSON names as `{"$bytes": 0}`.
    struct Answer {
        Json result;
        std::optional<std::vector<std::uint8_t>> bytes;
    };

    // A characteristic that the app subscribed to, whose values reach the app while its revoker lives.
    struct Subscription {
        Characteristic characteristic{nullptr};
        Characteristic::ValueChanged_revoker changes;
    };

    // A device that the app connects to or connected to, with the session that keeps the connection and the GATT objects that the calls found.
    struct Connection {
        std::string id;
        Device device{nullptr};
        Session session{nullptr};
        Device::ConnectionStatusChanged_revoker statusChanges;
        bool connected = false;
        std::uint64_t attempt = 0;
        std::vector<std::uint64_t> connecting;
        std::map<std::string, Service> services;
        std::map<std::string, std::map<std::string, Characteristic>> characteristics;
        std::map<std::string, Subscription> subscriptions;
    };

    // What one scan learned of a device from its advertisements and scan responses, until it reaches the app once.
    struct Sighting {
        std::string name;
        std::set<std::string> services;
        std::optional<std::vector<std::uint8_t>> manufacturerData;
        int rssi = 0;
        bool responded = false;
        bool sent = false;
        Clock::time_point first;
    };

    // The scan that runs, with the services that it looks for and the devices that it saw.
    struct Scan {
        std::uint64_t call = 0;
        std::uint64_t generation = 0;
        Watcher watcher{nullptr};
        Watcher::Received_revoker received;
        Watcher::Stopped_revoker stopped;
        std::set<std::string> services;
        std::map<std::uint64_t, Sighting> sightings;
    };

    // The time that a connection may take before it fails.
    static constexpr std::chrono::seconds kConnectBound{30};

    // How long a scan waits for the scan response of a device that advertises without its name, before the device reaches the app without it.
    static constexpr std::chrono::seconds kResponseBound{1};

    void run(const BluetoothRequest& request);
    [[nodiscard]] std::optional<Answer> dispatch(const BluetoothRequest& request);
    void resolve(std::uint64_t call, const Answer& answer) const;

    [[nodiscard]] static Answer permission();
    static void ready();

    [[nodiscard]] std::optional<Answer> scan(const BluetoothRequest& request);
    void endScan();
    void dropScan();
    void stoppedScan(std::uint64_t generation, BluetoothError error);
    void saw(std::uint64_t generation, const Received& args);
    [[nodiscard]] static bool matches(const Scan& running, const Sighting& sighting);
    void sendFound(std::uint64_t address, const Sighting& sighting) const;

    [[nodiscard]] std::optional<Answer> connect(std::uint64_t call, const std::string& id);
    [[nodiscard]] static Answer connectedAnswer(const Connection& entry);
    [[nodiscard]] Device openDevice(const std::string& id) const;
    void changedStatus(const std::string& id, bool isConnected);
    void close(const std::string& id);
    [[nodiscard]] std::optional<Answer> disconnect(const std::string& id);
    void giveUp(std::uint64_t call);

    [[nodiscard]] Connection& connectedDevice(const std::string& id);
    static void check(Status status, const winrt::Windows::Foundation::IReference<std::uint8_t>& protocolError, const std::string& id);
    static void discoverServices(Connection& entry);
    [[nodiscard]] Answer services(const std::string& id);
    [[nodiscard]] static Service& findService(Connection& entry, const std::string& uuid);
    static std::map<std::string, Characteristic>& discoverCharacteristics(Connection& entry, const std::string& serviceUuid);
    [[nodiscard]] static bool has(Properties properties, Properties flag);
    [[nodiscard]] Answer characteristics(const std::string& id, const std::string& service);
    [[nodiscard]] static Characteristic findCharacteristic(Connection& entry, const std::string& service, const std::string& uuid);
    [[nodiscard]] Answer read(const BluetoothRequest& request);
    [[nodiscard]] Answer write(const BluetoothRequest& request);
    // Writes the configuration of the characteristic on the device, with notifications where it notifies and indications where it only indicates, and sends every value it notifies as the batched event `bluetooth.changed`.
    [[nodiscard]] Answer setNotify(const BluetoothRequest& request, bool enabled);

    // The full form of a UUID in lowercase, as every platform answers it.
    [[nodiscard]] static std::string formatUuid(const winrt::guid& value);
    // The address of a device as six bytes in hexadecimal with colons, such as `AA:BB:CC:DD:EE:FF`, which is its id.
    [[nodiscard]] static std::string formatAddress(std::uint64_t value);
    [[nodiscard]] static std::optional<std::uint64_t> parseAddress(std::string_view text);
    [[nodiscard]] static std::vector<std::uint8_t> copyBytes(const Buffer& buffer);

    const BluetoothBridge& bridge;
    WindowsBluetoothWorker worker;

    // The state that only the thread of the library touches.
    std::optional<Scan> scanning;
    std::uint64_t scans = 0;
    std::uint64_t attempts = 0;
    std::map<std::uint64_t, AddressType> addressTypes;
    std::map<std::string, Connection> devices;
};
