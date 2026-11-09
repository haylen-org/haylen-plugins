#include "BluetoothRequest.hpp"

#include <algorithm>

#include "BluetoothFailure.hpp"

const std::array<std::pair<std::string_view, BluetoothRequest::Kind>, 12> BluetoothRequest::kMethods{{
    {"scan", Kind::Scan},
    {"stopScan", Kind::StopScan},
    {"connect", Kind::Connect},
    {"disconnect", Kind::Disconnect},
    {"services", Kind::Services},
    {"characteristics", Kind::Characteristics},
    {"read", Kind::Read},
    {"write", Kind::Write},
    {"subscribe", Kind::Subscribe},
    {"unsubscribe", Kind::Unsubscribe},
    {"permission", Kind::Permission},
    {"requestPermission", Kind::Permission},
}};

BluetoothRequest::Kind BluetoothRequest::kindOf(std::string_view method) {
    const auto found = std::ranges::find(kMethods, method, &std::pair<std::string_view, Kind>::first);
    return found->second;
}

BluetoothRequest BluetoothRequest::parse(Kind requested, std::uint64_t requestCall, const char* paramsJson, std::span<const HaylenNativeBuffer> buffers) {
    const Json params = Json::parse(paramsJson != nullptr ? paramsJson : "{}", nullptr, false);
    BluetoothRequest request;
    request.kind = requested;
    request.call = requestCall;

    const bool namesCharacteristic = requested == Kind::Read || requested == Kind::Write || requested == Kind::Subscribe || requested == Kind::Unsubscribe;
    const bool namesService = namesCharacteristic || requested == Kind::Characteristics;
    const bool namesDevice = namesService || requested == Kind::Connect || requested == Kind::Disconnect || requested == Kind::Services;
    if (namesDevice) {
        request.id = readText(params, "id");
    }
    if (namesService) {
        request.service = readText(params, "service");
    }
    if (namesCharacteristic) {
        request.characteristic = readText(params, "characteristic");
    }

    if (requested == Kind::Scan) {
        request.services = readUuids(params);
        request.seconds = readSeconds(params);
    }
    if (requested == Kind::Write) {
        request.value = readBytes(params, "value", buffers);
        request.response = readFlag(params, "response");
    }
    return request;
}

std::string BluetoothRequest::readText(const Json& params, const char* key) {
    const auto found = params.is_object() ? params.find(key) : params.end();
    if (found == params.end() || !found->is_string() || found->get_ref<const std::string&>().empty()) {
        throw BluetoothFailure{"invalidParams", "The call needs \"" + std::string(key) + "\" as a string."};
    }
    return found->get<std::string>();
}

// An empty list of Lua crosses the bridge as an empty object, which counts as an empty list.
std::vector<std::string> BluetoothRequest::readUuids(const Json& params) {
    const BluetoothFailure invalid{"invalidParams", "The \"services\" of a scan are a list of UUID strings."};
    const auto found = params.is_object() ? params.find("services") : params.end();
    if (found == params.end()) {
        throw invalid;
    }
    if (found->is_object() && found->empty()) {
        return {};
    }
    if (!found->is_array()) {
        throw invalid;
    }

    std::vector<std::string> uuids;
    for (const Json& uuid : *found) {
        if (!uuid.is_string()) {
            throw invalid;
        }
        uuids.push_back(uuid.get<std::string>());
    }
    return uuids;
}

double BluetoothRequest::readSeconds(const Json& params) {
    const auto found = params.is_object() ? params.find("seconds") : params.end();
    if (found == params.end() || !found->is_number() || !(found->get<double>() > 0)) {
        throw BluetoothFailure{"invalidParams", "The \"seconds\" of a scan are a number above 0."};
    }
    return found->get<double>();
}

bool BluetoothRequest::readFlag(const Json& params, const char* key) {
    const auto found = params.is_object() ? params.find(key) : params.end();
    if (found == params.end() || !found->is_boolean()) {
        throw BluetoothFailure{"invalidParams", "The call needs \"" + std::string(key) + "\" as a boolean."};
    }
    return found->get<bool>();
}

// Copies the bytes that the reference `{"$bytes": N}` names, since the buffers of the call live only while its handler runs.
std::vector<std::uint8_t> BluetoothRequest::readBytes(const Json& params, const char* key, std::span<const HaylenNativeBuffer> buffers) {
    const BluetoothFailure invalid{"invalidParams", "The call needs \"" + std::string(key) + "\" as bytes."};
    const auto found = params.is_object() ? params.find(key) : params.end();
    if (found == params.end() || !found->is_object()) {
        throw invalid;
    }
    const auto reference = found->find("$bytes");
    if (reference == found->end() || !reference->is_number_unsigned() || reference->get<std::size_t>() >= buffers.size()) {
        throw invalid;
    }

    const HaylenNativeBuffer& buffer = buffers[reference->get<std::size_t>()];
    const auto* data = static_cast<const std::uint8_t*>(buffer.data);
    return std::vector<std::uint8_t>(data, data + buffer.size);
}
