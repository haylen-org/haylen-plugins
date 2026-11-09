#pragma once

#include <string>

// A file descriptor that the library owns and closes, such as the node of a camera.
class LinuxDescriptor final {
  public:
    LinuxDescriptor() = default;
    ~LinuxDescriptor();

    LinuxDescriptor(LinuxDescriptor&& other) noexcept;
    LinuxDescriptor& operator=(LinuxDescriptor&& other) noexcept;
    LinuxDescriptor(const LinuxDescriptor&) = delete;
    LinuxDescriptor& operator=(const LinuxDescriptor&) = delete;

    // Opens a device for reading and writing without blocking, which `isOpen` and `errno` tell the outcome of.
    [[nodiscard]] static LinuxDescriptor openDevice(const std::string& path);

    [[nodiscard]] bool isOpen() const;
    [[nodiscard]] int get() const;

    // Sends a request of the driver, again when a signal interrupts it, and returns what `ioctl` returns.
    int control(unsigned long request, void* argument) const;

  private:
    explicit LinuxDescriptor(int value);

    int descriptor = -1;
};
