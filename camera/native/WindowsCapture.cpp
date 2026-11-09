#include "WindowsCapture.hpp"

#include <climits>
#include <cstdlib>
#include <cstring>
#include <utility>

#include <mfapi.h>
#include <roapi.h>

#include "CameraPlugin.hpp"
#include "WindowsText.hpp"

using Microsoft::WRL::ComPtr;

WindowsCapture::Opened WindowsCapture::open(const CameraPlugin& plugin, const WindowsCameraDevices::Device& device, int wantedWidth, int wantedHeight) {
    ComPtr<IMFMediaSource> mediaSource;
    if (const HRESULT result = device.activate->ActivateObject(IID_PPV_ARGS(&mediaSource)); FAILED(result)) {
        return "The camera \"" + device.name + "\" did not open, and Media Foundation answered " + WindowsText::hresult(result) + ".";
    }

    ComPtr<IMFAttributes> attributes;
    ComPtr<IMFSourceReader> sourceReader;
    MFCreateAttributes(&attributes, 1);
    attributes->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE);
    if (const HRESULT result = MFCreateSourceReaderFromMediaSource(mediaSource.Get(), attributes.Get(), &sourceReader); FAILED(result)) {
        mediaSource->Shutdown();
        return "The camera \"" + device.name + "\" cannot deliver frames to the app, and Media Foundation answered " + WindowsText::hresult(result) + ".";
    }

    const ComPtr<IMFMediaType> native = closestType(sourceReader.Get(), wantedWidth, wantedHeight);
    UINT32 frameWidth = 0;
    UINT32 frameHeight = 0;
    const auto firstVideo = static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM);
    if (!native || FAILED(sourceReader->SetCurrentMediaType(firstVideo, nullptr, native.Get())) || FAILED(MFGetAttributeSize(native.Get(), MF_MT_FRAME_SIZE, &frameWidth, &frameHeight))) {
        mediaSource->Shutdown();
        return "The camera \"" + device.name + "\" offers no format of video.";
    }

    ComPtr<IMFMediaType> output;
    MFCreateMediaType(&output);
    output->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    output->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
    MFSetAttributeSize(output.Get(), MF_MT_FRAME_SIZE, frameWidth, frameHeight);
    if (const HRESULT result = sourceReader->SetCurrentMediaType(firstVideo, nullptr, output.Get()); FAILED(result)) {
        mediaSource->Shutdown();
        return "The camera \"" + device.name + "\" cannot turn its frames into pixels, and Media Foundation answered " + WindowsText::hresult(result) + ".";
    }

    HaylenNativeVideoStream* videoStream = plugin.getApi().openVideoStream("camera", "camera", HAYLEN_NATIVE_PIXELS_BGRA8, 0, 0);
    if (videoStream == nullptr) {
        mediaSource->Shutdown();
        return std::string("The video stream \"camera\" did not open.");
    }
    const LONG frameStride = readStride(sourceReader.Get(), frameWidth);
    std::unique_ptr<WindowsCapture> capture(new WindowsCapture(plugin, mediaSource, sourceReader, videoStream, static_cast<int>(frameWidth), static_cast<int>(frameHeight), frameStride));
    return Opened(std::move(capture));
}

WindowsCapture::WindowsCapture(const CameraPlugin& owner, ComPtr<IMFMediaSource> mediaSource, ComPtr<IMFSourceReader> sourceReader, HaylenNativeVideoStream* videoStream, int frameWidth, int frameHeight, LONG frameStride) : plugin(owner), source(std::move(mediaSource)), reader(std::move(sourceReader)), video(videoStream), width(frameWidth), height(frameHeight), stride(frameStride), thread(&WindowsCapture::run, this) {}

WindowsCapture::~WindowsCapture() {
    stopping = true;
    thread.join();
    source->Shutdown();
}

int WindowsCapture::getWidth() const {
    return width;
}

int WindowsCapture::getHeight() const {
    return height;
}

std::optional<WindowsCapture::Frame> WindowsCapture::getNewest() {
    const std::lock_guard<std::mutex> guard(mutex);
    if (newest.pixels.empty()) {
        return std::nullopt;
    }
    return newest;
}

