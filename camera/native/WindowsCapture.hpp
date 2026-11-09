#pragma once

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <variant>
#include <vector>

#include <windows.h>

#include <mfidl.h>
#include <mfreadwrite.h>
#include <wrl/client.h>

#include "WindowsCameraDevices.hpp"
#include "haylen/platform/native/HaylenNative.h"

class CameraPlugin;

// The capture of one camera through a source reader of Media Foundation, whose video processor turns the frames of the camera into RGB32, the BGRA bytes of Windows. A thread of its own reads the frames, copies them top down with an opaque alpha, pushes them into the video stream `camera` and keeps the newest one for a photo.
class WindowsCapture final {
  public:
    struct Frame {
        std::vector<std::uint8_t> pixels;
        int width = 0;
        int height = 0;
    };

    using Opened = std::variant<std::unique_ptr<WindowsCapture>, std::string>;

    // Opens the camera in the format whose size is the closest to the one the app asked for, or returns the reason it cannot.
    [[nodiscard]] static Opened open(const CameraPlugin& plugin, const WindowsCameraDevices::Device& device, int wantedWidth, int wantedHeight);

    // The thread sees the stop after the frame it waits for, which a camera that runs delivers within a fraction of a second, and a camera that went away fails at once, so the source shuts down only once nothing reads from it.
    ~WindowsCapture();

    WindowsCapture(const WindowsCapture&) = delete;
    WindowsCapture& operator=(const WindowsCapture&) = delete;

    [[nodiscard]] int getWidth() const;
    [[nodiscard]] int getHeight() const;
    [[nodiscard]] std::optional<Frame> getNewest();

  private:
    WindowsCapture(const CameraPlugin& owner, Microsoft::WRL::ComPtr<IMFMediaSource> mediaSource, Microsoft::WRL::ComPtr<IMFSourceReader> sourceReader, HaylenNativeVideoStream* videoStream, int frameWidth, int frameHeight, LONG frameStride);

    // The distance between the rows of a frame, negative for a bottom-up frame, as the current type of the reader gives it, or the one of RGB32 for a type that leaves it out.
    static LONG readStride(IMFSourceReader* sourceReader, UINT32 frameWidth);
    static Microsoft::WRL::ComPtr<IMFMediaType> closestType(IMFSourceReader* sourceReader, int wantedWidth, int wantedHeight);

    void run();

    // Copies the frame row by row from its first scanline, which a bottom-up buffer holds last, and makes every pixel opaque, since RGB32 leaves the fourth byte undefined. A buffer shorter than the frame is dropped.
    bool copy(IMFSample* sample, std::vector<std::uint8_t>& pixels) const;

    const CameraPlugin& plugin;
    Microsoft::WRL::ComPtr<IMFMediaSource> source;
    Microsoft::WRL::ComPtr<IMFSourceReader> reader;
    HaylenNativeVideoStream* video;
    const int width;
    const int height;
    const LONG stride;
    std::atomic<bool> stopping = false;
    std::mutex mutex;
    Frame newest;
    std::thread thread;
};
