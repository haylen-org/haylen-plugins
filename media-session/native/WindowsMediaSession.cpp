#include "WindowsMediaSession.hpp"

#include <roapi.h>
#include <shcore.h>
#include <shlwapi.h>
#include <systemmediatransportcontrolsinterop.h>
#include <windows.foundation.h>
#include <windows.storage.streams.h>
#include <winstring.h>
#include <wrl/event.h>
#include <wrl/wrappers/corewrappers.h>

#include <algorithm>
#include <cmath>

#include "MediaSessionPlugin.hpp"
#include "WindowsText.hpp"

using ABI::Windows::Media::ISystemMediaTransportControls;
using ABI::Windows::Media::ISystemMediaTransportControls2;
using ABI::Windows::Media::ISystemMediaTransportControlsButtonPressedEventArgs;
using ABI::Windows::Media::ISystemMediaTransportControlsDisplayUpdater;
using ABI::Windows::Media::SystemMediaTransportControlsButton;
using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;
using Microsoft::WRL::Wrappers::HString;
using Microsoft::WRL::Wrappers::HStringReference;

WindowsMediaSession::WindowsMediaSession(const MediaSessionPlugin& owner) : plugin(owner) {}

std::optional<WindowsMediaSession::Command> WindowsMediaSession::commandFromName(std::string_view name) noexcept {
    const auto found = std::ranges::find(kCommandNames, name, &std::pair<std::string_view, Command>::first);
    return found != kCommandNames.end() ? std::optional<Command>(found->second) : std::nullopt;
}

std::string_view WindowsMediaSession::commandName(Command value) noexcept {
    return std::ranges::find(kCommandNames, value, &std::pair<std::string_view, Command>::second)->first;
}

// The play and pause buttons send the toggle of an app that offers only the toggle, since the controls have no toggle button and the play and pause key sends the one the status shows.
void WindowsMediaSession::receiveButton(SystemMediaTransportControlsButton button) const {
    // clang-format off
    const auto send = [this](Command command) {
        const Commands commands = offered.load();
        const bool toggled = (command == Command::Play || command == Command::Pause) && (commands & bit(command)) == 0 && (commands & bit(Command::TogglePlayPause)) != 0;
        plugin.emitCommand(toggled ? Command::TogglePlayPause : command, 0.0);
    };
    // clang-format on
    switch (button) {
    case ABI::Windows::Media::SystemMediaTransportControlsButton_Play:
        send(Command::Play);
        break;
    case ABI::Windows::Media::SystemMediaTransportControlsButton_Pause:
        send(Command::Pause);
        break;
    case ABI::Windows::Media::SystemMediaTransportControlsButton_Stop:
        send(Command::Stop);
        break;
    case ABI::Windows::Media::SystemMediaTransportControlsButton_Next:
        send(Command::Next);
        break;
    case ABI::Windows::Media::SystemMediaTransportControlsButton_Previous:
        send(Command::Previous);
        break;
    default:
        break;
    }
}

