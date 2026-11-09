#include "MicrophonePlugin.hpp"

MicrophonePlugin* MicrophonePlugin::instance = nullptr;

int MicrophonePlugin::initialize(const HaylenNativeApi* api) {
    if (api->version != HAYLEN_NATIVE_API_VERSION) {
        return 1;
    }
    if (instance == nullptr) {
        instance = new MicrophonePlugin(*api);
    }

    // The Lua API of every app sends `microphone.reset` as it loads, so a recording that an earlier app of the process left running stops.
    api->registerHandler("microphone.reset", &MicrophonePlugin::stop, nullptr, instance);
    api->registerHandler("microphone.start", &MicrophonePlugin::start, nullptr, instance);
    api->registerHandler("microphone.stop", &MicrophonePlugin::stop, nullptr, instance);
    api->registerHandler("microphone.permission", &MicrophonePlugin::permission, nullptr, instance);
    api->registerHandler("microphone.requestPermission", &MicrophonePlugin::requestPermission, nullptr, instance);
    api->registerPlugin("microphone");
    return 0;
}

MicrophonePlugin::MicrophonePlugin(const HaylenNativeApi& engine) : api(engine), device(*this) {}

const HaylenNativeApi& MicrophonePlugin::getApi() const {
    return api;
}

void MicrophonePlugin::succeed(std::uint64_t call, const Json& result) const {
    const std::string text = write(result);
    api.resolve(call, 1, text.c_str(), nullptr, 0);
}

void MicrophonePlugin::fail(std::uint64_t call, std::string_view message, std::string_view code) const {
    const std::string text = write({{"message", message}, {"code", code}});
    api.resolve(call, 0, text.c_str(), nullptr, 0);
}

void MicrophonePlugin::emit(std::string_view event, const Json& payload) const {
    const std::string name(event);
    const std::string text = write(payload);
    api.emit(name.c_str(), text.c_str(), nullptr, 0, 0);
}

// The engine hands JSON text, which the library reads without exceptions, since none may cross the C interface of the engine.
void MicrophonePlugin::start(void* user, std::uint64_t call, const char*, const char* paramsJson, const HaylenNativeBuffer*, std::size_t) {
    auto& plugin = *static_cast<MicrophonePlugin*>(user);
    const Json params = Json::parse(paramsJson, nullptr, false);
    const std::optional<int> sampleRate = readSampleRate(params);
    if (!sampleRate) {
        plugin.fail(call, "The sample rate of the microphone is a positive number of hertz.", "microphoneFailed");
        return;
    }
    plugin.device.start(call, *sampleRate);
}

void MicrophonePlugin::stop(void* user, std::uint64_t call, const char*, const char*, const HaylenNativeBuffer*, std::size_t) {
    static_cast<MicrophonePlugin*>(user)->device.stop(call);
}

void MicrophonePlugin::permission(void* user, std::uint64_t call, const char*, const char*, const HaylenNativeBuffer*, std::size_t) {
    static_cast<MicrophonePlugin*>(user)->device.permission(call);
}

void MicrophonePlugin::requestPermission(void* user, std::uint64_t call, const char*, const char*, const HaylenNativeBuffer*, std::size_t) {
    static_cast<MicrophonePlugin*>(user)->device.requestPermission(call);
}

std::optional<int> MicrophonePlugin::readSampleRate(const Json& params) {
    if (!params.is_object()) {
        return kDefaultRate;
    }
    const auto found = params.find("sampleRate");
    if (found == params.end() || !found->is_number()) {
        return kDefaultRate;
    }

    const double rate = found->get<double>();
    if (rate < 1 || rate > kMaxRate) {
        return std::nullopt;
    }
    return static_cast<int>(rate);
}

std::string MicrophonePlugin::write(const Json& value) {
    return value.dump(-1, ' ', false, Json::error_handler_t::replace);
}
