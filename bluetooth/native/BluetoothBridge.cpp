#include "BluetoothBridge.hpp"

BluetoothBridge::BluetoothBridge(const HaylenNativeApi& engine) : api(&engine) {}

void BluetoothBridge::setApi(const HaylenNativeApi& engine) {
    api.store(&engine);
}

void BluetoothBridge::succeed(std::uint64_t call, const Json& result) const {
    const std::string text = write(result);
    api.load()->resolve(call, 1, text.c_str(), nullptr, 0);
}

void BluetoothBridge::succeedWithBytes(std::uint64_t call, const Json& result, std::span<const std::uint8_t> bytes) const {
    const std::string text = write(result);
    const HaylenNativeBuffer buffer{.data = bytes.data(), .size = bytes.size()};
    api.load()->resolve(call, 1, text.c_str(), &buffer, 1);
}

void BluetoothBridge::fail(std::uint64_t call, const BluetoothFailure& failure) const {
    const std::string text = write({{"message", failure.message}, {"code", failure.code}});
    api.load()->resolve(call, 0, text.c_str(), nullptr, 0);
}

void BluetoothBridge::emit(std::string_view event, const Json& payload, int flags) const {
    const std::string name(event);
    const std::string text = write(payload);
    api.load()->emit(name.c_str(), text.c_str(), nullptr, 0, flags);
}

void BluetoothBridge::emitWithBytes(std::string_view event, const Json& payload, std::span<const std::uint8_t> bytes, int flags) const {
    const std::string name(event);
    const std::string text = write(payload);
    const HaylenNativeBuffer buffer{.data = bytes.data(), .size = bytes.size()};
    api.load()->emit(name.c_str(), text.c_str(), &buffer, 1, flags);
}

void BluetoothBridge::log(int level, const std::string& text) const {
    api.load()->log(level, text.c_str());
}

std::string BluetoothBridge::write(const Json& value) {
    return value.dump(-1, ' ', false, Json::error_handler_t::replace);
}
