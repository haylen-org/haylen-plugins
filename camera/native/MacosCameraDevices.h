#pragma once

#import <AVFoundation/AVFoundation.h>

#include <string>

#include <nlohmann/json.hpp>

NS_ASSUME_NONNULL_BEGIN

// The cameras of AVFoundation that the desktop player lists and starts, the built-in camera, USB cameras and, from macOS 14, the Continuity Camera of an iPhone, and the state of their permission.
@interface MacosCameraDevices : NSObject

+ (NSArray<AVCaptureDevice*>*)devices;

// The built-in camera of a Mac faces the person, and every other camera faces neither way.
+ (std::string)facing:(AVCaptureDevice*)device;

+ (nlohmann::json)describe:(AVCaptureDevice*)device;

// Finds the camera that the parameters name by its id, by the way it faces, or the default camera of the system, or returns nil with the reason in `failure`.
+ (nullable AVCaptureDevice*)find:(const nlohmann::json&)params failure:(std::string*)failure;

// The state of the permission `camera` that an authorization of AVFoundation gives.
+ (std::string)stateOf:(AVAuthorizationStatus)status;

@end

NS_ASSUME_NONNULL_END
