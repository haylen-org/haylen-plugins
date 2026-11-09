#include "LinuxCameraDevices.hpp"

#include <algorithm>
#include <charconv>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <string_view>
#include <system_error>

#include <linux/videodev2.h>

#include "LinuxDescriptor.hpp"

std::vector<LinuxCameraDevices::Device> LinuxCameraDevices::list() {
    std::vector<Device> devices;
    std::error_code error;
    std::filesystem::directory_iterator folder("/dev", error);
    if (error) {
        return devices;
    }

    constexpr std::string_view prefix = "video";
    for (const std::filesystem::directory_entry& entry : folder) {
        if (devices.size() == kMaxDevices) {
            break;
        }
        const std::string file = entry.path().filename().string();
        if (!file.starts_with(prefix)) {
            continue;
        }
        int number = -1;
        const char* digits = file.data() + prefix.size();
        const char* end = file.data() + file.size();
        const std::from_chars_result parsed = std::from_chars(digits, end, number);
        if (parsed.ec != std::errc() || parsed.ptr != end || digits == end || number < 0) {
            continue;
        }

        const std::string path = "/dev/video" + std::to_string(number);
        const LinuxDescriptor node = LinuxDescriptor::openDevice(path);
        if (!node.isOpen()) {
            continue;
        }
        v4l2_capability capability{};
        const int queried = node.control(VIDIOC_QUERYCAP, &capability);
        const std::uint32_t capabilities = (capability.capabilities & V4L2_CAP_DEVICE_CAPS) != 0 ? capability.device_caps : capability.capabilities;
        if (queried == -1 || (capabilities & V4L2_CAP_VIDEO_CAPTURE) == 0 || (capabilities & V4L2_CAP_STREAMING) == 0) {
            continue;
        }

        const auto* card = reinterpret_cast<const char*>(capability.card);
        devices.push_back({.path = path, .name = std::string(card, strnlen(card, sizeof(capability.card))), .number = number});
    }

    std::ranges::sort(devices, {}, &Device::number);
    return devices;
}
