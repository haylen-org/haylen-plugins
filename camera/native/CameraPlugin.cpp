#include "CameraPlugin.hpp"

#include <limits>

CameraPlugin* CameraPlugin::instance = nullptr;

int CameraPlugin::initialize(const HaylenNativeApi* api) {
    if (api->version != HAYLEN_NATIVE_API_VERSION) {
        return 1;
    }
    if (instance == nullptr) {
        instance = new CameraPlugin(*api);
    }

    // The Lua API sends `camera.reset` as it loads, which stops a capture that an earlier app of the process left running.
    api->registerHandler("camera.reset", &CameraPlugin::stop, nullptr, instance);
    api->registerHandler("camera.cameras", &CameraPlugin::cameras, nullptr, instance);
    api->registerHandler("camera.start", &CameraPlugin::start, nullptr, instance);
    api->registerHandler("camera.stop", &CameraPlugin::stop, nullptr, instance);
    api->registerHandler("camera.takePhoto", &CameraPlugin::takePhoto, nullptr, instance);
    api->registerHandler("camera.permission", &CameraPlugin::permission, nullptr, instance);
    api->registerHandler("camera.requestPermission", &CameraPlugin::requestPermission, nullptr, instance);
    api->registerPlugin("camera");
    return 0;
}

CameraPlugin::CameraPlugin(const HaylenNativeApi& engine) : api(engine), camera(*this) {}

const HaylenNativeApi& CameraPlugin::getApi() const {
    return api;
}

void CameraPlugin::succeed(std::uint64_t call, const Json& result, std::span<const HaylenNativeBuffer> buffers) const {
    const std::string text = write(result);
    api.resolve(call, 1, text.c_str(), buffers.data(), buffers.size());
}

void CameraPlugin::fail(std::uint64_t call, std::string_view message, std::string_view code) const {
    const std::string text = write({{"message", message}, {"code", code}});
    api.resolve(call, 0, text.c_str(), nullptr, 0);
}

void CameraPlugin::emitStopped(std::string_view message) const {
    const std::string text = write({{"message", message}, {"code", "cameraFailed"}});
    api.emit("camera.stopped", text.c_str(), nullptr, 0, 0);
}

CameraPlugin::Json CameraPlugin::describe(std::string_view id, std::string_view name, std::string_view facing) {
    return {{"id", id}, {"name", name}, {"facing", facing}};
}

std::optional<std::string> CameraPlugin::readText(const Json& params, const char* key) {
    const auto found = params.find(key);
    if (found == params.end() || !found->is_string()) {
        return std::nullopt;
    }
    return found->get<std::string>();
}

int CameraPlugin::readSize(const Json& params, const char* key, int fallback) {
    const auto found = params.find(key);
    if (found == params.end() || !found->is_number()) {
        return fallback;
    }
    const double size = found->get<double>();
    if (size < 0 || size > static_cast<double>(std::numeric_limits<int>::max())) {
        return fallback;
    }
    return static_cast<int>(size);
}

std::string CameraPlugin::write(const Json& value) {
    return value.dump(-1, ' ', false, Json::error_handler_t::replace);
}

void CameraPlugin::cameras(void* user, std::uint64_t call, const char*, const char*, const HaylenNativeBuffer*, std::size_t) {
    static_cast<CameraPlugin*>(user)->camera.cameras(call);
}

// The engine hands JSON text, which the library reads without exceptions, since none may cross the C interface of the engine.
void CameraPlugin::start(void* user, std::uint64_t call, const char*, const char* paramsJson, const HaylenNativeBuffer*, std::size_t) {
    const Json params = Json::parse(paramsJson, nullptr, false);
    static_cast<CameraPlugin*>(user)->camera.start(call, params);
}

void CameraPlugin::stop(void* user, std::uint64_t call, const char*, const char*, const HaylenNativeBuffer*, std::size_t) {
    static_cast<CameraPlugin*>(user)->camera.stop(call);
}

void CameraPlugin::takePhoto(void* user, std::uint64_t call, const char*, const char*, const HaylenNativeBuffer*, std::size_t) {
    static_cast<CameraPlugin*>(user)->camera.takePhoto(call);
}

void CameraPlugin::permission(void* user, std::uint64_t call, const char*, const char*, const HaylenNativeBuffer*, std::size_t) {
    static_cast<CameraPlugin*>(user)->camera.permission(call);
}

void CameraPlugin::requestPermission(void* user, std::uint64_t call, const char*, const char*, const HaylenNativeBuffer*, std::size_t) {
    static_cast<CameraPlugin*>(user)->camera.requestPermission(call);
}
