#import "MacosCapture.h"

#import <CoreMedia/CoreMedia.h>
#import <ImageIO/ImageIO.h>

#include <climits>
#include <cstdlib>
#include <memory>
#include <type_traits>

#import "MacosCameraDevices.h"

#include "CameraPlugin.hpp"

@implementation MacosCapture {
    const CameraPlugin* plugin;
    AVCaptureSession* session;
    dispatch_queue_t queue;
    HaylenNativeVideoStream* stream;
    CVPixelBufferRef newest;
    id runtimeErrors;
}

- (nullable instancetype)initWithDevice:(AVCaptureDevice*)device width:(int)width height:(int)height plugin:(const CameraPlugin*)owner error:(std::string*)error {
    self = [super init];
    if (self == nil) {
        return nil;
    }
    plugin = owner;
    const std::string name = device.localizedName.UTF8String;
    NSError* failure = nil;
    AVCaptureDeviceInput* input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&failure];
    if (input == nil) {
        *error = "The camera \"" + name + "\" did not open: " + failure.localizedDescription.UTF8String;
        return nil;
    }

    AVCaptureDeviceFormat* format = nil;
    long best = LONG_MAX;
    for (AVCaptureDeviceFormat* candidate in device.formats) {
        const CMVideoDimensions size = CMVideoFormatDescriptionGetDimensions(candidate.formatDescription);
        const long distance = std::labs(static_cast<long>(size.width) - width) + std::labs(static_cast<long>(size.height) - height);
        if (distance < best) {
            best = distance;
            format = candidate;
        }
    }
    if (format == nil) {
        *error = "The camera \"" + name + "\" offers no format of video.";
        return nil;
    }
    const CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
    _width = dimensions.width;
    _height = dimensions.height;

    session = [[AVCaptureSession alloc] init];
    queue = dispatch_queue_create("com.haylen.plugins.camera.capture", DISPATCH_QUEUE_SERIAL);
    stream = plugin->getApi().openVideoStream("camera", "camera", HAYLEN_NATIVE_PIXELS_BGRA8, 0, 0);
    AVCaptureVideoDataOutput* output = [[AVCaptureVideoDataOutput alloc] init];
    // The session of macOS keeps the size of its preset whatever format the device takes, so the output scales its frames to the size of the format.
    output.videoSettings = @{(NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA), (NSString*)kCVPixelBufferWidthKey : @(_width), (NSString*)kCVPixelBufferHeightKey : @(_height)};
    output.alwaysDiscardsLateVideoFrames = YES;
    [output setSampleBufferDelegate:self queue:queue];

    [session beginConfiguration];
    if (stream == nullptr || ![session canAddInput:input] || ![session canAddOutput:output]) {
        [session commitConfiguration];
        *error = "The camera \"" + name + "\" cannot deliver frames to the app.";
        return nil;
    }
    [session addInput:input];
    [session addOutput:output];
    AVCaptureConnection* connection = [output connectionWithMediaType:AVMediaTypeVideo];
    if (connection.supportsVideoMirroring) {
        connection.automaticallyAdjustsVideoMirroring = NO;
        connection.videoMirrored = [MacosCameraDevices facing:device] == "front";
    }
    [session commitConfiguration];

    // The session applies its preset as it commits, so the format of the device follows the commit and decides the size of the frames.
    if (![device lockForConfiguration:&failure]) {
        *error = "The camera \"" + name + "\" refused its format: " + failure.localizedDescription.UTF8String;
        return nil;
    }
    device.activeFormat = format;
    [device unlockForConfiguration];

    const CameraPlugin* stopped = plugin;
    // clang-format off
    runtimeErrors = [NSNotificationCenter.defaultCenter addObserverForName:AVCaptureSessionRuntimeErrorNotification object:session queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification* notification) {
        NSError* reason = notification.userInfo[AVCaptureSessionErrorKey];
        NSString* text = reason.localizedDescription != nil ? reason.localizedDescription : @"AVFoundation gave no reason";
        stopped->emitStopped(std::string("The camera stopped: ") + text.UTF8String + ".");
    }];
    // clang-format on
    AVCaptureSession* running = session;
    dispatch_async(queue, ^{ [running startRunning]; });
    return self;
}

