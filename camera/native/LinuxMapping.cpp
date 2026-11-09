#include "LinuxMapping.hpp"

#include <utility>

#include <sys/mman.h>

LinuxMapping::LinuxMapping(void* address, std::size_t size) : start(address), length(size) {}

LinuxMapping::~LinuxMapping() {
    release();
}

LinuxMapping::LinuxMapping(LinuxMapping&& other) noexcept : start(std::exchange(other.start, nullptr)), length(std::exchange(other.length, 0)) {}

LinuxMapping& LinuxMapping::operator=(LinuxMapping&& other) noexcept {
    if (this != &other) {
        release();
        start = std::exchange(other.start, nullptr);
        length = std::exchange(other.length, 0);
    }
    return *this;
}

const void* LinuxMapping::getStart() const {
    return start;
}

void LinuxMapping::release() {
    if (start != nullptr) {
        munmap(start, length);
    }
}
