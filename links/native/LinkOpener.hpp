#pragma once

#include <functional>
#include <string>

// Opens a url with the app that the system picks for it: through the workspace of AppKit on macOS, the shell on Windows and the command `xdg-open` on Linux. The file `LinkOpener.mm` serves macOS, `LinkOpenerWindows.cpp` Windows and `LinkOpenerLinux.cpp` Linux.
class LinkOpener final {
  public:
    enum class Answer { Opened, NotAUrl, NoApp, MissingCommand, NoThread };

    // Opens the url, a UTF-8 text, and calls `reply` once with what the system answered, on the thread of the call or, on Linux, on a thread of its own, so the frame thread never waits for `xdg-open`.
    static void open(std::string url, std::function<void(Answer)> reply);
};
