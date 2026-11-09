#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <variant>
#include <vector>

#include <nlohmann/json.hpp>

#include "haylen/platform/native/HaylenNative.h"

// A share as the Lua API of the plugin sends it: a text, a url, a title, files with the bytes that the call carried, and the place of the window it comes from.
struct ShareRequest {
    struct File {
        std::string name;
        std::vector<std::uint8_t> bytes;
    };

    // A rectangle in fractions of the window from its top left corner.
    struct Anchor {
        double x = 0.0;
        double y = 0.0;
        double width = 0.0;
        double height = 0.0;
    };

    // Why a share cannot show, with the code of the failure of its call.
    struct Failure {
        std::string message;
        std::string code;
    };

    std::optional<std::string> text;
    std::optional<std::string> url;
    std::optional<std::string> title;
    std::vector<File> files;
    std::optional<Anchor> anchor;

    // Reads the parameters of a share and copies the bytes of its files, since the buffers of a call live only while its handler runs.
    [[nodiscard]] static std::variant<ShareRequest, Failure> read(const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);

  private:
    using Json = nlohmann::json;

    [[nodiscard]] static std::optional<std::string> readText(const Json& object, const char* key);
    [[nodiscard]] static double readNumber(const Json& object, const char* key);

    // The buffer that a reference `{"$bytes": index}` names, or null when the call carried no such buffer.
    [[nodiscard]] static const HaylenNativeBuffer* findBuffer(const Json& reference, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
};
