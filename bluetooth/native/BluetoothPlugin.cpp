#include "BluetoothPlugin.hpp"

#include <span>
#include <string>
#include <utility>

#include "BluetoothFailure.hpp"
#include "BluetoothRequest.hpp"

int BluetoothPlugin::initialize(const HaylenNativeApi* api) {
    if (api->version != HAYLEN_NATIVE_API_VERSION) {
        return 1;
    }

    if (instance == nullptr) {
        instance = new BluetoothPlugin(*api);
    } else {
        instance->bridge.setApi(*api);
    }

    for (const auto& [name, kind] : BluetoothRequest::kMethods) {
        const std::string method = std::string(kPrefix) + std::string(name);
        const bool cancellable = kind == BluetoothRequest::Kind::Scan || kind == BluetoothRequest::Kind::Connect;
        api->registerHandler(method.c_str(), &BluetoothPlugin::handleCall, cancellable ? &BluetoothPlugin::cancelCall : nullptr, instance);
    }
    api->registerPlugin("bluetooth");
    return 0;
}

BluetoothPlugin::BluetoothPlugin(const HaylenNativeApi& engine) : bridge(engine), central(bridge) {}

void BluetoothPlugin::handleCall(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount) {
    auto& plugin = *static_cast<BluetoothPlugin*>(user);
    const BluetoothRequest::Kind kind = BluetoothRequest::kindOf(std::string_view(method).substr(kPrefix.size()));
    try {
        BluetoothRequest request = BluetoothRequest::parse(kind, call, paramsJson, std::span(buffers, bufferCount));
        plugin.central.submit(std::move(request));
    } catch (const BluetoothFailure& failure) {
        plugin.bridge.fail(call, failure);
    }
}

void BluetoothPlugin::cancelCall(void* user, std::uint64_t call) {
    auto& plugin = *static_cast<BluetoothPlugin*>(user);
    plugin.central.cancel(call);
}
