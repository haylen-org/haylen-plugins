#import "MacosCameraDevices.h"

#include <optional>

#include "CameraPlugin.hpp"

@implementation MacosCameraDevices

+ (NSArray<AVCaptureDevice*>*)devices {
    NSArray<AVCaptureDeviceType>* types = nil;
    if (@available(macOS 14.0, *)) {
        types = @[ AVCaptureDeviceTypeBuiltInWideAngleCamera, AVCaptureDeviceTypeExternal, AVCaptureDeviceTypeContinuityCamera ];
    } else {
        types = @[ AVCaptureDeviceTypeBuiltInWideAngleCamera, AVCaptureDeviceTypeExternalUnknown ];
    }
    AVCaptureDeviceDiscoverySession* discovery = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:types mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];
    return discovery.devices;
}

+ (std::string)facing:(AVCaptureDevice*)device {
    if (device.position == AVCaptureDevicePositionFront || [device.deviceType isEqualToString:AVCaptureDeviceTypeBuiltInWideAngleCamera]) {
        return "front";
    }
    return device.position == AVCaptureDevicePositionBack ? "back" : "external";
}

+ (nlohmann::json)describe:(AVCaptureDevice*)device {
    return CameraPlugin::describe(device.uniqueID.UTF8String, device.localizedName.UTF8String, [self facing:device]);
}

+ (nullable AVCaptureDevice*)find:(const nlohmann::json&)params failure:(std::string*)failure {
    const std::optional<std::string> identifier = CameraPlugin::readText(params, "camera");
    const std::optional<std::string> facing = CameraPlugin::readText(params, "facing");
    NSArray<AVCaptureDevice*>* devices = [self devices];

    if (identifier) {
        for (AVCaptureDevice* device in devices) {
            if (*identifier == device.uniqueID.UTF8String) {
                return device;
            }
        }
        *failure = "This device has no camera with the id \"" + *identifier + "\". The function \"camera.cameras\" lists the cameras.";
        return nil;
    }

    if (facing) {
        for (AVCaptureDevice* device in devices) {
            if ([self facing:device] == *facing) {
                return device;
            }
        }
        *failure = "This device has no camera that faces \"" + *facing + "\".";
        return nil;
    }

    AVCaptureDevice* device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (device == nil) {
        *failure = "This device has no camera.";
    }
    return device;
}

+ (std::string)stateOf:(AVAuthorizationStatus)status {
    switch (status) {
    case AVAuthorizationStatusNotDetermined:
        return "prompt";
    case AVAuthorizationStatusAuthorized:
        return "granted";
    case AVAuthorizationStatusDenied:
    case AVAuthorizationStatusRestricted:
        return "denied";
    }
    return "unknown";
}

@end
