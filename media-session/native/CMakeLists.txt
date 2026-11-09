# The Windows part of the Media Session plugin, a C++ library that Windows apps load. The tooling builds the target named after the plugin, `media-session`, against the installed SDK of the engine, whose target `haylen::native` gives it `haylen/platform/native/HaylenNative.h` and nlohmann/json. It reaches the system media transport controls of the window of the app through the Windows Runtime of `runtimeobject`.
cmake_minimum_required(VERSION 3.28...4.4)
project(media-session LANGUAGES CXX)

find_package(haylen CONFIG REQUIRED)

add_library(media-session MediaSession.cpp MediaSessionPlugin.cpp WindowsMediaSession.cpp WindowsText.cpp)
target_link_libraries(media-session PRIVATE haylen::native runtimeobject shlwapi shcore)
target_compile_features(media-session PRIVATE cxx_std_20)
target_compile_definitions(media-session PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
set_target_properties(media-session PROPERTIES CXX_EXTENSIONS OFF CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)
