#include "DialogsAnswer.hpp"

const HaylenNativeApi* DialogsAnswer::api = nullptr;

void DialogsAnswer::use(const HaylenNativeApi& value) noexcept {
    api = &value;
}

void DialogsAnswer::button(std::uint64_t call, std::size_t number) {
    resolve(call, true, number);
}

void DialogsAnswer::files(std::uint64_t call, const std::vector<File>& picked) {
    Json list = Json::array();
    for (const File& file : picked) {
        list.push_back(describe(file));
    }
    resolve(call, true, list);
}

void DialogsAnswer::saved(std::uint64_t call, const File& file) {
    resolve(call, true, describe(file));
}

void DialogsAnswer::folder(std::uint64_t call, std::string_view path) {
    resolve(call, true, path);
}

void DialogsAnswer::dismissed(std::uint64_t call) {
    resolve(call, true, nullptr);
}

void DialogsAnswer::fail(std::uint64_t call, std::string_view code, std::string_view message) {
    resolve(call, false, {{"message", message}, {"code", code}});
}

// A path of Linux may hold bytes that are not UTF-8, which the JSON replaces, since the text crosses into the engine.
void DialogsAnswer::resolve(std::uint64_t call, bool ok, const Json& value) {
    const std::string text = value.dump(-1, ' ', false, Json::error_handler_t::replace);
    api->resolve(call, ok ? 1 : 0, text.c_str(), nullptr, 0);
}

DialogsAnswer::Json DialogsAnswer::describe(const File& file) {
    return {{"name", file.name}, {"path", file.path}};
}
