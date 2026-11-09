#include "ShareAnswer.hpp"

#include <string>

const HaylenNativeApi* ShareAnswer::api = nullptr;

void ShareAnswer::use(const HaylenNativeApi& value) noexcept {
    api = &value;
}

void ShareAnswer::finish(std::uint64_t call, bool shared, std::string_view target) {
    Json result = {{"shared", shared}};
    if (shared && !target.empty()) {
        result["target"] = target;
    }
    resolve(call, true, result);
}

void ShareAnswer::fail(std::uint64_t call, std::string_view code, std::string_view message) {
    resolve(call, false, {{"message", message}, {"code", code}});
}

// The text may hold bytes that are not UTF-8, such as a name that the system reports, which the JSON replaces, since the text crosses into the engine.
void ShareAnswer::resolve(std::uint64_t call, bool ok, const Json& value) {
    const std::string text = value.dump(-1, ' ', false, Json::error_handler_t::replace);
    api->resolve(call, ok ? 1 : 0, text.c_str(), nullptr, 0);
}