// The controls belong to the window, so they are made once its window exists, and a system without them leaves the app out of the controls.
ISystemMediaTransportControls* WindowsMediaSession::getControls() {
    if (attempted) {
        return controls.Get();
    }

    const auto window = static_cast<HWND>(plugin.getWindow());
    if (window == nullptr) {
        return nullptr;
    }

    attempted = true;
    const HRESULT started = RoInitialize(RO_INIT_SINGLETHREADED);
    if (FAILED(started) && started != RPC_E_CHANGED_MODE) {
        return nullptr;
    }

    ComPtr<ISystemMediaTransportControlsInterop> interop;
    if (FAILED(RoGetActivationFactory(HStringReference(RuntimeClass_Windows_Media_SystemMediaTransportControls).Get(), IID_PPV_ARGS(&interop))) || FAILED(interop->GetForWindow(window, IID_PPV_ARGS(&controls)))) {
        controls.Reset();
        return nullptr;
    }

    EventRegistrationToken token{};
    // clang-format off
    controls->add_ButtonPressed(Callback<ABI::Windows::Foundation::ITypedEventHandler<ABI::Windows::Media::SystemMediaTransportControls*, ABI::Windows::Media::SystemMediaTransportControlsButtonPressedEventArgs*>>([this](ISystemMediaTransportControls*, ISystemMediaTransportControlsButtonPressedEventArgs* event) {
        SystemMediaTransportControlsButton button{};
        if (SUCCEEDED(event->get_Button(&button))) {
            receiveButton(button);
        }

        return S_OK;
    }).Get(), &token);
    ComPtr<ISystemMediaTransportControls2> seeking;
    if (SUCCEEDED(controls.As(&seeking))) {
        seeking->add_PlaybackPositionChangeRequested(Callback<ABI::Windows::Foundation::ITypedEventHandler<ABI::Windows::Media::SystemMediaTransportControls*, ABI::Windows::Media::PlaybackPositionChangeRequestedEventArgs*>>([this](ISystemMediaTransportControls*, ABI::Windows::Media::IPlaybackPositionChangeRequestedEventArgs* event) {
            ABI::Windows::Foundation::TimeSpan position{};
            if ((offered.load() & bit(Command::Seek)) != 0 && SUCCEEDED(event->get_RequestedPlaybackPosition(&position))) {
                plugin.emitCommand(Command::Seek, static_cast<double>(position.Duration) / kUnitsPerSecond);
            }

            return S_OK;
        }).Get(), &token);
    }
    // clang-format on
    return controls.Get();
}

void WindowsMediaSession::show(const Track& track) {
    ISystemMediaTransportControls* found = getControls();
    if (found == nullptr) {
        return;
    }

    showDisplay(*found, track);
    shownDuration = track.duration;
    showing = true;
}

// The controls exist while they show what the app plays, and a process that never showed anything never makes them.
void WindowsMediaSession::clear() {
    if (!showing) {
        return;
    }

    offered.store(0);
    ComPtr<ISystemMediaTransportControlsDisplayUpdater> updater;
    if (SUCCEEDED(controls->get_DisplayUpdater(&updater))) {
        updater->ClearAll();
    }

    controls->put_PlaybackStatus(ABI::Windows::Media::MediaPlaybackStatus_Closed);
    controls->put_IsEnabled(false);
    shownDuration = 0.0;
    showing = false;
}

void WindowsMediaSession::showDisplay(ISystemMediaTransportControls& target, const Track& track) {
    offered.store(track.commands);
    const auto offers = [&track](Command command) -> boolean { return (track.commands & bit(command)) != 0; };
    const boolean toggles = offers(Command::TogglePlayPause);
    target.put_IsEnabled(true);
    target.put_IsPlayEnabled(offers(Command::Play) || toggles);
    target.put_IsPauseEnabled(offers(Command::Pause) || toggles);
    target.put_IsStopEnabled(offers(Command::Stop));
    target.put_IsNextEnabled(offers(Command::Next));
    target.put_IsPreviousEnabled(offers(Command::Previous));
    target.put_PlaybackStatus(track.playing ? ABI::Windows::Media::MediaPlaybackStatus_Playing : ABI::Windows::Media::MediaPlaybackStatus_Paused);

    ComPtr<ISystemMediaTransportControlsDisplayUpdater> updater;
    ComPtr<ABI::Windows::Media::IMusicDisplayProperties> music;
    if (FAILED(target.get_DisplayUpdater(&updater)) || FAILED(updater->put_Type(ABI::Windows::Media::MediaPlaybackType_Music)) || FAILED(updater->get_MusicProperties(&music))) {
        return;
    }

    const std::wstring title = WindowsText::toWide(track.title);
    const std::wstring artist = WindowsText::toWide(track.artist);
    const std::wstring album = WindowsText::toWide(track.album);
    music->put_Title(HStringReference(title.c_str(), static_cast<unsigned int>(title.size())).Get());
    music->put_Artist(HStringReference(artist.c_str(), static_cast<unsigned int>(artist.size())).Get());
    ComPtr<ABI::Windows::Media::IMusicDisplayProperties2> albums;
    if (SUCCEEDED(music.As(&albums))) {
        albums->put_AlbumTitle(HStringReference(album.c_str(), static_cast<unsigned int>(album.size())).Get());
    }

    showArtwork(*updater.Get(), track);
    updater->Update();
    showTimeline(target, track);
}

