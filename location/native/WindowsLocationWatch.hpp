#pragma once

#include <windows.h>

#include <windows.devices.geolocation.h>
#include <wrl/client.h>

// A watch of the location: its `Geolocator` and the registrations of its events, which end with it.
class WindowsLocationWatch final {
  public:
    WindowsLocationWatch(Microsoft::WRL::ComPtr<ABI::Windows::Devices::Geolocation::IGeolocator> watched, EventRegistrationToken positionToken, EventRegistrationToken statusToken);
    WindowsLocationWatch(const WindowsLocationWatch&) = delete;
    WindowsLocationWatch& operator=(const WindowsLocationWatch&) = delete;
    ~WindowsLocationWatch();

  private:
    Microsoft::WRL::ComPtr<ABI::Windows::Devices::Geolocation::IGeolocator> geolocator;
    EventRegistrationToken positions;
    EventRegistrationToken statuses;
};
