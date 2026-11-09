#pragma once

#import <AVFoundation/AVFoundation.h>

#include <string>

class CameraPlugin;

NS_ASSUME_NONNULL_BEGIN

// The capture of one camera, whose BGRA frames arrive on a dispatch queue of its own, which pushes them into the video stream `camera` and keeps the newest one for a photo.
@interface MacosCapture : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>

@property(nonatomic, readonly) int width;
@property(nonatomic, readonly) int height;

// Opens the camera in its format whose size is the closest to the one the app asks for and starts it, or returns nil with the reason in `error`.
- (nullable instancetype)initWithDevice:(AVCaptureDevice*)device width:(int)width height:(int)height plugin:(const CameraPlugin*)plugin error:(std::string*)error;
- (void)stop;
- (BOOL)hasFrame;

// Encodes the newest frame as a JPEG file with ImageIO, or returns nil before the first frame or when the frame does not encode.
- (nullable NSData*)photoWidth:(int*)width height:(int*)height;

@end

NS_ASSUME_NONNULL_END