// The artwork reaches the controls as a stream of its bytes in memory.
void WindowsMediaSession::showArtwork(ISystemMediaTransportControlsDisplayUpdater& updater, const Track& track) {
    if (track.artwork.empty()) {
        updater.put_Thumbnail(nullptr);
        return;
    }

    ComPtr<IStream> memory;
    memory.Attach(SHCreateMemStream(reinterpret_cast<const BYTE*>(track.artwork.data()), static_cast<UINT>(track.artwork.size())));
    ComPtr<ABI::Windows::Storage::Streams::IRandomAccessStream> stream;
    ComPtr<ABI::Windows::Storage::Streams::IRandomAccessStreamReferenceStatics> references;
    ComPtr<ABI::Windows::Storage::Streams::IRandomAccessStreamReference> reference;
    if (memory && SUCCEEDED(CreateRandomAccessStreamOverStream(memory.Get(), BSOS_DEFAULT, IID_PPV_ARGS(&stream))) && SUCCEEDED(RoGetActivationFactory(HStringReference(RuntimeClass_Windows_Storage_Streams_RandomAccessStreamReference).Get(), IID_PPV_ARGS(&references))) && SUCCEEDED(references->CreateFromStream(stream.Get(), &reference))) {
        updater.put_Thumbnail(reference.Get());
    }
}

void WindowsMediaSession::showTimeline(ISystemMediaTransportControls& target, const Track& track) {
    ComPtr<ISystemMediaTransportControls2> seeking;
    ComPtr<IInspectable> created;
    ComPtr<ABI::Windows::Media::ISystemMediaTransportControlsTimelineProperties> timeline;
    if (track.duration <= 0.0 || FAILED(target.QueryInterface(IID_PPV_ARGS(&seeking))) || FAILED(RoActivateInstance(HStringReference(RuntimeClass_Windows_Media_SystemMediaTransportControlsTimelineProperties).Get(), &created)) || FAILED(created.As(&timeline))) {
        return;
    }

    const auto units = [](double seconds) { return ABI::Windows::Foundation::TimeSpan{.Duration = std::llround(seconds * kUnitsPerSecond)}; };
    timeline->put_StartTime(units(0.0));
    timeline->put_MinSeekTime(units(0.0));
    timeline->put_EndTime(units(track.duration));
    timeline->put_MaxSeekTime(units(track.duration));
    timeline->put_Position(units(std::min(track.position, track.duration)));
    seeking->UpdateTimelineProperties(timeline.Get());
}

// The controls exist while they show what the app plays, since only controls that exist show it.
nlohmann::json WindowsMediaSession::describe() const {
    if (!showing) {
        return nullptr;
    }

    ComPtr<ISystemMediaTransportControlsDisplayUpdater> updater;
    ComPtr<ABI::Windows::Media::IMusicDisplayProperties> music;
    if (FAILED(controls->get_DisplayUpdater(&updater)) || FAILED(updater->get_MusicProperties(&music))) {
        return nullptr;
    }

    HString title;
    HString artist;
    HString album;
    music->get_Title(title.GetAddressOf());
    music->get_Artist(artist.GetAddressOf());
    ComPtr<ABI::Windows::Media::IMusicDisplayProperties2> albums;
    if (SUCCEEDED(music.As(&albums))) {
        albums->get_AlbumTitle(album.GetAddressOf());
    }

    ABI::Windows::Media::MediaPlaybackStatus status{};
    controls->get_PlaybackStatus(&status);
    ComPtr<ABI::Windows::Storage::Streams::IRandomAccessStreamReference> thumbnail;
    updater->get_Thumbnail(&thumbnail);
    return {
        {"title", readText(title.Get())}, {"artist", readText(artist.Get())}, {"album", readText(album.Get())}, {"duration", shownDuration}, {"playing", status == ABI::Windows::Media::MediaPlaybackStatus_Playing}, {"artwork", thumbnail != nullptr},
    };
}

std::string WindowsMediaSession::readText(HSTRING text) {
    UINT32 length = 0;
    const wchar_t* characters = WindowsGetStringRawBuffer(text, &length);
    return WindowsText::toUtf8(std::wstring_view(characters, length));
}
