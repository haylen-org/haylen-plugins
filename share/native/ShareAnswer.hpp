#pragma once

#include <cstdint>
#include <string_view>

#include <nlohmann/json.hpp>

#include "haylen/platform/native/HaylenNative.h"

// Answers the call of a share through the engine, from any thread, with the JSON that the Lua API reads: whether the person shared and where, or a failure.
class ShareAnswer final {
  public:
    static void use(const HaylenNativeApi& value) noexcept;

    // Answers `{shared, target}`, with the target only when the person shared and the system names where.
    static void finish(std::uint64_t call, bool shared, std::string_view target);
    static void fail(std::uint64_t call, std::string_view code, std::string_view message);

  private:
    using Json = nlohmann::json;

    static const HaylenNativeApi* api;

    static void resolve(std::uint64_t call, bool ok, const Json& value);
};
