#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

#include <nlohmann/json.hpp>

#include "haylen/platform/native/HaylenNative.h"

// The engine as the desktop part of the Location plugin talks to it: the calls it answers and the events it sends with JSON payloads, from any thread, the parameters of the calls it reads, and the sentences that every desktop shares. The engine hands one native API for the life of the process.
class LocationBridge final {
  public:
    using Json = nlohmann::json;

    static constexpr std::string_view kLocationOff = "The location of the device is turned off. The person turns it on in the settings of the system.";

    explicit LocationBridge(const HaylenNativeApi& engine);

    // Reads the parameters of a call, which are discarded JSON when the text is not JSON, since no exception may cross the C interface of the engine.
    [[nodiscard]] static Json parse(const char* text);
    [[nodiscard]] static std::optional<double> readNumber(const Json& params, const char* key);
    [[nodiscard]] static std::optional<bool> readBool(const Json& params, const char* key);
    [[nodiscard]] static std::optional<std::string> readText(const Json& params, const char* key);

    // The words of a permission of the plugin, such as "the precise location" for `preciseLocation`, or nothing for a name that the plugin does not own.
    [[nodiscard]] static std::optional<std::string_view> describePermission(std::string_view permission);
    // The sentence of a call that needs a permission that the person has not allowed.
    [[nodiscard]] static std::string refusal(std::string_view permission);
    [[nodiscard]] static Json failure(std::string_view message, std::string_view code);
    // A count of seconds as the shortest text that reads back as the same number.
    [[nodiscard]] static std::string seconds(double value);

    void succeed(std::uint64_t call, const Json& result) const;
    void fail(std::uint64_t call, std::string_view message, std::string_view code) const;
    void emit(const char* event, const Json& payload, int flags) const;

  private:
    // The JSON of a value, with bytes that are not UTF-8 replaced, since the text crosses into the engine.
    [[nodiscard]] static std::string write(const Json& value);

    const HaylenNativeApi& api;
};
