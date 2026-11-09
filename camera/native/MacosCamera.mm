#include "MacosCamera.hpp"

#import <AVFoundation/AVFoundation.h>

#include <span>
#include <string>

#import "MacosCameraDevices.h"
#import "MacosCapture.h"

#include "CameraPlugin.hpp"

struct MacosCamera::Session {
    MacosCapture* capture = nil;
};

MacosCamera::MacosCamera(const CameraPlugin& owner) : plugin(owner), session(std::make_unique<Session>()) {}

MacosCamera::~MacosCamera() = default;

void MacosCamera::cameras(std::uint64_t call) {
    require(call, [this, call] { listCameras(call); });
}

void MacosCamera::start(std::uint64_t call, const nlohmann::json& params) {
    require(call, [this, call, params] { open(call, params); });
}

void MacosCamera::stop(std::uint64_t call) {
    stopCapture();
    plugin.succeed(call, nullptr);
}

void MacosCamera::takePhoto(std::uint64_t call) {
    MacosCapture* capture = session->capture;
    if (capture == nil) {
        plugin.fail(call, "The camera is off. Call \"camera.start\" first.", "cameraOff");
        return;
    }
    if (![capture hasFrame]) {
        plugin.fail(call, "The camera has no frame yet.", "noFrame");
        return;
    }

    int width = 0;
    int height = 0;
    NSData* jpeg = [capture photoWidth:&width height:&height];
    if (jpeg == nil) {
        plugin.fail(call, "The frame of the camera did not encode as a JPEG file.", "cameraFailed");
        return;
    }
    const HaylenNativeBuffer buffer{.data = jpeg.bytes, .size = jpeg.length};
    plugin.succeed(call, {{"jpeg", {{"$bytes", 0}}}, {"width", width}, {"height", height}}, std::span(&buffer, 1));
}

// Reads the state of the permission `camera` without asking, the state that macOS keeps for the app that started the player.
void MacosCamera::permission(std::uint64_t call) const {
    const AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    plugin.succeed(call, [MacosCameraDevices stateOf:status]);
}

void MacosCamera::requestPermission(std::uint64_t call) const {
    const AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status != AVAuthorizationStatusNotDetermined) {
        plugin.succeed(call, [MacosCameraDevices stateOf:status]);
        return;
    }
    const CameraPlugin& answering = plugin;
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL allowed) { answering.succeed(call, allowed ? "granted" : "denied"); }];
}

void MacosCamera::require(std::uint64_t call, std::function<void()> granted) const {
    const AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusAuthorized) {
        granted();
        return;
    }
    if (status != AVAuthorizationStatusNotDetermined) {
        plugin.fail(call, CameraPlugin::kRefusal, "denied");
        return;
    }

    const CameraPlugin& refusing = plugin;
    dispatch_block_t allowedBlock = ^{ granted(); };
    dispatch_block_t refusedBlock = ^{ refusing.fail(call, CameraPlugin::kRefusal, "denied"); };
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL allowed) { dispatch_async(dispatch_get_main_queue(), allowed ? allowedBlock : refusedBlock); }];
}

void MacosCamera::listCameras(std::uint64_t call) const {
    nlohmann::json cameras = nlohmann::json::array();
    for (AVCaptureDevice* device in [MacosCameraDevices devices]) {
        cameras.push_back([MacosCameraDevices describe:device]);
    }
    plugin.succeed(call, cameras);
}

void MacosCamera::open(std::uint64_t call, const nlohmann::json& params) {
    std::string failure;
    AVCaptureDevice* device = [MacosCameraDevices find:params failure:&failure];
    if (device == nil) {
        plugin.fail(call, failure, "noCamera");
        return;
    }

    stopCapture();
    std::string error;
    const int width = CameraPlugin::readSize(params, "width", 0);
    const int height = CameraPlugin::readSize(params, "height", 0);
    MacosCapture* capture = [[MacosCapture alloc] initWithDevice:device width:width height:height plugin:&plugin error:&error];
    if (capture == nil) {
        plugin.fail(call, error, "cameraFailed");
        return;
    }
    session->capture = capture;

    nlohmann::json started = [MacosCameraDevices describe:device];
    started["width"] = capture.width;
    started["height"] = capture.height;
    plugin.succeed(call, started);
}

void MacosCamera::stopCapture() {
    [session->capture stop];
    session->capture = nil;
}
