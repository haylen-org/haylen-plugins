#pragma once

#include <cstdint>
#include <optional>

#include <windows.h>

#include <windows.devices.geolocation.h>
#include <wrl/client.h>

#include "LocationBridge.hpp"

// The places of the `Geolocator` as the places of the plugin: degrees, meters and seconds since 1970, without the fields that Windows does not know.
class WindowsLocationPlace final {
  public:
    [[nodiscard]] static std::optional<LocationBridge::Json> read(ABI::Windows::Devices::Geolocation::IGeoposition* position);

  private:
    // The time of the Windows Runtime counts hundreds of nanoseconds from 1601, which is this many before 1970.
    static constexpr std::int64_t kUnixEpoch = 116444736000000000;

    // A place holds the altitude above the sea, which Windows tells for a measured point whose reference system is the geoid.
    [[nodiscard]] static bool isAboveSea(ABI::Windows::Devices::Geolocation::IGeocoordinate* coordinate, const Microsoft::WRL::ComPtr<ABI::Windows::Devices::Geolocation::IGeopoint>& point);
    // A value that Windows leaves out, or gives as not a number, such as the heading of a device that stands still, stays out of the place.
    static void addKnown(LocationBridge::Json& place, const char* key, ABI::Windows::Foundation::IReference<double>* reference);
};
