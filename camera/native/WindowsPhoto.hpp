#pragma once

#include <cstdint>
#include <optional>
#include <vector>

// The JPEG file of a frame of BGRA pixels, which WIC encodes from the BGR pixels that its encoder takes.
class WindowsPhoto final {
  public:
    [[nodiscard]] static std::optional<std::vector<std::uint8_t>> encode(const std::vector<std::uint8_t>& pixels, int width, int height);
};
