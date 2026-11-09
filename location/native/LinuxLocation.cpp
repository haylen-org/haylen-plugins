#include "LinuxLocation.hpp"

#include <algorithm>
#include <functional>
#include <limits>
#include <system_error>
#include <utility>

#include <dbus/dbus.h>

#include "GeoClueSession.hpp"

int LinuxLocation::initialize(const HaylenNativeApi* api) {
    if (api->version != HAYLEN_NATIVE_API_VERSION) {
        return 1;
    }
    if (!dbus_threads_init_default()) {
        return 2;
    }
    // The init function runs again after a restart of the app, while the thread of GeoClue belongs to the process, so the plugin lives as long as the process.
    if (instance == nullptr) {
        instance = new LinuxLocation(*api);
    }

    api->registerHandler("location.reset", &LinuxLocation::handleReset, nullptr, instance);
    api->registerHandler("location.current", &LinuxLocation::handleCurrent, &LinuxLocation::cancelCurrent, instance);
    api->registerHandler("location.watch", &LinuxLocation::handleWatch, nullptr, instance);
    api->registerHandler("location.stop", &LinuxLocation::handleStop, nullptr, instance);
    api->registerHandler("location.permission", &LinuxLocation::handlePermission, nullptr, instance);
    api->registerHandler("location.requestPermission", &LinuxLocation::handlePermission, nullptr, instance);
    api->registerPlugin("location");
    return 0;
}

LinuxLocation::LinuxLocation(const HaylenNativeApi& engine) : bridge(engine) {}

void LinuxLocation::handleReset(void* user, std::uint64_t call, const char*, const char*, const HaylenNativeBuffer*, std::size_t) {
    static_cast<LinuxLocation*>(user)->reset(call);
}

void LinuxLocation::handleCurrent(void* user, std::uint64_t call, const char*, const char* paramsJson, const HaylenNativeBuffer*, std::size_t) {
    static_cast<LinuxLocation*>(user)->current(call, LocationBridge::parse(paramsJson));
}

// The app gave a call of `current` up, so it stops waiting without an answer.
void LinuxLocation::cancelCurrent(void* user, std::uint64_t call) {
    static_cast<LinuxLocation*>(user)->forget(call);
}

void LinuxLocation::handleWatch(void* user, std::uint64_t call, const char*, const char* paramsJson, const HaylenNativeBuffer*, std::size_t) {
    static_cast<LinuxLocation*>(user)->watch(call, LocationBridge::parse(paramsJson));
}

void LinuxLocation::handleStop(void* user, std::uint64_t call, const char*, const char*, const HaylenNativeBuffer*, std::size_t) {
    static_cast<LinuxLocation*>(user)->stop(call);
}

// GeoClue asks the person when a client starts and tells nothing before, so a check and a request answer the same, for every permission of the plugin.
void LinuxLocation::handlePermission(void* user, std::uint64_t call, const char*, const char*, const HaylenNativeBuffer*, std::size_t) {
    static_cast<const LinuxLocation*>(user)->answerPermission(call);
}

// Ends the thread of GeoClue and what an earlier app of the process left waiting, whose answers no app receives anymore.
void LinuxLocation::reset(std::uint64_t call) {
    std::unique_lock lock(mutex);
    stopWatchLocked();
    failAllLocked("cancelled", "The app that asked for the location ended.");
    shutdown = true;
    wake.notify_one();
    lock.unlock();

    if (worker.joinable()) {
        worker.join();
    }
    markStopped();
    bridge.succeed(call, nullptr);
}

void LinuxLocation::current(std::uint64_t call, const Json& params) {
    const std::optional<double> timeout = LocationBridge::readNumber(params, "timeout");
    if (!timeout || *timeout <= 0) {
        bridge.fail(call, "The call \"location.current\" needs a \"timeout\" of seconds above 0, which the Lua API of the plugin sends.", "invalidParams");
        return;
    }

    const std::lock_guard lock(mutex);
    if (!readDesktopId(call, params)) {
        return;
    }
    const bool precise = LocationBridge::readBool(params, "precise").value_or(false);
    requests.push_back({.call = call, .timeout = std::chrono::duration<double>(*timeout), .deadline = std::nullopt, .precise = precise});
    wakeLocked();
}

void LinuxLocation::forget(std::uint64_t call) {
    const std::lock_guard lock(mutex);
    std::erase_if(requests, [call](const Request& request) { return request.call == call; });
    wake.notify_one();
}

void LinuxLocation::watch(std::uint64_t call, const Json& params) {
    const std::optional<double> distance = LocationBridge::readNumber(params, "distance");
    if (!distance || *distance < 0) {
        bridge.fail(call, "The call \"location.watch\" needs a \"distance\" of meters, 0 or more, which the Lua API of the plugin sends.", "invalidParams");
        return;
    }

    const std::lock_guard lock(mutex);
    if (!readDesktopId(call, params)) {
        return;
    }
    if (watchAnswering) {
        bridge.fail(watchCall, "A new watch of the location replaced this one before it started.", "cancelled");
    }
    constexpr std::uint32_t kFarthest = std::numeric_limits<std::uint32_t>::max();
    watching = true;
    watchPrecise = LocationBridge::readBool(params, "precise").value_or(false);
    watchDistance = *distance < static_cast<double>(kFarthest) ? static_cast<std::uint32_t>(*distance) : kFarthest;

    if (started) {
        bridge.succeed(call, nullptr);
        watchAnswering = false;
    } else {
        watchCall = call;
        watchAnswering = true;
    }
    wakeLocked();
}

void LinuxLocation::stop(std::uint64_t call) {
    std::unique_lock lock(mutex);
    stopWatchLocked();
    lock.unlock();
    bridge.succeed(call, nullptr);
}

