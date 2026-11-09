#include "SharePlugin.hpp"

#include <utility>
#include <variant>

#include "ShareAnswer.hpp"
#include "ShareRequest.hpp"

#if defined(__APPLE__)
#include "MacosShare.hpp"
using ShareSystem = MacosShare;
#else
#include "WindowsShare.hpp"
using ShareSystem = WindowsShare;
#endif

const HaylenNativeApi* SharePlugin::api = nullptr;

int SharePlugin::initialize(const HaylenNativeApi* value) {
    if (value->version != HAYLEN_NATIVE_API_VERSION) {
        return 1;
    }
    api = value;
    ShareAnswer::use(*api);
    ShareSystem::use(*api);

    api->registerHandler("share.share", &SharePlugin::share, nullptr, nullptr);
    api->registerPlugin("share");
    return 0;
}

void SharePlugin::share(void*, std::uint64_t call, const char*, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount) {
    HaylenNativeWindow window{};
    if (api->getWindow(&window) == 0 || window.handle == nullptr) {
        ShareAnswer::fail(call, "noWindow", "The app has no window yet.");
        return;
    }

    std::variant<ShareRequest, ShareRequest::Failure> reading = ShareRequest::read(paramsJson, buffers, bufferCount);
    if (const auto* failure = std::get_if<ShareRequest::Failure>(&reading)) {
        ShareAnswer::fail(call, failure->code, failure->message);
        return;
    }
    ShareSystem::show(call, window, std::move(std::get<ShareRequest>(reading)));
}
