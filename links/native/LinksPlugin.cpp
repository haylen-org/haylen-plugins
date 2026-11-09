#include "LinksPlugin.hpp"

#include <nlohmann/json.hpp>

int LinksPlugin::initialize(const HaylenNativeApi* given) {
    if (given->version != HAYLEN_NATIVE_API_VERSION) {
        return 1;
    }
    api = given;

    api->registerHandler("links.open", &LinksPlugin::open, nullptr, nullptr);
    api->registerPlugin("links");
    return 0;
}

// The engine hands JSON text, which the library reads without exceptions, since none may cross the C interface of the engine.
void LinksPlugin::open(void*, std::uint64_t call, const char*, const char* paramsJson, const HaylenNativeBuffer*, std::size_t) {
    const nlohmann::json params = nlohmann::json::parse(paramsJson, nullptr, false);
    const auto found = params.find("url");
    if (!params.is_object() || found == params.end() || !found->is_string()) {
        fail(call, "The method \"links.open\" needs the url as a string.", "invalidUrl");
        return;
    }

    const std::string url = found->get<std::string>();
    // clang-format off
    LinkOpener::open(url, [call, url](LinkOpener::Answer result) {
        answer(call, url, result);
    });
    // clang-format on
}

void LinksPlugin::answer(std::uint64_t call, const std::string& url, LinkOpener::Answer result) {
    switch (result) {
    case LinkOpener::Answer::Opened: {
        const std::string text = nlohmann::json(true).dump();
        api->resolve(call, 1, text.c_str(), nullptr, 0);
        return;
    }
    case LinkOpener::Answer::NotAUrl:
        fail(call, "The text \"" + url + "\" is not a url.", "unsupported");
        return;
    case LinkOpener::Answer::NoApp:
        fail(call, "No app on this device opens \"" + url + "\".", "unsupported");
        return;
    case LinkOpener::Answer::MissingCommand:
        fail(call, "The url \"" + url + "\" cannot open, because the command \"xdg-open\" of the desktop is missing.", "unsupported");
        return;
    case LinkOpener::Answer::NoThread:
        fail(call, "The url \"" + url + "\" cannot open, because the library of links could not start a thread.", "unsupported");
        return;
    }
}

void LinksPlugin::fail(std::uint64_t call, const std::string& message, const char* code) {
    const nlohmann::json failure = {{"message", message}, {"code", code}};
    const std::string text = failure.dump(-1, ' ', false, nlohmann::json::error_handler_t::replace);
    api->resolve(call, 0, text.c_str(), nullptr, 0);
}
