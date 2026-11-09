#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

#include <nlohmann/json.hpp>

#include "haylen/platform/native/HaylenNative.h"

// A request of the app as the Lua API of the plugin sends it, after it checked every option, so a value that is missing takes its default.
struct DialogsRequest {
    enum class Method : std::uint8_t {
        Message,
        OpenFiles,
        SaveFile,
        OpenFolder,
        OpenPhotos,
    };

    enum class Kind : std::uint8_t {
        Info,
        Warning,
        Error,
    };

    // A named choice of file types, such as Images with `png` and `jpg`, whose extensions come without their dot.
    struct Filter {
        std::string name;
        std::vector<std::string> extensions;
    };

    Method method = Method::Message;
    std::string title;
    std::string text;
    Kind kind = Kind::Info;
    std::vector<std::string> buttons;
    bool multiple = false;
    std::string name;
    std::vector<Filter> filters;
    std::vector<std::uint8_t> bytes;

    // The methods of the plugin, which the library registers.
    static constexpr std::string_view kMethods[] = {"dialogs.message", "dialogs.openFiles", "dialogs.saveFile", "dialogs.openFolder", "dialogs.openPhotos"};

    // The image files that the desktops pick as photos, by their extensions.
    static constexpr std::string_view kImageExtensions[] = {"png", "jpg", "jpeg", "gif", "bmp", "webp", "heic", "heif", "tif", "tiff"};

    // Reads the parameters of the method, with the bytes of a save from its buffer. Throws `std::runtime_error` for a method that the plugin does not have, parameters that are no JSON object or a save without its bytes.
    [[nodiscard]] static DialogsRequest read(std::string_view method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);

  private:
    using Json = nlohmann::json;

    [[nodiscard]] static Method readMethod(std::string_view method);
    [[nodiscard]] static std::string readString(const Json& object, const char* key);
    [[nodiscard]] static bool readBoolean(const Json& object, const char* key);

    // The texts of a list member, with an empty text for an item that is no string.
    [[nodiscard]] static std::vector<std::string> readStrings(const Json& object, const char* key);

    // The bytes of the buffer that the member `{"$bytes": index}` names, copied, since the buffers of a call live only while its handler runs.
    [[nodiscard]] static std::vector<std::uint8_t> readBytes(const Json& reference, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
};
