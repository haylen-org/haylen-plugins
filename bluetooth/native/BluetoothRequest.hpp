#pragma once

#include <array>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include <nlohmann/json.hpp>

#include "haylen/platform/native/HaylenNative.h"

// A call of the app with copies of its parameters, which the handler reads on the frame thread so the work can run later on a thread of the library.
struct BluetoothRequest {
    enum class Kind { Scan, StopScan, Connect, Disconnect, Services, Characteristics, Read, Write, Subscribe, Unsubscribe, Permission };

    // The methods of the plugin without the prefix `bluetooth.`, with the kind of request each one makes.
    static const std::array<std::pair<std::string_view, Kind>, 12> kMethods;

    Kind kind = Kind::Permission;
    std::uint64_t call = 0;
    std::string id;
    std::string service;
    std::string characteristic;
    std::vector<std::string> services;
    double seconds = 0;
    bool response = false;
    std::vector<std::uint8_t> value;

    // The kind of a method of `kMethods`, the only methods whose handlers the plugin registers.
    [[nodiscard]] static Kind kindOf(std::string_view method);

    // Reads the parameters that the method of `requested` needs, as `source/init.lua` sends them, and throws a `BluetoothFailure` with the code `invalidParams` for one that is missing or of another type.
    [[nodiscard]] static BluetoothRequest parse(Kind requested, std::uint64_t requestCall, const char* paramsJson, std::span<const HaylenNativeBuffer> buffers);

  private:
    using Json = nlohmann::json;

    [[nodiscard]] static std::string readText(const Json& params, const char* key);
    [[nodiscard]] static std::vector<std::string> readUuids(const Json& params);
    [[nodiscard]] static double readSeconds(const Json& params);
    [[nodiscard]] static bool readFlag(const Json& params, const char* key);
    [[nodiscard]] static std::vector<std::uint8_t> readBytes(const Json& params, const char* key, std::span<const HaylenNativeBuffer> buffers);
};
