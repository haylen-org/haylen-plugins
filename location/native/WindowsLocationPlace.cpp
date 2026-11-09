#include "WindowsLocationPlace.hpp"

#include <cmath>

using ABI::Windows::Devices::Geolocation::AltitudeReferenceSystem;
using ABI::Windows::Devices::Geolocation::BasicGeoposition;
using ABI::Windows::Devices::Geolocation::IGeocoordinate;
using ABI::Windows::Devices::Geolocation::IGeocoordinateWithPoint;
using ABI::Windows::Devices::Geolocation::IGeopoint;
using ABI::Windows::Devices::Geolocation::IGeoposition;
using ABI::Windows::Devices::Geolocation::IGeoshape;
using ABI::Windows::Foundation::DateTime;
using ABI::Windows::Foundation::IReference;
using Microsoft::WRL::ComPtr;

std::optional<LocationBridge::Json> WindowsLocationPlace::read(IGeoposition* position) {
    ComPtr<IGeocoordinate> coordinate;
    if (FAILED(position->get_Coordinate(&coordinate))) {
        return std::nullopt;
    }
    ComPtr<IGeocoordinateWithPoint> located;
    ComPtr<IGeopoint> point;
    if (FAILED(coordinate.As(&located)) || FAILED(located->get_Point(&point))) {
        return std::nullopt;
    }
    BasicGeoposition basic{};
    double accuracy = 0;
    DateTime timestamp{};
    if (FAILED(point->get_Position(&basic)) || FAILED(coordinate->get_Accuracy(&accuracy)) || FAILED(coordinate->get_Timestamp(&timestamp))) {
        return std::nullopt;
    }

    const double seconds = static_cast<double>(timestamp.UniversalTime - kUnixEpoch) / 1e7;
    LocationBridge::Json place = {{"latitude", basic.Latitude}, {"longitude", basic.Longitude}, {"accuracy", accuracy}, {"timestamp", seconds}};
    if (isAboveSea(coordinate.Get(), point)) {
        place["altitude"] = basic.Altitude;
    }
    ComPtr<IReference<double>> speed;
    coordinate->get_Speed(&speed);
    addKnown(place, "speed", speed.Get());
    ComPtr<IReference<double>> heading;
    coordinate->get_Heading(&heading);
    addKnown(place, "heading", heading.Get());
    return place;
}

bool WindowsLocationPlace::isAboveSea(IGeocoordinate* coordinate, const ComPtr<IGeopoint>& point) {
    ComPtr<IReference<double>> altitudeAccuracy;
    if (FAILED(coordinate->get_AltitudeAccuracy(&altitudeAccuracy)) || !altitudeAccuracy) {
        return false;
    }
    ComPtr<IGeoshape> shape;
    AltitudeReferenceSystem reference = AltitudeReferenceSystem::AltitudeReferenceSystem_Unspecified;
    if (FAILED(point.As(&shape)) || FAILED(shape->get_AltitudeReferenceSystem(&reference))) {
        return false;
    }
    return reference == AltitudeReferenceSystem::AltitudeReferenceSystem_Geoid;
}

void WindowsLocationPlace::addKnown(LocationBridge::Json& place, const char* key, IReference<double>* reference) {
    double value = 0;
    if (reference == nullptr || FAILED(reference->get_Value(&value)) || std::isnan(value)) {
        return;
    }
    place[key] = value;
}
