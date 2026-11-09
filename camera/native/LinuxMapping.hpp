#pragma once

#include <cstddef>

// A buffer of a driver that the library maps into its memory and unmaps when it ends.
class LinuxMapping final {
  public:
    LinuxMapping(void* start, std::size_t length);
    ~LinuxMapping();

    LinuxMapping(LinuxMapping&& other) noexcept;
    LinuxMapping& operator=(LinuxMapping&& other) noexcept;
    LinuxMapping(const LinuxMapping&) = delete;
    LinuxMapping& operator=(const LinuxMapping&) = delete;

    [[nodiscard]] const void* getStart() const;

  private:
    void release();

    void* start;
    std::size_t length;
};
