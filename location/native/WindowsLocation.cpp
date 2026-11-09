#include "WindowsLocation.hpp"

#include <array>
#include <charconv>
#include <functional>
#include <optional>

#include <roapi.h>
#include <wrl/event.h>
#include <wrl/wrappers/corewrappers.h>

#include "WindowsLocationPermission.hpp"
#include "WindowsLocationPlace.hpp"

using ABI::Windows::Devices::Geolocation::Geolocator;
using ABI::Windows::Devices::Geolocation::Geoposition;
using ABI::Windows::Devices::Geolocation::IGeolocator;
using ABI::Windows::Devices::Geolocation::IGeoposition;
using ABI::Windows::Devices::Geolocation::IPositionChangedEventArgs;
using ABI::Windows::Devices::Geolocation::IStatusChangedEventArgs;
using ABI::Windows::Devices::Geolocation::PositionAccuracy;
using ABI::Windows::Devices::Geolocation::PositionChangedEventArgs;
using ABI::Windows::Devices::Geolocation::PositionStatus;
using ABI::Windows::Devices::Geolocation::StatusChangedEventArgs;
using ABI::Windows::Foundation::AsyncStatus;
using ABI::Windows::Foundation::IAsyncInfo;
using ABI::Windows::Foundation::IAsyncOperationCompletedHandler;
using ABI::Windows::Foundation::ITypedEventHandler;
using ABI::Windows::Foundation::TimeSpan;
using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;
using Microsoft::WRL::Wrappers::HStringReference;

int WindowsLocation::initialize(const HaylenNativeApi* api) {
    if (api->version != HAYLEN_NATIVE_API_VERSION) {
        return 1;
    }
    // The init function runs again after a restart of the app, while the thread of the library and the watch belong to the process, so the plugin lives as long as the process.
    if (instance == nullptr) {
        instance = new WindowsLocation(*api);
    }

    api->registerHandler("location.reset", &WindowsLocation::handleStop, nullptr, instance);
    api->registerHandler("location.current", &WindowsLocation::handleCurrent, nullptr, instance);
    api->registerHandler("location.watch", &WindowsLocation::handleWatch, nullptr, instance);
    api->registerHandler("location.stop", &WindowsLocation::handleStop, nullptr, instance);
    api->registerHandler("location.permission", &WindowsLocation::handlePermission, nullptr, instance);
    api->registerHandler("location.requestPermission", &WindowsLocation::handleRequestPermission, nullptr, instance);
    api->registerPlugin("location");
    return 0;
}

WindowsLocation::WindowsLocation(const HaylenNativeApi& engine) : bridge(engine) {}

void WindowsLocation::handleCurrent(void* user, std::uint64_t call, const char*, const char* paramsJson, const HaylenNativeBuffer*, std::size_t) {
    static_cast<WindowsLocation*>(user)->current(call, LocationBridge::parse(paramsJson));
}

void WindowsLocation::handleWatch(void* user, std::uint64_t call, const char*, const char* paramsJson, const HaylenNativeBuffer*, std::size_t) {
    static_cast<WindowsLocation*>(user)->watch(call, LocationBridge::parse(paramsJson));
}

// Answers `location.stop` and `location.reset`, which the Lua API of every app sends as it loads, so a watch that an earlier app of the process left running stops.
void WindowsLocation::handleStop(void* user, std::uint64_t call, const char*, const char*, const HaylenNativeBuffer*, std::size_t) {
    static_cast<WindowsLocation*>(user)->stop(call);
}

void WindowsLocation::handlePermission(void* user, std::uint64_t call, const char*, const char* paramsJson, const HaylenNativeBuffer*, std::size_t) {
    static_cast<WindowsLocation*>(user)->answerPermission(call, LocationBridge::parse(paramsJson), false);
}

void WindowsLocation::handleRequestPermission(void* user, std::uint64_t call, const char*, const char* paramsJson, const HaylenNativeBuffer*, std::size_t) {
    static_cast<WindowsLocation*>(user)->answerPermission(call, LocationBridge::parse(paramsJson), true);
}

std::string WindowsLocation::describeResult(HRESULT result) {
    std::array<char, 16> digits{};
    const auto written = std::to_chars(digits.data(), digits.data() + digits.size(), static_cast<std::uint32_t>(result), 16);
    return "0x" + std::string(digits.data(), written.ptr);
}

