#include "BluezObject.hpp"

#include <array>
#include <utility>

bool BluezObject::has(unsigned properties) const {
    return (present & properties) != 0;
}

void BluezObject::readProperties(DBusMessageIter* dictionary) {
    DBusMessageIter entry;
    dbus_message_iter_recurse(dictionary, &entry);
    while (dbus_message_iter_get_arg_type(&entry) == DBUS_TYPE_DICT_ENTRY) {
        DBusMessageIter pair;
        DBusMessageIter value;
        const char* key = nullptr;
        dbus_message_iter_recurse(&entry, &pair);
        dbus_message_iter_get_basic(&pair, &key);
        dbus_message_iter_next(&pair);
        dbus_message_iter_recurse(&pair, &value);

        const std::string_view property(key);
        const int type = dbus_message_iter_get_arg_type(&value);
        if (property == "Address") {
            address = readText(&value);
        } else if (property == "Adapter" || property == "Device" || property == "Service") {
            parent = readText(&value);
        } else if (property == "UUID") {
            uuid = readText(&value);
        } else if (property == "Name") {
            name = readText(&value);
            present |= kHasName;
        } else if (property == "RSSI" && type == DBUS_TYPE_INT16) {
            dbus_int16_t signal = 0;
            dbus_message_iter_get_basic(&value, &signal);
            rssi = signal;
            present |= kHasRssi;
        } else if (property == "Powered") {
            powered = readBool(&value);
            present |= kHasPowered;
        } else if (property == "Connected") {
            connected = readBool(&value);
            present |= kHasConnected;
        } else if (property == "ServicesResolved") {
            resolved = readBool(&value);
            present |= kHasResolved;
        } else if (property == "Flags" && type == DBUS_TYPE_ARRAY) {
            flags = readFlags(&value);
        } else if (property == "UUIDs" && type == DBUS_TYPE_ARRAY) {
            uuids = readStrings(&value);
            present |= kHasAdvertisement;
        } else if (property == "ManufacturerData" && type == DBUS_TYPE_ARRAY) {
            readMaker(&value);
        }
        dbus_message_iter_next(&entry);
    }
}

void BluezObject::readInterfaces(DBusMessageIter* interfaces) {
    DBusMessageIter entry;
    dbus_message_iter_recurse(interfaces, &entry);
    while (dbus_message_iter_get_arg_type(&entry) == DBUS_TYPE_DICT_ENTRY) {
        DBusMessageIter pair;
        const char* interface = nullptr;
        dbus_message_iter_recurse(&entry, &pair);
        dbus_message_iter_get_basic(&pair, &interface);
        dbus_message_iter_next(&pair);

        const Kind found = kindOf(interface);
        if (found != Kind::Other) {
            kind = found;
            readProperties(&pair);
        }
        dbus_message_iter_next(&entry);
    }
}

bool BluezObject::readBool(DBusMessageIter* value) {
    dbus_bool_t flag = FALSE;
    if (dbus_message_iter_get_arg_type(value) == DBUS_TYPE_BOOLEAN) {
        dbus_message_iter_get_basic(value, &flag);
    }
    return flag != FALSE;
}

BluezObject::Kind BluezObject::kindOf(std::string_view interface) {
    static const std::array<std::pair<std::string_view, Kind>, 4> kInterfaces{{
        {kAdapterInterface, Kind::Adapter},
        {kDeviceInterface, Kind::Device},
        {kServiceInterface, Kind::Service},
        {kCharacteristicInterface, Kind::Characteristic},
    }};
    for (const auto& [interfaceName, interfaceKind] : kInterfaces) {
        if (interfaceName == interface) {
            return interfaceKind;
        }
    }
    return Kind::Other;
}

std::string BluezObject::readText(DBusMessageIter* value) {
    const int type = dbus_message_iter_get_arg_type(value);
    if (type != DBUS_TYPE_STRING && type != DBUS_TYPE_OBJECT_PATH) {
        return {};
    }
    const char* text = nullptr;
    dbus_message_iter_get_basic(value, &text);
    return text;
}

std::vector<std::string> BluezObject::readStrings(DBusMessageIter* array) {
    DBusMessageIter item;
    dbus_message_iter_recurse(array, &item);
    std::vector<std::string> strings;
    while (dbus_message_iter_get_arg_type(&item) == DBUS_TYPE_STRING) {
        const char* text = nullptr;
        dbus_message_iter_get_basic(&item, &text);
        strings.emplace_back(text);
        dbus_message_iter_next(&item);
    }
    return strings;
}

unsigned BluezObject::readFlags(DBusMessageIter* array) {
    static const std::array<std::pair<std::string_view, unsigned>, 5> kFlags{{
        {"read", kReads},
        {"write", kWrites},
        {"write-without-response", kWritesWithoutResponse},
        {"notify", kNotifies},
        {"indicate", kIndicates},
    }};
    unsigned found = 0;
    for (const std::string& flag : readStrings(array)) {
        for (const auto& [flagName, bit] : kFlags) {
            if (flagName == flag) {
                found |= bit;
            }
        }
    }
    return found;
}

// Keeps the first company of the dictionary of company ids and bytes, as the platforms that advertise one maker give it.
void BluezObject::readMaker(DBusMessageIter* dictionary) {
    DBusMessageIter entry;
    dbus_message_iter_recurse(dictionary, &entry);
    maker.clear();
    if (dbus_message_iter_get_arg_type(&entry) != DBUS_TYPE_DICT_ENTRY) {
        return;
    }

    DBusMessageIter pair;
    DBusMessageIter variant;
    DBusMessageIter bytes;
    dbus_message_iter_recurse(&entry, &pair);
    if (dbus_message_iter_get_arg_type(&pair) != DBUS_TYPE_UINT16) {
        return;
    }
    dbus_uint16_t company = 0;
    dbus_message_iter_get_basic(&pair, &company);
    dbus_message_iter_next(&pair);
    dbus_message_iter_recurse(&pair, &variant);
    if (dbus_message_iter_get_arg_type(&variant) != DBUS_TYPE_ARRAY || dbus_message_iter_get_element_type(&variant) != DBUS_TYPE_BYTE) {
        return;
    }

    const std::uint8_t* data = nullptr;
    int length = 0;
    dbus_message_iter_recurse(&variant, &bytes);
    dbus_message_iter_get_fixed_array(&bytes, &data, &length);
    maker.push_back(static_cast<std::uint8_t>(company & 0xFF));
    maker.push_back(static_cast<std::uint8_t>(company >> 8));
    maker.insert(maker.end(), data, data + length);
    present |= kHasAdvertisement;
}
