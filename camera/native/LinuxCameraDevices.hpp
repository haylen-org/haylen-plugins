#pragma once

#include <cstddef>
#include <string>
#include <vector>

// The capture nodes of Video4Linux, each with its path, which is its id, and its card, which is its name.
class LinuxCameraDevices final {
  public:
    struct Device {
        std::string path;
        std::string name;
        int number = 0;
    };

    // Lists the nodes that capture video frames by streaming, in the order of their numbers, which leaves out the nodes of metadata that drivers add next to each camera.
    [[nodiscard]] static std::vector<Device> list();

  private:
    static constexpr std::size_t kMaxDevices = 64;
};
