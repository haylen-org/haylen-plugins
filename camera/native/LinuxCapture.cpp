#include "LinuxCapture.hpp"

#include <algorithm>
#include <cerrno>
#include <climits>
#include <cstdlib>
#include <system_error>
#include <utility>

#include <linux/videodev2.h>
#include <poll.h>
#include <sys/mman.h>

#include "CameraPlugin.hpp"

LinuxCapture::Opened LinuxCapture::open(const CameraPlugin& plugin, const LinuxCameraDevices::Device& camera, int wantedWidth, int wantedHeight) {
    LinuxDescriptor node = LinuxDescriptor::openDevice(camera.path);
    if (!node.isOpen()) {
        const int reason = errno;
        if (reason == EACCES) {
            return "The camera \"" + camera.name + "\" did not open, since the person who runs the app has no access to \"" + camera.path + "\", such as a member of the group \"video\" has.";
        }
        return "The camera \"" + camera.name + "\" did not open: " + std::generic_category().message(reason) + ".";
    }

    std::unique_ptr<LinuxCapture> capture(new LinuxCapture(plugin, std::move(node), camera.name));
    std::string error = capture->configure(wantedWidth, wantedHeight);
    if (!error.empty()) {
        return error;
    }
    return Opened(std::move(capture));
}

LinuxCapture::LinuxCapture(const CameraPlugin& owner, LinuxDescriptor node, std::string cameraName) : plugin(owner), device(std::move(node)), name(std::move(cameraName)) {}

LinuxCapture::~LinuxCapture() {
    running = false;
    if (thread.joinable()) {
        thread.join();
    }
    if (streaming) {
        v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        device.control(VIDIOC_STREAMOFF, &type);
    }
}

int LinuxCapture::getWidth() const {
    return width;
}

int LinuxCapture::getHeight() const {
    return height;
}

std::string LinuxCapture::configure(int wantedWidth, int wantedHeight) {
    bool hasFormat = false;
    bool hasYuyv = false;
    v4l2_fmtdesc description{};
    description.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    for (description.index = 0; device.control(VIDIOC_ENUM_FMT, &description) == 0; ++description.index) {
        hasFormat = true;
        hasYuyv = hasYuyv || description.pixelformat == V4L2_PIX_FMT_YUYV;
    }
    if (!hasYuyv && hasFormat) {
        return "The camera \"" + name + "\" offers only compressed frames, such as MJPEG, and the plugin reads the uncompressed frames of YUYV.";
    }
    if (!hasYuyv) {
        return "The camera \"" + name + "\" offers no format of video.";
    }

    int frameWidth = wantedWidth;
    int frameHeight = wantedHeight;
    closestSize(device, frameWidth, frameHeight);
    v4l2_format format{};
    format.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    format.fmt.pix.width = static_cast<std::uint32_t>(frameWidth);
    format.fmt.pix.height = static_cast<std::uint32_t>(frameHeight);
    format.fmt.pix.pixelformat = V4L2_PIX_FMT_YUYV;
    format.fmt.pix.field = V4L2_FIELD_NONE;
    if (device.control(VIDIOC_S_FMT, &format) == -1 || format.fmt.pix.pixelformat != V4L2_PIX_FMT_YUYV) {
        return "The camera \"" + name + "\" refused the frames of YUYV of " + std::to_string(frameWidth) + "x" + std::to_string(frameHeight) + ".";
    }
    width = static_cast<int>(format.fmt.pix.width);
    height = static_cast<int>(format.fmt.pix.height);
    stride = format.fmt.pix.bytesperline >= format.fmt.pix.width * 2 ? static_cast<int>(format.fmt.pix.bytesperline) : width * 2;

    v4l2_requestbuffers request{};
    request.count = kBufferCount;
    request.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    request.memory = V4L2_MEMORY_MMAP;
    if (device.control(VIDIOC_REQBUFS, &request) == -1 || request.count == 0) {
        return "The camera \"" + name + "\" gave the plugin no buffers of frames.";
    }

    for (unsigned index = 0; index < request.count && index < kBufferCount; ++index) {
        v4l2_buffer buffer{};
        buffer.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        buffer.memory = V4L2_MEMORY_MMAP;
        buffer.index = index;
        if (device.control(VIDIOC_QUERYBUF, &buffer) == -1) {
            break;
        }
        void* start = mmap(nullptr, buffer.length, PROT_READ | PROT_WRITE, MAP_SHARED, device.get(), buffer.m.offset);
        if (start == MAP_FAILED) {
            break;
        }
        LinuxMapping mapping(start, buffer.length);
        if (device.control(VIDIOC_QBUF, &buffer) == -1) {
            break;
        }
        buffers.push_back(std::move(mapping));
    }

    pixels.resize(static_cast<std::size_t>(width) * static_cast<std::size_t>(height) * 4);
    stream = plugin.getApi().openVideoStream("camera", "camera", HAYLEN_NATIVE_PIXELS_RGBA8, 0, 0);
    v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    if (buffers.size() != request.count || stream == nullptr || device.control(VIDIOC_STREAMON, &type) == -1) {
        return "The camera \"" + name + "\" cannot deliver frames to the app.";
    }
    streaming = true;

    running = true;
    try {
        thread = std::thread(&LinuxCapture::readFrames, this);
    } catch (const std::system_error&) {
        running = false;
        return "The camera \"" + name + "\" got no thread to read its frames on.";
    }
    return {};
}