void WindowsLocation::current(std::uint64_t call, const Json& params) {
    const std::optional<bool> precise = LocationBridge::readBool(params, "precise");
    const std::optional<double> timeout = LocationBridge::readNumber(params, "timeout");
    if (!precise || !timeout || *timeout <= 0) {
        bridge.fail(call, "The call \"location.current\" needs \"precise\" and a \"timeout\" of seconds above 0, which the Lua API of the plugin sends.", "invalidParams");
        return;
    }

    // clang-format off
    worker.post([this, call, precise = *precise, timeout = *timeout] {
        if (!require(call, precise ? "preciseLocation" : "location")) {
            return;
        }
        const GeolocatorPointer geolocator = open(call, precise);
        if (!geolocator) {
            return;
        }
        locate(call, geolocator, precise, timeout);
    });
    // clang-format on
}

void WindowsLocation::watch(std::uint64_t call, const Json& params) {
    const std::optional<bool> precise = LocationBridge::readBool(params, "precise");
    const std::optional<bool> background = LocationBridge::readBool(params, "background");
    const std::optional<double> distance = LocationBridge::readNumber(params, "distance");
    if (!precise || !background || !distance || *distance < 0) {
        bridge.fail(call, "The call \"location.watch\" needs \"precise\", \"background\" and a \"distance\" of meters, 0 or more, which the Lua API of the plugin sends.", "invalidParams");
        return;
    }

    // clang-format off
    worker.post([this, call, precise = *precise, background = *background, distance = *distance] {
        if (!require(call, precise ? "preciseLocation" : "location") || (background && !require(call, "backgroundLocation"))) {
            return;
        }
        watching.reset();
        const GeolocatorPointer geolocator = open(call, precise);
        if (!geolocator) {
            return;
        }
        geolocator->put_MovementThreshold(distance);
        watching = follow(call, geolocator);
        if (watching) {
            bridge.succeed(call, nullptr);
        }
    });
    // clang-format on
}

void WindowsLocation::stop(std::uint64_t call) {
    // clang-format off
    worker.post([this, call] {
        watching.reset();
        bridge.succeed(call, nullptr);
    });
    // clang-format on
}

void WindowsLocation::answerPermission(std::uint64_t call, const Json& params, bool asking) {
    const std::string name = LocationBridge::readText(params, "name").value_or("");
    // clang-format off
    worker.post([this, call, name, asking] {
        if (!LocationBridge::describePermission(name)) {
            bridge.fail(call, "The plugin \"location\" registers no permission \"" + name + "\" on this platform.", "unsupported");
            return;
        }
        const WindowsLocationPermission::Answer answer = asking ? WindowsLocationPermission::request() : WindowsLocationPermission::check();
        if (answer.state == "unsupported") {
            bridge.fail(call, answer.message, "unsupported");
            return;
        }
        bridge.succeed(call, answer.state);
    });
    // clang-format on
}

bool WindowsLocation::require(std::uint64_t call, std::string_view permission) const {
    const WindowsLocationPermission::Answer answer = WindowsLocationPermission::request();
    if (answer.state == "granted" || answer.state == "unknown") {
        return true;
    }
    if (answer.state == "unsupported") {
        bridge.fail(call, answer.message, "unsupported");
        return false;
    }
    bridge.fail(call, LocationBridge::refusal(permission), "denied");
    return false;
}

WindowsLocation::GeolocatorPointer WindowsLocation::open(std::uint64_t call, bool precise) const {
    ComPtr<IInspectable> created;
    GeolocatorPointer geolocator;
    const HRESULT activated = RoActivateInstance(HStringReference(RuntimeClass_Windows_Devices_Geolocation_Geolocator).Get(), &created);
    if (FAILED(activated) || FAILED(created.As(&geolocator))) {
        bridge.fail(call, "This Windows offers no location.", "unsupported");
        return nullptr;
    }
    geolocator->put_DesiredAccuracy(precise ? PositionAccuracy::PositionAccuracy_High : PositionAccuracy::PositionAccuracy_Default);

    PositionStatus status = PositionStatus::PositionStatus_NotInitialized;
    geolocator->get_LocationStatus(&status);
    if (status == PositionStatus::PositionStatus_NotAvailable) {
        bridge.fail(call, "This Windows offers no location.", "unsupported");
        return nullptr;
    }
    if (status == PositionStatus::PositionStatus_Disabled) {
        bridge.fail(call, LocationBridge::kLocationOff, "locationOff");
        return nullptr;
    }
    return geolocator;
}

