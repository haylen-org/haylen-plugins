#pragma once

#include <cstdint>
#include <string>

#include "ShareRequest.hpp"
#include "haylen/platform/native/HaylenNative.h"

// The share of macOS: the sharing service picker of AppKit over the window of the app, as the Apple part shows it in the macOS app. The frame thread of the app is the main thread of AppKit, so the picker shows there. The files of a share are written into a folder of their own in the temporary folder, emptied before every share.
class MacosShare final {
  public:
    static void use(const HaylenNativeApi& value) noexcept;

    // Shows the picker over the anchor of the share, or over the middle of the window, on the frame thread.
    static void show(std::uint64_t call, const HaylenNativeWindow& window, ShareRequest request);

    // Ends the share that shows once the person picked a service, or none, which uncovers the app and answers its call.
    static void end(bool shared, const std::string& target);

    // The picker that shows, which the file `MacosShare.mm` keeps with its Objective-C objects.
    struct Showing;
    [[nodiscard]] static Showing& getShowing();

  private:
    static const HaylenNativeApi* api;
};
