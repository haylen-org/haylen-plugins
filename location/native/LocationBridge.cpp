#include "LocationBridge.hpp"

#include <array>
#include <charconv>

LocationBridge::LocationBridge(const HaylenNativeApi& engine) : api(engine) {}

LocationBridge::Json LocationBridge::parse(const char* text) {
    return Json::parse(text, nullptr, false);
}

std::optional<double> LocationBridge::readNumber(const Json& params, const char* key) {
    if (!params.is_object()) {
        return std::nullopt;
    }
    const auto found = params.find(key);
    if (found == params.end() || !found->is_number()) {
        return std::nullopt;
    }
    return found->get<double>();
}

std::optional<bool> LocationBridge::readBool(const Json& params, const char* key) {
    if (!params.is_object()) {
        return std::nullopt;
    }
    const auto found = params.find(key);
    if (found == params.end() || !found->is_boolean()) {
        return std::nullopt;
    }
    return found->get<bool>();
}

std::optional<std::string> LocationBridge::readText(const Json& params, const char* key) {
    if (!params.is_object()) {
        return std::nullopt;
    }
    const auto found = params.find(key);
    if (found == params.end() || !found->is_string()) {
        return std::nullopt;
    }
    return found->get<std::string>();
}

std::optional<std::string_view> LocationBridge::describePermission(std::string_view permission) {
    if (permission == "location") {
        return "the location";
    }
    if (permission == "preciseLocation") {
        return "the precise location";
    }
    if (permission == "backgroundLocation") {
        return "the location in the background";
    }
    return std::nullopt;
}

std::string LocationBridge::refusal(std::string_view permission) {
    const std::string_view words = describePermission(permission).value_or("the location");
    return "The person has not allowed " + std::string(words) + ". Ask for it with \"location.requestPermission('" + std::string(permission) + "')\", which shows the prompt of the system while the system still asks, or the person allows it in the settings of the system.";
}

LocationBridge::Json LocationBridge::failure(std::string_view message, std::string_view code) {
    return {{"message", message}, {"code", code}};
}

std::string LocationBridge::seconds(double value) {
    std::array<char, 32> digits{};
    const auto written = std::to_chars(digits.data(), digits.data() + digits.size(), value);
    return std::string(digits.data(), written.ptr);
}

void LocationBridge::succeed(std::uint64_t call, const Json& result) const {
    const std::string text = write(result);
    api.resolve(call, 1, text.c_str(), nullptr, 0);
}

void LocationBridge::fail(std::uint64_t call, std::string_view message, std::string_view code) const {
    const std::string text = write(failure(message, code));
    api.resolve(call, 0, text.c_str(), nullptr, 0);
}

void LocationBridge::emit(const char* event, const Json& payload, int flags) const {
    const std::string text = write(payload);
    api.emit(event, text.c_str(), nullptr, 0, flags);
}

std::string LocationBridge::write(const Json& value) {
    return value.dump(-1, ' ', false, Json::error_handler_t::replace);
}
