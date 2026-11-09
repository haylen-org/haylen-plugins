#pragma once

#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include <windows.h>

#include <windows.media.h>
#include <wrl/client.h>

#include <nlohmann/json.hpp>

class MediaSessionPlugin;

// The media controls of Windows, the system media transport controls of the window of the app, which the media keys of keyboards and headsets and the flyout of the volume and of the lock screen reach. Their buttons and seeks reach the app through `MediaSessionPlugin::emitCommand`. The frame thread shows and clears what plays, and the controls call their handlers on threads of the system.
class WindowsMediaSession final {
  public:
    enum class Command : std::uint8_t {
        Play,
        Pause,
        TogglePlayPause,
        Stop,
        Next,
        Previous,
        Seek,
    };

    // The commands that the controls offer, as bits of `Command`.
    using Commands = std::uint8_t;

    static constexpr std::size_t kCommandCount = 7;

    static constexpr std::array<std::pair<std::string_view, Command>, kCommandCount> kCommandNames{{
        {"play", Command::Play},
        {"pause", Command::Pause},
        {"togglePlayPause", Command::TogglePlayPause},
        {"stop", Command::Stop},
        {"next", Command::Next},
        {"previous", Command::Previous},
        {"seek", Command::Seek},
    }};

    // What plays: the texts the controls show, the duration and the position in seconds with zero for a duration that is not known, whether it plays, the bytes of a PNG or JPEG artwork and the commands the controls offer.
    struct Track {
        std::string title;
        std::string artist;
        std::string album;
        double duration = 0.0;
        double position = 0.0;
        bool playing = false;
        std::vector<std::byte> artwork;
        Commands commands = 0;
    };

    explicit WindowsMediaSession(const MediaSessionPlugin& owner);

    // Shows what plays in the controls, replacing what showed before.
    void show(const Track& track);

    // Takes the app out of the controls.
    void clear();

    // What the controls show, read back from them as `{title, artist, album, duration, playing, artwork}`, or `null` while they show nothing of the app.
    [[nodiscard]] nlohmann::json describe() const;

    [[nodiscard]] static std::optional<Command> commandFromName(std::string_view name) noexcept;
    [[nodiscard]] static std::string_view commandName(Command value) noexcept;
    [[nodiscard]] static constexpr Commands bit(Command value) noexcept {
        return static_cast<Commands>(1U << static_cast<unsigned>(value));
    }

  private:
    // The controls of the window, made once the window exists, with their handlers, or null where the system has none.
    [[nodiscard]] ABI::Windows::Media::ISystemMediaTransportControls* getControls();
    void showDisplay(ABI::Windows::Media::ISystemMediaTransportControls& target, const Track& track);
    static void showTimeline(ABI::Windows::Media::ISystemMediaTransportControls& target, const Track& track);
    static void showArtwork(ABI::Windows::Media::ISystemMediaTransportControlsDisplayUpdater& updater, const Track& track);
    void receiveButton(ABI::Windows::Media::SystemMediaTransportControlsButton button) const;
    [[nodiscard]] static std::string readText(HSTRING text);

    // Media Foundation and the transport controls count time in units of 100 nanoseconds.
    static constexpr double kUnitsPerSecond = 10000000.0;

    const MediaSessionPlugin& plugin;

    // The controls call their handlers on threads of the system until the process ends, and the plugin lives as long, so they are never released.
    Microsoft::WRL::ComPtr<ABI::Windows::Media::ISystemMediaTransportControls> controls;
    bool attempted = false;

    // The commands the app offers, which the frame thread writes and the handlers of the controls read on a thread of the system.
    std::atomic<Commands> offered = 0;

    // The duration shown last, which the controls do not tell back, and whether they show what the app plays.
    double shownDuration = 0.0;
    bool showing = false;
};
