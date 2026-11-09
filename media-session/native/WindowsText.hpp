#pragma once

#include <string>
#include <string_view>

// Text between the UTF-8 of the engine and the UTF-16 of Windows.
class WindowsText final {
  public:
    [[nodiscard]] static std::wstring toWide(std::string_view text);
    [[nodiscard]] static std::string toUtf8(std::wstring_view text);
};
