#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <string_view>

#include <windows.h>

#include <windows.devices.geolocation.h>
#include <windows.foundation.h>
#include <wrl/client.h>

#include "LocationBridge.hpp"
#include "WindowsLocationWatch.hpp"
#include "WindowsLocationWorker.hpp"

// The desktop part of the Location plugin on Windows, which the desktop player and the Windows app load: one fix and the updates of the `Geolocator` of the Windows Runtime, and the handlers of the permissions `location`, `preciseLocation` and `backgroundLocation`, which the capability `location` of the privacy settings of Windows answers for all three, since a desktop app keeps running in the background as in use and Windows gives the precision its settings allow. The handlers run on the frame thread and hand their work to the thread of the library, which alone touches the watch and answers the calls, while the fixes and the updates arrive on threads of the Windows Runtime.
class WindowsLocation final {
  public:
    // Creates the plugin once, since its thread and its watch belong to the process, registers its methods and declares the library the native part of `location`. Returns 1 for a native API of another version.
    [[nodiscard]] static int initialize(const HaylenNativeApi* api);

  private:
    using Json = LocationBridge::Json;
    using GeolocatorPointer = Microsoft::WRL::ComPtr<ABI::Windows::Devices::Geolocation::IGeolocator>;
    using Fix = ABI::Windows::Foundation::IAsyncOperation<ABI::Windows::Devices::Geolocation::Geoposition*>;

    static inline WindowsLocation* instance = nullptr;

    explicit WindowsLocation(const HaylenNativeApi& engine);

    static void handleCurrent(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void handleWatch(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void handleStop(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void handlePermission(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    static void handleRequestPermission(void* user, std::uint64_t call, const char* method, const char* paramsJson, const HaylenNativeBuffer* buffers, std::size_t bufferCount);
    [[nodiscard]] static std::string describeResult(HRESULT result);

    void current(std::uint64_t call, const Json& params);
    void watch(std::uint64_t call, const Json& params);
    void stop(std::uint64_t call);
    void answerPermission(std::uint64_t call, const Json& params, bool asking);

    // Asks for the location where the app does not hold it yet, and fails the call with the refusal of `permission` where the person or the system refuses it. A Windows that tells nothing lets the use try.
    [[nodiscard]] bool require(std::uint64_t call, std::string_view permission) const;
    // Makes a `Geolocator` at the accuracy the call asks for, or fails the call where Windows has no location or the person turned it off.
    [[nodiscard]] GeolocatorPointer open(std::uint64_t call, bool precise) const;
    // Asks for a fresh fix, which ends on a thread of the Windows Runtime, so the thread of the library goes on meanwhile. The operation holds the `Geolocator` until it ends.
    void locate(std::uint64_t call, const GeolocatorPointer& geolocator, bool precise, double timeout) const;
    void settle(std::uint64_t call, Fix* finished, ABI::Windows::Foundation::AsyncStatus status, bool precise, double timeout) const;
    // Sends every place of the `Geolocator` as a batched event, and ends the watch when the person turns the location off or Windows refuses it.
    [[nodiscard]] std::unique_ptr<WindowsLocationWatch> follow(std::uint64_t call, const GeolocatorPointer& geolocator);
    // Ends a watch that Windows stopped, with the refusal when the person took the location back and the sentence of a location that is off otherwise.
    void endWatch();

    LocationBridge bridge;
    std::unique_ptr<WindowsLocationWatch> watching;
    WindowsLocationWorker worker;
};
