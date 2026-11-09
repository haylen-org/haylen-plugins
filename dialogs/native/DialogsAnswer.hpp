#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

#include <nlohmann/json.hpp>

#include "haylen/platform/native/HaylenNative.h"

// Answers the calls of the plugin through the engine, from any thread, with the JSON that the Lua API reads: the button of a message counted from 1, the opened files, the saved file, the picked folder, `null` for a dialog that the person dismissed, or a failure. The engine drops an answer to a call that the app gave up.
class DialogsAnswer final {
  public:
    struct File {
        std::string name;
        std::string path;
    };

    static void use(const HaylenNativeApi& value) noexcept;

    static void button(std::uint64_t call, std::size_t number);
    static void files(std::uint64_t call, const std::vector<File>& picked);
    static void saved(std::uint64_t call, const File& file);
    static void folder(std::uint64_t call, std::string_view path);
    static void dismissed(std::uint64_t call);
    static void fail(std::uint64_t call, std::string_view code, std::string_view message);

  private:
    using Json = nlohmann::json;

    static const HaylenNativeApi* api;

    static void resolve(std::uint64_t call, bool ok, const Json& value);
    [[nodiscard]] static Json describe(const File& file);
};
