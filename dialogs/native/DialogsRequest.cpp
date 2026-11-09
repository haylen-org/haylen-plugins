#include "DialogsRequest.hpp"

#include <stdexcept>
#include <utility>

DialogsRequest DialogsRequest::read(std::string_view method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount) {
    DialogsRequest request;
    request.method = readMethod(method);

    const Json params = Json::parse(paramsJson, nullptr, false);
    if (!params.is_object()) {
        throw std::runtime_error("The parameters of the dialog are not a JSON object.");
    }
    request.title = readString(params, "title");
    request.text = readString(params, "text");
    request.multiple = readBoolean(params, "multiple");
    request.name = readString(params, "name");
    request.buttons = readStrings(params, "buttons");

    const std::string kind = readString(params, "kind");
    if (kind == "warning") {
        request.kind = Kind::Warning;
    } else if (kind == "error") {
        request.kind = Kind::Error;
    }

    const auto filters = params.find("filters");
    if (filters != params.end() && filters->is_array()) {
        for (const Json& entry : *filters) {
            if (!entry.is_object()) {
                continue;
            }
            request.filters.push_back({.name = readString(entry, "name"), .extensions = readStrings(entry, "extensions")});
        }
    }

    const auto data = params.find("data");
    if (data != params.end()) {
        request.bytes = readBytes(*data, buffers, bufferCount);
    }
    return request;
}

DialogsRequest::Method DialogsRequest::readMethod(std::string_view method) {
    if (method == "dialogs.message") {
        return Method::Message;
    }
    if (method == "dialogs.openFiles") {
        return Method::OpenFiles;
    }
    if (method == "dialogs.saveFile") {
        return Method::SaveFile;
    }
    if (method == "dialogs.openFolder") {
        return Method::OpenFolder;
    }
    if (method == "dialogs.openPhotos") {
        return Method::OpenPhotos;
    }
    throw std::runtime_error("The plugin \"dialogs\" has no method \"" + std::string(method) + "\".");
}

std::string DialogsRequest::readString(const Json& object, const char* key) {
    const auto found = object.find(key);
    if (found == object.end() || !found->is_string()) {
        return {};
    }
    return found->get<std::string>();
}

bool DialogsRequest::readBoolean(const Json& object, const char* key) {
    const auto found = object.find(key);
    return found != object.end() && found->is_boolean() && found->get<bool>();
}

std::vector<std::string> DialogsRequest::readStrings(const Json& object, const char* key) {
    std::vector<std::string> texts;
    const auto found = object.find(key);
    if (found == object.end() || !found->is_array()) {
        return texts;
    }
    for (const Json& item : *found) {
        texts.push_back(item.is_string() ? item.get<std::string>() : std::string());
    }
    return texts;
}

std::vector<std::uint8_t> DialogsRequest::readBytes(const Json& reference, const HaylenNativeBuffer* buffers, std::size_t bufferCount) {
    const auto index = reference.is_object() ? reference.find("$bytes") : reference.end();
    const bool named = index != reference.end() && index->is_number_unsigned() && index->get<std::uint64_t>() < bufferCount;
    if (!named) {
        throw std::runtime_error("The data of the save names a byte buffer that did not come with it.");
    }

    const HaylenNativeBuffer& buffer = buffers[index->get<std::uint64_t>()];
    const auto* first = static_cast<const std::uint8_t*>(buffer.data);
    return std::vector<std::uint8_t>(first, first + buffer.size);
}