// Tells whether GeoClue runs on the system bus, or starts there when asked, on a thread of its own so the frame thread never waits for the bus.
void LinuxLocation::answerPermission(std::uint64_t call) const {
    try {
        // clang-format off
        std::thread([this, call] {
            const std::optional<std::string_view> missing = GeoClueSession::findMissing();
            if (missing) {
                bridge.fail(call, *missing, "unsupported");
                return;
            }
            bridge.succeed(call, "unknown");
        }).detach();
        // clang-format on
    } catch (const std::system_error&) {
        bridge.fail(call, "The plugin got no thread to ask the system bus on.", "locationUnknown");
    }
}

void LinuxLocation::run() {
    GeoClueSession session;
    std::uint32_t appliedDistance = 0;
    const std::function<bool()> isWanted = [this] { return isStillWanted(); };

    for (;;) {
        std::unique_lock lock(mutex);
        wake.wait(lock, [this, &session] { return shutdown || isWantedLocked() || session.isOpen(); });
        const bool stopping = shutdown;
        const bool wanted = isWantedLocked();
        const std::uint32_t distance = watching ? watchDistance : 0;
        const std::string desktop = desktopId;
        lock.unlock();

        if (stopping || !wanted) {
            session.end();
            markStopped();
            if (stopping) {
                return;
            }
            continue;
        }

        if (!session.isOpen()) {
            const std::optional<GeoClueSession::Failure> failure = session.begin(desktop, distance, isWanted);
            if (failure) {
                if (failure->code != "cancelled") {
                    failAll(failure->code, failure->message);
                }
                continue;
            }
            appliedDistance = distance;
            markStarted();
        }
        if (distance != appliedDistance && session.setDistance(distance)) {
            appliedDistance = distance;
        }

        const std::optional<GeoClueSession::Place> place = session.takePlace();
        if (place) {
            deliver(place->value, place->updated);
        }
        expire();

        const bool connected = session.dispatch();
        if (session.isRevoked()) {
            session.end();
            failAll("denied", "");
        } else if (!connected || session.hasVanished()) {
            session.end();
            failAll("locationUnknown", "The location is unknown: GeoClue, the location service of Linux, left the system bus.");
        }
    }
}

void LinuxLocation::wakeLocked() {
    if (!worker.joinable()) {
        shutdown = false;
        try {
            worker = std::thread(&LinuxLocation::run, this);
        } catch (const std::system_error&) {
            failAllLocked("locationUnknown", "The location is unknown: the plugin got no thread to talk to GeoClue on.");
            return;
        }
    }
    wake.notify_one();
}

bool LinuxLocation::readDesktopId(std::uint64_t call, const Json& params) {
    std::optional<std::string> given = LocationBridge::readText(params, "desktopId");
    if (!given || given->empty()) {
        bridge.fail(call, "GeoClue knows an app by its desktop id, which the Lua API of the plugin sends as \"desktopId\", and this call came without it.", "invalidParams");
        return false;
    }
    desktopId = std::move(*given);
    return true;
}

bool LinuxLocation::isWantedLocked() const {
    return !requests.empty() || watching;
}

bool LinuxLocation::isStillWanted() {
    const std::lock_guard lock(mutex);
    return !shutdown && isWantedLocked();
}

// The client started, so a watch that waited for it answers.
void LinuxLocation::markStarted() {
    const std::lock_guard lock(mutex);
    started = true;
    if (watchAnswering) {
        bridge.succeed(watchCall, nullptr);
        watchAnswering = false;
    }
}

void LinuxLocation::markStopped() {
    const std::lock_guard lock(mutex);
    started = false;
}

void LinuxLocation::deliver(const Json& place, bool updated) {
    const std::lock_guard lock(mutex);
    for (const Request& request : requests) {
        bridge.succeed(request.call, place);
    }
    requests.clear();

    if (updated && watching) {
        bridge.emit("location.changed", place, HAYLEN_NATIVE_EMIT_BATCHED);
    }
}

void LinuxLocation::expire() {
    const Clock::time_point now = Clock::now();
    const std::lock_guard lock(mutex);
    std::vector<Request> kept;
    for (Request& request : requests) {
        if (!request.deadline) {
            request.deadline = now + std::chrono::duration_cast<Clock::duration>(request.timeout);
        }
        if (now < *request.deadline) {
            kept.push_back(request);
            continue;
        }
        bridge.fail(request.call, "No fix of the location came within " + LocationBridge::seconds(request.timeout.count()) + " seconds.", "timeout");
    }
    requests = std::move(kept);
}

void LinuxLocation::failAll(std::string_view code, std::string_view message) {
    const std::lock_guard lock(mutex);
    started = false;
    failAllLocked(code, message);
}

void LinuxLocation::failAllLocked(std::string_view code, std::string_view message) {
    const bool denied = code == "denied";
    for (const Request& request : requests) {
        const std::string reason = denied ? LocationBridge::refusal(request.precise ? "preciseLocation" : "location") : std::string(message);
        bridge.fail(request.call, reason, code);
    }
    requests.clear();

    if (!watching) {
        return;
    }
    const std::string reason = denied ? LocationBridge::refusal(watchPrecise ? "preciseLocation" : "location") : std::string(message);
    if (watchAnswering) {
        bridge.fail(watchCall, reason, code);
    } else {
        bridge.emit("location.stopped", LocationBridge::failure(reason, code), 0);
    }
    watching = false;
    watchAnswering = false;
}

void LinuxLocation::stopWatchLocked() {
    if (watchAnswering) {
        bridge.fail(watchCall, "The watch of the location stopped before it started.", "cancelled");
    }
    watching = false;
    watchAnswering = false;
    wake.notify_one();
}
