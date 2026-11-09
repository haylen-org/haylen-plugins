#pragma once

#include <string>
#include <string_view>

#include <windows.h>

// Text between the UTF-16 of Windows and the UTF-8 of the engine, and the codes of COM in messages.
class WindowsText final {
  public:
    [[nodiscard]] static std::string toUtf8(std::wstring_view text);

    // A code of COM as hexadecimal digits, such as "0x80070005".
    [[nodiscard]] static std::string hresult(HRESULT result);
};
