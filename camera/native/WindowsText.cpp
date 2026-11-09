#include "WindowsText.hpp"

#include <charconv>
#include <cstdint>

std::string WindowsText::toUtf8(std::wstring_view text) {
    if (text.empty()) {
        return {};
    }
    const int length = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
    std::string utf8(static_cast<std::size_t>(length), '\0');
    WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), utf8.data(), length, nullptr, nullptr);
    return utf8;
}

std::string WindowsText::hresult(HRESULT result) {
    char digits[16];
    const std::to_chars_result written = std::to_chars(digits, digits + sizeof(digits), static_cast<std::uint32_t>(result), 16);
    return "0x" + std::string(digits, written.ptr);
}
