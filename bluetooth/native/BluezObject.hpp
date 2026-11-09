#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

#include <dbus/dbus.h>

// An object that BlueZ publishes on the system bus, an adapter, a device, a service or a characteristic, with the properties of its interface that the plugin reads.
struct BluezObject {
    enum class Kind { Other, Adapter, Device, Service, Characteristic };

    static constexpr const char* kAdapterInterface = "org.bluez.Adapter1";
    static constexpr const char* kDeviceInterface = "org.bluez.Device1";
    static constexpr const char* kServiceInterface = "org.bluez.GattService1";
    static constexpr const char* kCharacteristicInterface = "org.bluez.GattCharacteristic1";

    // The properties that a set of changes or a set of values holds, so a change tells which of them it carries.
    static constexpr unsigned kHasPowered = 1;
    static constexpr unsigned kHasConnected = 2;
    static constexpr unsigned kHasResolved = 4;
    static constexpr unsigned kHasRssi = 8;
    static constexpr unsigned kHasName = 16;
    static constexpr unsigned kHasAdvertisement = 32;

    // The properties of a characteristic, as the flags of BlueZ name them.
    static constexpr unsigned kReads = 1;
    static constexpr unsigned kWrites = 2;
    static constexpr unsigned kWritesWithoutResponse = 4;
    static constexpr unsigned kNotifies = 8;
    static constexpr unsigned kIndicates = 16;

    Kind kind = Kind::Other;
    unsigned present = 0;
    std::string path;
    std::string parent;
    std::string address;
    std::string uuid;
    std::string name;
    int rssi = 0;
    bool powered = false;
    bool connected = false;
    bool resolved = false;
    unsigned flags = 0;
    std::vector<std::string> uuids;
    // The data of the maker as the bytes that advertise it: the first company id in little endian and its bytes.
    std::vector<std::uint8_t> maker;

    [[nodiscard]] bool has(unsigned properties) const;

    // Reads the properties of a dictionary of names and variants that the plugin uses, and marks the ones it found.
    void readProperties(DBusMessageIter* dictionary);

    // Reads the interfaces of the object, a dictionary of interface names and their properties, and takes the kind of the interface of BlueZ that it has.
    void readInterfaces(DBusMessageIter* interfaces);

    // Reads a variant that holds a boolean, which is false when it holds another type.
    [[nodiscard]] static bool readBool(DBusMessageIter* value);

  private:
    [[nodiscard]] static Kind kindOf(std::string_view interface);
    [[nodiscard]] static std::string readText(DBusMessageIter* value);
    [[nodiscard]] static std::vector<std::string> readStrings(DBusMessageIter* array);
    [[nodiscard]] static unsigned readFlags(DBusMessageIter* array);

    void readMaker(DBusMessageIter* dictionary);
};
