#include "DialogsPlugin.hpp"

#include <exception>
#include <string>
#include <string_view>

#include "DialogsAnswer.hpp"
#include "DialogsRequest.hpp"

#if defined(__APPLE__)
#include "MacosDialogs.hpp"
using DialogsSystem = MacosDialogs;
#elif defined(_WIN32)
#include "WindowsDialogs.hpp"
using DialogsSystem = WindowsDialogs;
#else
#include "LinuxDialogs.hpp"
using DialogsSystem = LinuxDialogs;
#endif

int DialogsPlugin::initialize(const HaylenNativeApi* api) {
    if (api->version != HAYLEN_NATIVE_API_VERSION) {
        return 1;
    }
    DialogsAnswer::use(*api);
    DialogsSystem::use(*api);

    for (const std::string_view method : DialogsRequest::kMethods) {
        const std::string name(method);
        api->registerHandler(name.c_str(), &DialogsPlugin::show, &DialogsPlugin::cancel, nullptr);
    }
    api->registerPlugin("dialogs");
    return 0;
}

// The buffers of the call live until the handler returns, so the request copies the data of a save. No exception crosses the C interface of the engine.
void DialogsPlugin::show(void*, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount) {
    try {
        DialogsSystem::show(call, DialogsRequest::read(method, paramsJson, buffers, bufferCount));
    } catch (const std::exception& error) {
        DialogsAnswer::fail(call, "failed", std::string("The dialog could not be shown: ") + error.what());
    }
}

void DialogsPlugin::cancel(void*, std::uint64_t call) {
    DialogsSystem::cancel(call);
}