void WindowsLocation::locate(std::uint64_t call, const GeolocatorPointer& geolocator, bool precise, double timeout) const {
    ComPtr<Fix> operation;
    const TimeSpan fresh{0};
    const TimeSpan limit{static_cast<INT64>(timeout * 1e7)};
    const HRESULT asked = geolocator->GetGeopositionAsyncWithAgeAndTimeout(fresh, limit, &operation);
    if (FAILED(asked)) {
        bridge.fail(call, "The location is unknown: Windows answered " + describeResult(asked) + ".", "locationUnknown");
        return;
    }

    // clang-format off
    const auto completed = Callback<IAsyncOperationCompletedHandler<Geoposition*>>([this, call, geolocator, precise, timeout](Fix* finished, AsyncStatus status) {
        settle(call, finished, status, precise, timeout);
        return S_OK;
    });
    // clang-format on
    const HRESULT waiting = operation->put_Completed(completed.Get());
    if (FAILED(waiting)) {
        bridge.fail(call, "The location is unknown: Windows answered " + describeResult(waiting) + ".", "locationUnknown");
    }
}

void WindowsLocation::settle(std::uint64_t call, Fix* finished, AsyncStatus status, bool precise, double timeout) const {
    ComPtr<IGeoposition> position;
    if (status == AsyncStatus::Completed && SUCCEEDED(finished->GetResults(&position))) {
        const std::optional<Json> place = WindowsLocationPlace::read(position.Get());
        if (place) {
            bridge.succeed(call, *place);
            return;
        }
    }

    ComPtr<IAsyncInfo> information;
    HRESULT error = E_FAIL;
    if (SUCCEEDED(finished->QueryInterface(IID_PPV_ARGS(&information)))) {
        information->get_ErrorCode(&error);
    }
    if (error == E_ACCESSDENIED) {
        bridge.fail(call, LocationBridge::refusal(precise ? "preciseLocation" : "location"), "denied");
        return;
    }
    if (error == HRESULT_FROM_WIN32(ERROR_TIMEOUT)) {
        bridge.fail(call, "No fix of the location came within " + LocationBridge::seconds(timeout) + " seconds.", "timeout");
        return;
    }
    bridge.fail(call, "The location is unknown: Windows answered " + describeResult(error) + ".", "locationUnknown");
}

std::unique_ptr<WindowsLocationWatch> WindowsLocation::follow(std::uint64_t call, const GeolocatorPointer& geolocator) {
    EventRegistrationToken positions{};
    EventRegistrationToken statuses{};
    // clang-format off
    const auto changed = Callback<ITypedEventHandler<Geolocator*, PositionChangedEventArgs*>>([this](IGeolocator*, IPositionChangedEventArgs* arguments) {
        ComPtr<IGeoposition> position;
        if (FAILED(arguments->get_Position(&position))) {
            return S_OK;
        }
        const std::optional<Json> place = WindowsLocationPlace::read(position.Get());
        if (place) {
            bridge.emit("location.changed", *place, HAYLEN_NATIVE_EMIT_BATCHED);
        }
        return S_OK;
    });
    const auto statusChanged = Callback<ITypedEventHandler<Geolocator*, StatusChangedEventArgs*>>([this](IGeolocator*, IStatusChangedEventArgs* arguments) {
        PositionStatus status = PositionStatus::PositionStatus_Ready;
        if (SUCCEEDED(arguments->get_Status(&status)) && status == PositionStatus::PositionStatus_Disabled) {
            worker.post(std::bind_front(&WindowsLocation::endWatch, this));
        }
        return S_OK;
    });
    // clang-format on
    const HRESULT added = geolocator->add_PositionChanged(changed.Get(), &positions);
    if (FAILED(added)) {
        bridge.fail(call, "The location gives no updates: Windows answered " + describeResult(added) + ".", "locationUnknown");
        return nullptr;
    }
    geolocator->add_StatusChanged(statusChanged.Get(), &statuses);
    return std::make_unique<WindowsLocationWatch>(geolocator, positions, statuses);
}

void WindowsLocation::endWatch() {
    if (!watching) {
        return;
    }
    watching.reset();
    const bool refused = WindowsLocationPermission::check().state == "denied";
    const std::string message = refused ? LocationBridge::refusal("location") : std::string(LocationBridge::kLocationOff);
    bridge.emit("location.stopped", LocationBridge::failure(message, refused ? "denied" : "locationOff"), 0);
}
