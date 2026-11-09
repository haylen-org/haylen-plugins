#include "MotionPlugin.hpp"

MotionPlugin* MotionPlugin::instance = nullptr;

int MotionPlugin::initialize(const HaylenNativeApi* api) {
    if (api->version != HAYLEN_NATIVE_API_VERSION) {
        return 1;
    }
    if (instance == nullptr) {
        instance = new MotionPlugin(*api);
    }

    api->registerHandler("motion.permission", &MotionPlugin::permission, nullptr, instance);
    api->registerHandler("motion.requestPermission", &MotionPlugin::permission, nullptr, instance);
    api->registerHandler("motion.watch", &MotionPlugin::watch, &MotionPlugin::cancelWatch, instance);
    api->registerHandler("motion.start", &MotionPlugin::start, nullptr, instance);
    api->registerPlugin("motion");
    return 0;
}

MotionPlugin::MotionPlugin(const HaylenNativeApi& engine) : api(engine), device(*this) {}

const HaylenNativeApi& MotionPlugin::getApi() const {
    return api;
}

void MotionPlugin::succeed(std::uint64_t call, const Json& result) const {
    const std::string text = write(result);
    api.resolve(call, 1, text.c_str(), nullptr, 0);
}

void MotionPlugin::fail(std::uint64_t call, std::string_view message, std::string_view code) const {
    const std::string text = write({{"message", message}, {"code", code}});
    api.resolve(call, 0, text.c_str(), nullptr, 0);
}

void MotionPlugin::emit(std::string_view event, const Json& payload, int flags) const {
    const std::string name(event);
    const std::string text = write(payload);
    api.emit(name.c_str(), text.c_str(), nullptr, 0, flags);
}

// Answers `motion.permission` and `motion.requestPermission`, which ask for nothing on the desktops.
void MotionPlugin::permission(void* user, std::uint64_t call, const char*, const char*, const HaylenNativeBuffer*, std::size_t) {
    static_cast<MotionPlugin*>(user)->device.permission(call);
}

// The engine hands JSON text, which the library reads without exceptions, since none may cross the C interface of the engine.
void MotionPlugin::watch(void* user, std::uint64_t call, const char*, const char* paramsJson, const HaylenNativeBuffer*, std::size_t) {
    auto& plugin = *static_cast<MotionPlugin*>(user);
    const Json params = Json::parse(paramsJson, nullptr, false);
    const std::optional<std::int64_t> session = readSession(params);
    if (!session) {
        plugin.fail(call, "The call \"motion.watch\" needs the \"session\" that the Lua API of the plugin sends.", "invalidParams");
        return;
    }
    plugin.device.watch(call, *session);
}

void MotionPlugin::cancelWatch(void* user, std::uint64_t call) {
    static_cast<MotionPlugin*>(user)->device.cancelWatch(call);
}

void MotionPlugin::start(void* user, std::uint64_t call, const char*, const char* paramsJson, const HaylenNativeBuffer*, std::size_t) {
    auto& plugin = *static_cast<MotionPlugin*>(user);
    const Json params = Json::parse(paramsJson, nullptr, false);
    const std::optional<std::int64_t> session = readSession(params);
    const std::optional<double> rate = readNumber(params, "rate");
    std::vector<std::string> sensors = readNames(params, "sensors");
    if (!session || !rate || *rate <= 0 || sensors.empty()) {
        plugin.fail(call, "The call \"motion.start\" needs the \"session\", a \"rate\" above 0 and the \"sensors\" that the Lua API of the plugin sends.", "invalidParams");
        return;
    }
    plugin.device.start(call, *session, *rate, std::move(sensors));
}

std::optional<std::int64_t> MotionPlugin::readSession(const Json& params) {
    const std::optional<double> session = readNumber(params, "session");
    if (!session || *session < 1) {
        return std::nullopt;
    }
    return static_cast<std::int64_t>(*session);
}

std::optional<double> MotionPlugin::readNumber(const Json& params, const char* key) {
    if (!params.is_object()) {
        return std::nullopt;
    }
    const auto found = params.find(key);
    if (found == params.end() || !found->is_number()) {
        return std::nullopt;
    }
    return found->get<double>();
}

std::vector<std::string> MotionPlugin::readNames(const Json& params, const char* key) {
    std::vector<std::string> names;
    if (!params.is_object()) {
        return names;
    }
    const auto found = params.find(key);
    if (found == params.end() || !found->is_array()) {
        return names;
    }

    for (const Json& name : *found) {
        if (name.is_string()) {
            names.push_back(name.get<std::string>());
        }
    }
    return names;
}

std::string MotionPlugin::write(const Json& value) {
    return value.dump(-1, ' ', false, Json::error_handler_t::replace);
}
