#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <shellapi.h>

#include "LinkOpener.hpp"

// The shell opens the url with the app that its scheme is associated with, and answers a value above 32 when one took it.
void LinkOpener::open(std::string url, std::function<void(Answer)> reply) {
    const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, url.c_str(), -1, nullptr, 0);
    if (length <= 0) {
        reply(Answer::NotAUrl);
        return;
    }
    std::wstring wide(static_cast<std::size_t>(length), L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, url.c_str(), -1, wide.data(), length);

    const auto result = reinterpret_cast<INT_PTR>(ShellExecuteW(nullptr, L"open", wide.c_str(), nullptr, nullptr, SW_SHOWNORMAL));
    reply(result > 32 ? Answer::Opened : Answer::NoApp);
}
