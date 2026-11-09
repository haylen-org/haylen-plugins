#include "WindowsLocationWatch.hpp"

#include <utility>

WindowsLocationWatch::WindowsLocationWatch(Microsoft::WRL::ComPtr<ABI::Windows::Devices::Geolocation::IGeolocator> watched, EventRegistrationToken positionToken, EventRegistrationToken statusToken) : geolocator(std::move(watched)), positions(positionToken), statuses(statusToken) {}

WindowsLocationWatch::~WindowsLocationWatch() {
    geolocator->remove_PositionChanged(positions);
    geolocator->remove_StatusChanged(statuses);
}
