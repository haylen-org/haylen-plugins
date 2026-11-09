# The desktop part of the Motion plugin, a C++ library that the desktop player and the Windows and Linux apps load. The tooling builds the target named after the plugin, `motion`, against the installed SDK of the engine, whose target `haylen::native` gives it `haylen/platform/native/HaylenNative.h` and nlohmann/json. Windows reads the sensors of tablets and convertibles through `Windows.Devices.Sensors` with C++/WinRT, whose headers come with the Windows SDK, while macOS and Linux give apps no readings of motion sensors, which the library answers.
cmake_minimum_required(VERSION 3.28...4.4)
project(motion LANGUAGES CXX)

find_package(haylen CONFIG REQUIRED)

add_library(motion Motion.cpp MotionPlugin.cpp)
target_link_libraries(motion PRIVATE haylen::native)
target_compile_features(motion PRIVATE cxx_std_20)
if(WIN32)
  target_sources(motion PRIVATE MotionDeviceWindows.cpp)
  target_link_libraries(motion PRIVATE windowsapp user32)
else()
  target_sources(motion PRIVATE MotionDevice.cpp)
endif()
set_target_properties(motion PROPERTIES CXX_EXTENSIONS OFF CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)
