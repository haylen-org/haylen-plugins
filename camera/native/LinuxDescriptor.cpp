#include "LinuxDescriptor.hpp"

#include <cerrno>
#include <utility>

#include <fcntl.h>
#include <sys/ioctl.h>
#include <unistd.h>

LinuxDescriptor::LinuxDescriptor(int value) : descriptor(value) {}

LinuxDescriptor::~LinuxDescriptor() {
    if (descriptor != -1) {
        close(descriptor);
    }
}

LinuxDescriptor::LinuxDescriptor(LinuxDescriptor&& other) noexcept : descriptor(std::exchange(other.descriptor, -1)) {}

LinuxDescriptor& LinuxDescriptor::operator=(LinuxDescriptor&& other) noexcept {
    if (this != &other) {
        if (descriptor != -1) {
            close(descriptor);
        }
        descriptor = std::exchange(other.descriptor, -1);
    }
    return *this;
}

LinuxDescriptor LinuxDescriptor::openDevice(const std::string& path) {
    return LinuxDescriptor(open(path.c_str(), O_RDWR | O_NONBLOCK | O_CLOEXEC));
}

bool LinuxDescriptor::isOpen() const {
    return descriptor != -1;
}

int LinuxDescriptor::get() const {
    return descriptor;
}

int LinuxDescriptor::control(unsigned long request, void* argument) const {
    int result = ioctl(descriptor, request, argument);
    while (result == -1 && errno == EINTR) {
        result = ioctl(descriptor, request, argument);
    }
    return result;
}
