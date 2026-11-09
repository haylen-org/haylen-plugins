#include "WindowsCamera.hpp"

#include <optional>
#include <span>
#include <string>
#include <variant>
#include <vector>

#include "CameraPlugin.hpp"
#include "WindowsCameraDevices.hpp"
#include "WindowsCameraPermission.hpp"
#include "WindowsCapture.hpp"
#include "WindowsPhoto.hpp"

WindowsCamera::WindowsCamera(const CameraPlugin& owner) : plugin(owner) {}

WindowsCamera::~WindowsCamera() = default;

void WindowsCamera::cameras(std::uint64_t call) {
    worker.post([this, call] { listCameras(call); });
}

void WindowsCamera::start(std::uint64_t call, const nlohmann::json& params) {
    worker.post([this, call, params] { open(call, params); });
}

void WindowsCamera::stop(std::uint64_t call) {
    worker.post([this, call] { closeCapture(call); });
}

void WindowsCamera::takePhoto(std::uint64_t call) {
    worker.post([this, call] { photograph(call); });
}

void WindowsCamera::permission(std::uint64_t call) {
    worker.post([this, call] { answerPermission(call, WindowsCameraPermission::check()); });
}

void WindowsCamera::requestPermission(std::uint64_t call) {
    worker.post([this, call] { answerPermission(call, WindowsCameraPermission::request()); });
}

void WindowsCamera::answerPermission(std::uint64_t call, const WindowsCameraPermission::Answer& given) const {
    if (given.state == "unsupported") {
        plugin.fail(call, given.message, "unsupported");
        return;
    }
    plugin.succeed(call, given.state);
}

bool WindowsCamera::require(std::uint64_t call) const {
    const WindowsCameraPermission::Answer answer = WindowsCameraPermission::request();
    if (answer.state == "granted" || answer.state == "unknown") {
        return true;
    }
    if (answer.state == "unsupported") {
        plugin.fail(call, answer.message, "unsupported");
        return false;
    }
    plugin.fail(call, CameraPlugin::kRefusal, "denied");
    return false;
}

void WindowsCamera::listCameras(std::uint64_t call) const {
    if (!require(call)) {
        return;
    }
    nlohmann::json list = nlohmann::json::array();
    for (const WindowsCameraDevices::Device& device : WindowsCameraDevices::list()) {
        list.push_back(WindowsCameraDevices::describe(device));
    }
    plugin.succeed(call, list);
}

void WindowsCamera::open(std::uint64_t call, const nlohmann::json& params) {
    if (!require(call)) {
        return;
    }
    const std::optional<WindowsCameraDevices::Device> device = find(call, params);
    if (!device) {
        return;
    }

    capture.reset();
    const int width = CameraPlugin::readSize(params, "width", 640);
    const int height = CameraPlugin::readSize(params, "height", 480);
    WindowsCapture::Opened opened = WindowsCapture::open(plugin, *device, width, height);
    if (const std::string* error = std::get_if<std::string>(&opened)) {
        plugin.fail(call, *error, "cameraFailed");
        return;
    }
    capture = std::move(std::get<std::unique_ptr<WindowsCapture>>(opened));

    nlohmann::json started = WindowsCameraDevices::describe(*device);
    started["width"] = capture->getWidth();
    started["height"] = capture->getHeight();
    plugin.succeed(call, started);
}

std::optional<WindowsCameraDevices::Device> WindowsCamera::find(std::uint64_t call, const nlohmann::json& params) const {
    const std::vector<WindowsCameraDevices::Device> devices = WindowsCameraDevices::list();
    const std::optional<std::string> identifier = CameraPlugin::readText(params, "camera");
    const std::optional<std::string> facing = CameraPlugin::readText(params, "facing");

    if (identifier) {
        for (const WindowsCameraDevices::Device& device : devices) {
            if (device.id == *identifier) {
                return device;
            }
        }
        plugin.fail(call, "This device has no camera with the id \"" + *identifier + "\". The function \"camera.cameras\" lists the cameras.", "noCamera");
        return std::nullopt;
    }

    if (facing) {
        for (const WindowsCameraDevices::Device& device : devices) {
            if (device.facing == *facing) {
                return device;
            }
        }
        plugin.fail(call, "This device has no camera that faces \"" + *facing + "\".", "noCamera");
        return std::nullopt;
    }

    if (devices.empty()) {
        plugin.fail(call, "This device has no camera.", "noCamera");
        return std::nullopt;
    }
    return devices.front();
}

void WindowsCamera::closeCapture(std::uint64_t call) {
    capture.reset();
    plugin.succeed(call, nullptr);
}

void WindowsCamera::photograph(std::uint64_t call) const {
    if (!capture) {
        plugin.fail(call, "The camera is off. Call \"camera.start\" first.", "cameraOff");
        return;
    }
    const std::optional<WindowsCapture::Frame> frame = capture->getNewest();
    if (!frame) {
        plugin.fail(call, "The camera has no frame yet.", "noFrame");
        return;
    }
    const std::optional<std::vector<std::uint8_t>> jpeg = WindowsPhoto::encode(frame->pixels, frame->width, frame->height);
    if (!jpeg) {
        plugin.fail(call, "The frame of the camera did not encode as a JPEG file.", "cameraFailed");
        return;
    }
    const HaylenNativeBuffer buffer{.data = jpeg->data(), .size = jpeg->size()};
    plugin.succeed(call, {{"jpeg", {{"$bytes", 0}}}, {"width", frame->width}, {"height", frame->height}}, std::span(&buffer, 1));
}
