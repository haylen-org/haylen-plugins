#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>
#include <string>
#include <string_view>

#include <nlohmann/json.hpp>

#include "WindowsMediaSession.hpp"
#include "haylen/platform/native/HaylenNative.h"

// The Windows part of the Media Session plugin, a C++ library that shows what the app plays in the system media transport controls of its window. The function `native.load` hands its init function the `HaylenNativeApi` of the engine, through which the library answers the methods of the plugin and sends the commands of the controls. The handlers run on the frame thread, and the controls send their commands from threads of the system.
class MediaSessionPlugin final {
  public:
    using Json = nlohmann::json;

    // Registers the methods of the plugin and declares the library the native part of `media-session`. The process keeps the library loaded across restarts of the app, which run this function again, so the controls of the first run stay. Returns 1 when the engine hands a native API of another version.
    [[nodiscard]] static int initialize(const HaylenNativeApi* api);

    // The `HWND` of the window of the app, or null before the window opens.
    [[nodiscard]] void* getWindow() const;

    // Sends a command of the controls to the app as `media-session.command`, with the position of a seek in seconds, from any thread.
    void emitCommand(WindowsMediaSession::Command command, double position) const;

  private:
    explicit MediaSessionPlugin(const HaylenNativeApi& engine);

    static void setNowPlaying(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void clear(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void nowPlaying(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);

    // What plays, from the parameters that the Lua API sends, whose artwork is the byte buffer that `{"$bytes": N}` names, or nothing for parameters of another shape.
    [[nodiscard]] static std::optional<WindowsMediaSession::Track> readTrack(const Json& params, std::span<const HaylenNativeBuffer> buffers);
    [[nodiscard]] static std::string readText(const Json& params, const char* key);
    [[nodiscard]] static double readSeconds(const Json& params, const char* key);
    [[nodiscard]] static bool readFlag(const Json& params, const char* key);

    void succeed(std::uint64_t call, const Json& result) const;
    void fail(std::uint64_t call, std::string_view message, std::string_view code) const;

    // The JSON of a value, with bytes that are not UTF-8 replaced, since the text crosses into the engine.
    [[nodiscard]] static std::string write(const Json& value);

    static MediaSessionPlugin* instance;

    const HaylenNativeApi& api;
    WindowsMediaSession session;
};
