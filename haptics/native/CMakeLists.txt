# The desktop part of the Haptics plugin, a C++ library that the desktop player and the Windows and Linux apps load. The tooling builds the target named after the plugin, `haptics`, against the installed SDK of the engine, whose target `haylen::native` gives it `haylen/platform/native/HaylenNative.h` and nlohmann/json. A Mac plays the feedback of its trackpad through AppKit in Objective-C++.
cmake_minimum_required(VERSION 3.28...4.4)
project(haptics LANGUAGES CXX)

find_package(haylen CONFIG REQUIRED)

add_library(haptics Haptics.cpp HapticsPlugin.cpp)
target_link_libraries(haptics PRIVATE haylen::native)
target_compile_features(haptics PRIVATE cxx_std_20)
if(APPLE)
  enable_language(OBJCXX)
  target_sources(haptics PRIVATE MacTrackpad.mm)
  set_source_files_properties(MacTrackpad.mm PROPERTIES COMPILE_OPTIONS -fobjc-arc)
  target_link_libraries(haptics PRIVATE "-framework AppKit")
endif()
set_target_properties(haptics PROPERTIES CXX_EXTENSIONS OFF CXX_VISIBILITY_PRESET hidden OBJCXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)
