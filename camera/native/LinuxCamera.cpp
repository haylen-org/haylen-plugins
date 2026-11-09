#include "LinuxCamera.hpp"

#include <string>
#include <variant>

#include "CameraPlugin.hpp"
#include "LinuxCapture.hpp"

LinuxCamera::LinuxCamera(const CameraPlugin& owner) : plugin(owner) {}

LinuxCamera::~LinuxCamera() = default;

void LinuxCamera::cameras(std::uint64_t call) const {
    nlohmann::json list = nlohmann::json::array();
    for (const LinuxCameraDevices::Device& device : LinuxCameraDevices::list()) {
        list.push_back(describe(device));
    }
    plugin.succeed(call, list);
}

void LinuxCamera::start(std::uint64_t call, const nlohmann::json& params) {
    const std::optional<LinuxCameraDevices::Device> camera = find(call, params);
    if (!camera) {
        return;
    }

    capture.reset();
    const int width = CameraPlugin::readSize(params, "width", 640);
    const int height = CameraPlugin::readSize(params, "height", 480);
    LinuxCapture::Opened opened = LinuxCapture::open(plugin, *camera, width, height);
    if (const std::string* error = std::get_if<std::string>(&opened)) {
        plugin.fail(call, *error, "cameraFailed");
        return;
    }
    capture = std::move(std::get<std::unique_ptr<LinuxCapture>>(opened));

    nlohmann::json started = describe(*camera);
    started["width"] = capture->getWidth();
    started["height"] = capture->getHeight();
    plugin.succeed(call, started);
}

void LinuxCamera::stop(std::uint64_t call) {
    capture.reset();
    plugin.succeed(call, nullptr);
}

void LinuxCamera::takePhoto(std::uint64_t call) const {
    plugin.fail(call, "Linux offers no JPEG encoder in its system API, so the plugin takes no photos there. Draw the texture of \"camera.stream()\" into a render target and keep it with \"graphics.readTarget\" and \"image:encodePng\".", "unsupported");
}

void LinuxCamera::permission(std::uint64_t call) const {
    plugin.succeed(call, "granted");
}

// A request shows no prompt, since the permission is granted.
void LinuxCamera::requestPermission(std::uint64_t call) const {
    permission(call);
}

std::optional<LinuxCameraDevices::Device> LinuxCamera::find(std::uint64_t call, const nlohmann::json& params) const {
    const std::vector<LinuxCameraDevices::Device> devices = LinuxCameraDevices::list();
    const std::optional<std::string> identifier = CameraPlugin::readText(params, "camera");
    const std::optional<std::string> facing = CameraPlugin::readText(params, "facing");

    if (identifier) {
        for (const LinuxCameraDevices::Device& device : devices) {
            if (device.path == *identifier) {
                return device;
            }
        }
        plugin.fail(call, "This device has no camera with the id \"" + *identifier + "\". The function \"camera.cameras\" lists the cameras.", "noCamera");
        return std::nullopt;
    }

    if (facing && *facing != "external") {
        plugin.fail(call, "This device has no camera that faces \"" + *facing + "\".", "noCamera");
        return std::nullopt;
    }
    if (devices.empty()) {
        plugin.fail(call, facing ? "This device has no camera that faces \"external\"." : "This device has no camera.", "noCamera");
        return std::nullopt;
    }
    return devices.front();
}

nlohmann::json LinuxCamera::describe(const LinuxCameraDevices::Device& device) {
    return CameraPlugin::describe(device.path, device.name, "external");
}
