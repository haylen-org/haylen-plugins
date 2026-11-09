#include "ShareRequest.hpp"

#include <utility>

std::variant<ShareRequest, ShareRequest::Failure> ShareRequest::read(const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount) {
    const Json params = Json::parse(paramsJson, nullptr, false);
    if (!params.is_object()) {
        return Failure{.message = "The parameters of the share are invalid.", .code = "invalidParams"};
    }

    ShareRequest request;
    request.text = readText(params, "text");
    request.url = readText(params, "url");
    request.title = readText(params, "title");

    const auto files = params.find("files");
    if (files != params.end() && files->is_array()) {
        for (const Json& file : *files) {
            const std::optional<std::string> name = file.is_object() ? readText(file, "name") : std::nullopt;
            const auto bytes = file.is_object() ? file.find("bytes") : file.end();
            const HaylenNativeBuffer* buffer = bytes != file.end() ? findBuffer(*bytes, buffers, bufferCount) : nullptr;
            if (!name || buffer == nullptr) {
                return Failure{.message = "A file of the share has no name or no bytes.", .code = "invalidParams"};
            }

            const auto* first = static_cast<const std::uint8_t*>(buffer->data);
            request.files.push_back({.name = *name, .bytes = std::vector<std::uint8_t>(first, first + buffer->size)});
        }
    }

    const auto anchor = params.find("anchor");
    if (anchor != params.end() && anchor->is_object()) {
        request.anchor = Anchor{.x = readNumber(*anchor, "x"), .y = readNumber(*anchor, "y"), .width = readNumber(*anchor, "width"), .height = readNumber(*anchor, "height")};
    }
    return request;
}

std::optional<std::string> ShareRequest::readText(const Json& object, const char* key) {
    const auto found = object.find(key);
    if (found == object.end() || !found->is_string()) {
        return std::nullopt;
    }
    return found->get<std::string>();
}

double ShareRequest::readNumber(const Json& object, const char* key) {
    const auto found = object.find(key);
    if (found == object.end() || !found->is_number()) {
        return 0.0;
    }
    return found->get<double>();
}

const HaylenNativeBuffer* ShareRequest::findBuffer(const Json& reference, const HaylenNativeBuffer* buffers, std::size_t bufferCount) {
    if (!reference.is_object()) {
        return nullptr;
    }
    const auto index = reference.find("$bytes");
    if (index == reference.end() || !index->is_number_unsigned()) {
        return nullptr;
    }

    const auto position = index->get<std::uint64_t>();
    if (position >= bufferCount) {
        return nullptr;
    }
    return &buffers[position];
}