void LinuxCapture::closestSize(const LinuxDescriptor& node, int& frameWidth, int& frameHeight) {
    const int wantedWidth = frameWidth;
    const int wantedHeight = frameHeight;
    long best = LONG_MAX;
    v4l2_frmsizeenum size{};
    size.pixel_format = V4L2_PIX_FMT_YUYV;

    for (size.index = 0; node.control(VIDIOC_ENUM_FRAMESIZES, &size) == 0; ++size.index) {
        if (size.type != V4L2_FRMSIZE_TYPE_DISCRETE) {
            const v4l2_frmsize_stepwise& range = size.stepwise;
            const int stepWidth = range.step_width > 0 ? static_cast<int>(range.step_width) : 1;
            const int stepHeight = range.step_height > 0 ? static_cast<int>(range.step_height) : 1;
            const int minimumWidth = static_cast<int>(range.min_width);
            const int minimumHeight = static_cast<int>(range.min_height);
            const int clampedWidth = std::clamp(wantedWidth, minimumWidth, std::max(minimumWidth, static_cast<int>(range.max_width)));
            const int clampedHeight = std::clamp(wantedHeight, minimumHeight, std::max(minimumHeight, static_cast<int>(range.max_height)));
            frameWidth = minimumWidth + (clampedWidth - minimumWidth) / stepWidth * stepWidth;
            frameHeight = minimumHeight + (clampedHeight - minimumHeight) / stepHeight * stepHeight;
            return;
        }

        const long distance = std::labs(static_cast<long>(size.discrete.width) - wantedWidth) + std::labs(static_cast<long>(size.discrete.height) - wantedHeight);
        if (distance < best) {
            best = distance;
            frameWidth = static_cast<int>(size.discrete.width);
            frameHeight = static_cast<int>(size.discrete.height);
        }
    }
}

std::uint8_t LinuxCapture::clamp(int value) {
    return static_cast<std::uint8_t>(std::clamp(value, 0, 255));
}

void LinuxCapture::convert(const std::uint8_t* frame) {
    std::uint8_t* target = pixels.data();
    for (int row = 0; row < height; ++row) {
        const std::uint8_t* source = frame + static_cast<std::size_t>(row) * static_cast<std::size_t>(stride);
        for (int column = 0; column + 1 < width; column += 2) {
            const int u = source[1] - 128;
            const int v = source[3] - 128;
            for (int half = 0; half < 2; ++half) {
                const int luma = 298 * (source[half * 2] - 16);
                target[0] = clamp((luma + 409 * v + 128) >> 8);
                target[1] = clamp((luma - 100 * u - 208 * v + 128) >> 8);
                target[2] = clamp((luma + 516 * u + 128) >> 8);
                target[3] = 255;
                target += 4;
            }
            source += 4;
        }
    }
}

void LinuxCapture::readFrames() {
    while (running) {
        pollfd ready{.fd = device.get(), .events = POLLIN, .revents = 0};
        const int polled = poll(&ready, 1, kPollMilliseconds);
        if (polled == 0 || (polled == -1 && errno == EINTR)) {
            continue;
        }

        v4l2_buffer buffer{};
        buffer.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        buffer.memory = V4L2_MEMORY_MMAP;
        const bool broken = polled == -1 || (ready.revents & (POLLERR | POLLHUP | POLLNVAL)) != 0;
        bool dequeued = false;
        if (!broken) {
            dequeued = device.control(VIDIOC_DQBUF, &buffer) == 0;
            if (!dequeued && errno == EAGAIN) {
                continue;
            }
        }
        if (!dequeued) {
            plugin.emitStopped("The camera \"" + name + "\" stopped, such as when it was unplugged.");
            return;
        }

        const auto frameSize = static_cast<std::uint32_t>(stride) * static_cast<std::uint32_t>(height);
        if (buffer.index < buffers.size() && buffer.bytesused >= frameSize) {
            convert(static_cast<const std::uint8_t*>(buffers[buffer.index].getStart()));
            const double timestamp = static_cast<double>(buffer.timestamp.tv_sec) + static_cast<double>(buffer.timestamp.tv_usec) / 1e6;
            plugin.getApi().pushVideoFrame(stream, pixels.data(), width, height, width * 4, timestamp);
        }
        device.control(VIDIOC_QBUF, &buffer);
    }
}
