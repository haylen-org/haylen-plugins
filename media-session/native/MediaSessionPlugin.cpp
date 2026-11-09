#include "MediaSessionPlugin.hpp"

#include <cmath>

MediaSessionPlugin* MediaSessionPlugin::instance = nullptr;

int MediaSessionPlugin::initialize(const HaylenNativeApi* api) {
    if (api->version != HAYLEN_NATIVE_API_VERSION) {
        return 1;
    }
    if (instance == nullptr) {
        instance = new MediaSessionPlugin(*api);
    }

    api->registerHandler("media-session.setNowPlaying", &MediaSessionPlugin::setNowPlaying, nullptr, instance);
    api->registerHandler("media-session.clear", &MediaSessionPlugin::clear, nullptr, instance);
    api->registerHandler("media-session.nowPlaying", &MediaSessionPlugin::nowPlaying, nullptr, instance);
    api->registerPlugin("media-session");
    return 0;
}

MediaSessionPlugin::MediaSessionPlugin(const HaylenNativeApi& engine) : api(engine), session(*this) {}

void* MediaSessionPlugin::getWindow() const {
    HaylenNativeWindow window{};
    return api.getWindow(&window) != 0 ? window.handle : nullptr;
}

void MediaSessionPlugin::emitCommand(WindowsMediaSession::Command command, double position) const {
    Json payload = {{"command", WindowsMediaSession::commandName(command)}};
    if (command == WindowsMediaSession::Command::Seek) {
        payload["position"] = position;
    }

    const std::string text = write(payload);
    api.emit("media-session.command", text.c_str(), nullptr, 0, 0);
}

void MediaSessionPlugin::succeed(std::uint64_t call, const Json& result) const {
    const std::string text = write(result);
    api.resolve(call, 1, text.c_str(), nullptr, 0);
}

void MediaSessionPlugin::fail(std::uint64_t call, std::string_view message, std::string_view code) const {
    const std::string text = write({{"message", message}, {"code", code}});
    api.resolve(call, 0, text.c_str(), nullptr, 0);
}

std::string MediaSessionPlugin::write(const Json& value) {
    return value.dump(-1, ' ', false, Json::error_handler_t::replace);
}

std::string MediaSessionPlugin::readText(const Json& params, const char* key) {
    const auto found = params.find(key);
    return found != params.end() && found->is_string() ? found->get<std::string>() : std::string();
}

double MediaSessionPlugin::readSeconds(const Json& params, const char* key) {
    const auto found = params.find(key);
    if (found == params.end() || !found->is_number()) {
        return 0.0;
    }
    const double seconds = found->get<double>();
    return std::isfinite(seconds) && seconds > 0.0 ? seconds : 0.0;
}

bool MediaSessionPlugin::readFlag(const Json& params, const char* key) {
    const auto found = params.find(key);
    return found != params.end() && found->is_boolean() && found->get<bool>();
}

std::optional<WindowsMediaSession::Track> MediaSessionPlugin::readTrack(const Json& params, std::span<const HaylenNativeBuffer> buffers) {
    if (!params.is_object()) {
        return std::nullopt;
    }
    const auto commands = params.find("commands");
    if (commands == params.end() || !commands->is_object()) {
        return std::nullopt;
    }

    WindowsMediaSession::Track track{
        .title = readText(params, "title"),
        .artist = readText(params, "artist"),
        .album = readText(params, "album"),
        .duration = readSeconds(params, "duration"),
        .position = readSeconds(params, "position"),
        .playing = readFlag(params, "playing"),
    };
    for (const auto& entry : commands->items()) {
        const std::optional<WindowsMediaSession::Command> command = WindowsMediaSession::commandFromName(entry.key());
        if (!command) {
            return std::nullopt;
        }
        track.commands |= WindowsMediaSession::bit(*command);
    }

    // The artwork crosses as `{"$bytes": N}`, which names buffer `N` of the call.
    const auto artwork = params.find("artwork");
    if (artwork != params.end()) {
        const auto index = artwork->is_object() ? artwork->find("$bytes") : artwork->end();
        if (index == artwork->end() || !index->is_number_unsigned() || index->get<std::size_t>() >= buffers.size()) {
            return std::nullopt;
        }
        const HaylenNativeBuffer& buffer = buffers[index->get<std::size_t>()];
        const auto* bytes = static_cast<const std::byte*>(buffer.data);
        track.artwork.assign(bytes, bytes + buffer.size);
    }
    return track;
}

// The engine hands JSON text, which the library reads without exceptions, since none may cross the C interface of the engine.
void MediaSessionPlugin::setNowPlaying(void* user, std::uint64_t call, const char*, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount) {
    auto& plugin = *static_cast<MediaSessionPlugin*>(user);
    const Json params = Json::parse(paramsJson, nullptr, false);
    const std::optional<WindowsMediaSession::Track> track = readTrack(params, std::span(buffers, bufferCount));
    if (!track) {
        plugin.fail(call, "The parameters of what plays are invalid.", "invalidParams");
        return;
    }

    plugin.session.show(*track);
    plugin.succeed(call, nullptr);
}

void MediaSessionPlugin::clear(void* user, std::uint64_t call, const char*, const char*, const HaylenNativeBuffer*, std::size_t) {
    auto& plugin = *static_cast<MediaSessionPlugin*>(user);
    plugin.session.clear();
    plugin.succeed(call, nullptr);
}

void MediaSessionPlugin::nowPlaying(void* user, std::uint64_t call, const char*, const char*, const HaylenNativeBuffer*, std::size_t) {
    auto& plugin = *static_cast<MediaSessionPlugin*>(user);
    plugin.succeed(call, plugin.session.describe());
}