LONG WindowsCapture::readStride(IMFSourceReader* sourceReader, UINT32 frameWidth) {
    ComPtr<IMFMediaType> current;
    UINT32 defaultStride = 0;
    const auto firstVideo = static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM);
    if (SUCCEEDED(sourceReader->GetCurrentMediaType(firstVideo, &current)) && SUCCEEDED(current->GetUINT32(MF_MT_DEFAULT_STRIDE, &defaultStride))) {
        return static_cast<LONG>(defaultStride);
    }
    LONG computed = 0;
    MFGetStrideForBitmapInfoHeader(MFVideoFormat_RGB32.Data1, frameWidth, &computed);
    return computed;
}

ComPtr<IMFMediaType> WindowsCapture::closestType(IMFSourceReader* sourceReader, int wantedWidth, int wantedHeight) {
    ComPtr<IMFMediaType> best;
    long bestDistance = LONG_MAX;
    const auto firstVideo = static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM);
    for (DWORD index = 0;; ++index) {
        ComPtr<IMFMediaType> type;
        if (FAILED(sourceReader->GetNativeMediaType(firstVideo, index, &type))) {
            return best;
        }
        UINT32 typeWidth = 0;
        UINT32 typeHeight = 0;
        if (FAILED(MFGetAttributeSize(type.Get(), MF_MT_FRAME_SIZE, &typeWidth, &typeHeight))) {
            continue;
        }
        const long distance = std::labs(static_cast<long>(typeWidth) - wantedWidth) + std::labs(static_cast<long>(typeHeight) - wantedHeight);
        if (distance < bestDistance) {
            bestDistance = distance;
            best = type;
        }
    }
}

void WindowsCapture::run() {
    RoInitialize(RO_INIT_MULTITHREADED);
    std::vector<std::uint8_t> pixels;
    const auto firstVideo = static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM);
    while (!stopping) {
        DWORD flags = 0;
        LONGLONG timestamp = 0;
        ComPtr<IMFSample> sample;
        const HRESULT result = reader->ReadSample(firstVideo, 0, nullptr, &flags, &timestamp, &sample);
        if (stopping) {
            break;
        }
        if (FAILED(result) || (flags & (MF_SOURCE_READERF_ERROR | MF_SOURCE_READERF_ENDOFSTREAM)) != 0) {
            plugin.emitStopped("The camera went away, such as when the person unplugged it or another app took it.");
            break;
        }
        if (!sample || !copy(sample.Get(), pixels)) {
            continue;
        }

        plugin.getApi().pushVideoFrame(video, pixels.data(), width, height, width * 4, static_cast<double>(timestamp) / 1e7);
        const std::lock_guard<std::mutex> guard(mutex);
        newest.pixels = pixels;
        newest.width = width;
        newest.height = height;
    }
    RoUninitialize();
}

bool WindowsCapture::copy(IMFSample* sample, std::vector<std::uint8_t>& pixels) const {
    ComPtr<IMFMediaBuffer> buffer;
    BYTE* data = nullptr;
    DWORD length = 0;
    const std::size_t row = static_cast<std::size_t>(width) * 4;
    const auto pitch = static_cast<std::size_t>(std::labs(stride));
    if (FAILED(sample->ConvertToContiguousBuffer(&buffer)) || FAILED(buffer->Lock(&data, nullptr, &length))) {
        return false;
    }
    if (length < pitch * static_cast<std::size_t>(height - 1) + row) {
        buffer->Unlock();
        return false;
    }

    const BYTE* first = stride < 0 ? data + pitch * static_cast<std::size_t>(height - 1) : data;
    pixels.resize(row * static_cast<std::size_t>(height));
    for (int line = 0; line < height; ++line) {
        std::uint8_t* target = pixels.data() + row * static_cast<std::size_t>(line);
        std::memcpy(target, first + static_cast<std::ptrdiff_t>(stride) * line, row);
        for (std::size_t alpha = 3; alpha < row; alpha += 4) {
            target[alpha] = 0xFF;
        }
    }
    buffer->Unlock();
    return true;
}
