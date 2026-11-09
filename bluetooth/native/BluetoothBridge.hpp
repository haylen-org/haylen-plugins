#pragma once

#include <atomic>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>

#include <nlohmann/json.hpp>

#include "BluetoothFailure.hpp"
#include "haylen/platform/native/HaylenNative.h"

// The way back to the app: the answers of calls, the events and the log lines of the library, written as JSON for the native API of the engine. Every method may run on any thread.
class BluetoothBridge final {
  public:
    using Json = nlohmann::json;

    explicit BluetoothBridge(const HaylenNativeApi& engine);

    // The engine hands the init function its native API again after every restart of the app.
    void setApi(const HaylenNativeApi& engine);

    void succeed(std::uint64_t call, const Json& result) const;
    // Answers with a result whose JSON names the bytes as `{"$bytes": 0}`.
    void succeedWithBytes(std::uint64_t call, const Json& result, std::span<const std::uint8_t> bytes) const;
    void fail(std::uint64_t call, const BluetoothFailure& failure) const;
    void emit(std::string_view event, const Json& payload, int flags) const;
    // Sends an event whose payload names the bytes as `{"$bytes": 0}`.
    void emitWithBytes(std::string_view event, const Json& payload, std::span<const std::uint8_t> bytes, int flags) const;
    void log(int level, const std::string& text) const;

  private:
    // The JSON of a value, with bytes that are not UTF-8 replaced, since the text crosses into the engine.
    [[nodiscard]] static std::string write(const Json& value);

    std::atomic<const HaylenNativeApi*> api;
};