- (void)stop {
    [NSNotificationCenter.defaultCenter removeObserver:runtimeErrors];
    AVCaptureSession* running = session;
    dispatch_async(queue, ^{ [running stopRunning]; });
}

- (void)dealloc {
    if (newest != nullptr) {
        CVPixelBufferRelease(newest);
    }
}

- (void)captureOutput:(AVCaptureOutput*)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection*)connection {
    CVPixelBufferRef buffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (buffer == nullptr) {
        return;
    }

    CVPixelBufferLockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
    const double timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
    const auto frameWidth = static_cast<int>(CVPixelBufferGetWidth(buffer));
    const auto frameHeight = static_cast<int>(CVPixelBufferGetHeight(buffer));
    const auto stride = static_cast<int>(CVPixelBufferGetBytesPerRow(buffer));
    plugin->getApi().pushVideoFrame(stream, CVPixelBufferGetBaseAddress(buffer), frameWidth, frameHeight, stride, timestamp);
    CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);

    @synchronized(self) {
        if (newest != nullptr) {
            CVPixelBufferRelease(newest);
        }
        newest = CVPixelBufferRetain(buffer);
    }
}

- (BOOL)hasFrame {
    @synchronized(self) {
        return newest != nullptr;
    }
}

- (nullable NSData*)photoWidth:(int*)width height:(int*)height {
    CVPixelBufferRef buffer = nullptr;
    @synchronized(self) {
        buffer = newest != nullptr ? CVPixelBufferRetain(newest) : nullptr;
    }
    if (buffer == nullptr) {
        return nil;
    }
    const std::unique_ptr<std::remove_pointer_t<CVPixelBufferRef>, decltype(&CVPixelBufferRelease)> frame(buffer, &CVPixelBufferRelease);

    CVPixelBufferLockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
    *width = static_cast<int>(CVPixelBufferGetWidth(buffer));
    *height = static_cast<int>(CVPixelBufferGetHeight(buffer));
    const std::unique_ptr<CGColorSpace, decltype(&CGColorSpaceRelease)> space(CGColorSpaceCreateWithName(kCGColorSpaceSRGB), &CGColorSpaceRelease);
    const CGBitmapInfo layout = static_cast<CGBitmapInfo>(kCGImageAlphaPremultipliedFirst) | kCGBitmapByteOrder32Little;
    const std::unique_ptr<CGContext, decltype(&CGContextRelease)> context(CGBitmapContextCreate(CVPixelBufferGetBaseAddress(buffer), static_cast<size_t>(*width), static_cast<size_t>(*height), 8, CVPixelBufferGetBytesPerRow(buffer), space.get(), layout), &CGContextRelease);
    const std::unique_ptr<CGImage, decltype(&CGImageRelease)> image(context != nullptr ? CGBitmapContextCreateImage(context.get()) : nullptr, &CGImageRelease);
    CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
    if (image == nullptr) {
        return nil;
    }

    NSMutableData* jpeg = [NSMutableData data];
    const std::unique_ptr<CGImageDestination, decltype(&CFRelease)> destination(CGImageDestinationCreateWithData((__bridge CFMutableDataRef)jpeg, CFSTR("public.jpeg"), 1, nullptr), &CFRelease);
    if (destination == nullptr) {
        return nil;
    }
    CGImageDestinationAddImage(destination.get(), image.get(), (__bridge CFDictionaryRef) @{(NSString*)kCGImageDestinationLossyCompressionQuality : @0.85});
    const bool written = CGImageDestinationFinalize(destination.get());
    return written ? jpeg : nil;
}

@end
