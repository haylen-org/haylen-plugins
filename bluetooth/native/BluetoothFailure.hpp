#pragma once

#include <string>

// A failure that answers a call with its code and its sentence, which the library throws where a call cannot go on.
struct BluetoothFailure {
    std::string code;
    std::string message;
};
