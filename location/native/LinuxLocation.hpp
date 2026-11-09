#pragma once

#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

#include "LocationBridge.hpp"

// The desktop part of the Location plugin on Linux, which the desktop player and the Linux app load: the location of GeoClue, the location service of Linux, over the system bus of D-Bus, and the handlers of the permissions `location`, `preciseLocation` and `backgroundLocation`. GeoClue asks the person through its agent when a client of the app starts and tells nothing before, so the permissions answer `unknown`, and the agent knows the app by its desktop id, the identifier of the app that the Lua API sends. A desktop app reads the location in the background as it does in use. The handlers run on the frame thread, and a thread of the library talks to GeoClue.
class LinuxLocation final {
  public:
    // Creates the plugin once, since its thread and its handlers belong to the process, registers its methods and declares the library the native part of `location`. Returns 1 for a native API of another version and 2 when D-Bus cannot serve threads.
    [[nodiscard]] static int initialize(const HaylenNativeApi* api);

  private:
    using Json = LocationBridge::Json;
    using Clock = std::chrono::steady_clock;

    // A call of `current` that waits for a fix: its deadline counts from the moment GeoClue started the client, after the agent let the app read the location.
    struct Request {
        std::uint64_t call;
        std::chrono::duration<double> timeout;
        std::optional<Clock::time_point> deadline;
        bool precise;
    };

    static inline LinuxLocation* instance = nullptr;

    explicit LinuxLocation(const HaylenNativeApi& engine);

    static void handleReset(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void handleCurrent(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void cancelCurrent(void* user, std::uint64_t call);
    static void handleWatch(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void handleStop(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void handlePermission(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);

    void reset(std::uint64_t call);
    void current(std::uint64_t call, const Json& params);
    void forget(std::uint64_t call);
    void watch(std::uint64_t call, const Json& params);
    void stop(std::uint64_t call);
    void answerPermission(std::uint64_t call) const;

    // The thread of GeoClue: it starts the client while the app wants the location, serves its updates and deadlines, stops it once nothing wants it, and ends when the library resets.
    void run();
    // Starts the thread of GeoClue where it does not run, and wakes it for what the frame thread asked, under the lock.
    void wakeLocked();
    // Reads the desktop id that GeoClue knows the app by, under the lock, and fails the call without it.
    [[nodiscard]] bool readDesktopId(std::uint64_t call, const Json& params);
    [[nodiscard]] bool isWantedLocked() const;
    [[nodiscard]] bool isStillWanted();
    void markStarted();
    void markStopped();
    // Answers every waiting call with the place, and sends a new place to the watch as a batched event.
    void deliver(const Json& place, bool updated);
    // Starts the deadlines of the calls that waited for the client, and fails the calls whose deadline passed.
    void expire();
    // Fails every waiting call and ends the watch with the same reason, where a refusal names the permission of each call.
    void failAll(std::string_view code, std::string_view message);
    void failAllLocked(std::string_view code, std::string_view message);
    void stopWatchLocked();

    LocationBridge bridge;
    std::mutex mutex;
    std::condition_variable wake;
    std::vector<Request> requests;
    std::string desktopId;
    std::uint64_t watchCall = 0;
    std::uint32_t watchDistance = 0;
    bool watching = false;
    bool watchPrecise = false;
    bool watchAnswering = false;
    bool started = false;
    bool shutdown = false;
    std::thread worker;
};
