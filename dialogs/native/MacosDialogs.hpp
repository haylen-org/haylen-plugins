#pragma once

#include <cstdint>

#include "DialogsRequest.hpp"
#include "haylen/platform/native/HaylenNative.h"

// The dialogs of macOS, each a sheet of the window of the app: an alert, and the panels of files to open, of a place to save, of a folder and of images. They run on the frame thread, which is the main thread of AppKit, and picked files are files of the Mac, which the app reads where they are. One sheet shows at a time, since AppKit drops a panel that begins while another sheet shows, and the sheets that wait begin in the order the app asked for them.
class MacosDialogs final {
  public:
    static void use(const HaylenNativeApi& value) noexcept;

    // Called on the frame thread.
    static void show(std::uint64_t call, DialogsRequest request);

    // Closes a sheet that the app gave up, or forgets it while it still waits for its turn. Its completion then finds the call gone, so nothing answers it.
    static void cancel(std::uint64_t call);

    // The sheets that show or wait, which the file `MacosDialogs.mm` keeps with their Objective-C objects.
    struct State;
    [[nodiscard]] static State& getState();

  private:
    static const HaylenNativeApi* api;
};
