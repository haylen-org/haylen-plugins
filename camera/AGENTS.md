# 🧭 Camera — plugin guide

This folder is the Camera plugin of Haylen, which shows the cameras of the device in the video stream `camera`, takes photos as JPEG bytes and owns the permission `camera`, on every platform of Haylen: Swift in `apple/`, a Kotlin library module in `android/`, an ES module in `web/` and a C++ library in `native/` for the desktop player of macOS, with Objective-C++ for AVFoundation, Windows and Linux, which reads and writes the JSON of its calls with nlohmann/json. Its Lua API lives in `source/init.lua`, and `README.md` documents it with what each platform answers. This file is binding for every change of the plugin.

## Rules

- The plugin follows the `AGENTS.md` of the Haylen repository and the plugin format of its `docs/platform/plugins.md`. Code, comments and docs are written in English, comments are rare complete sentences, and nothing names another engine or a company beyond the platforms.
- It uses the APIs of each platform alone, never a third-party library.
- The plugin owns the permission `camera` through the `permissions` plugin, which it lists in `dependencies`: `Permission` and `Permissions` of `permissions/apple/` on Apple platforms, `Permission` and `Permissions` of `com.haylen.plugins.permissions` on Android, `registerPermission` and `requirePermission` of `haylen-plugin:permissions` on the web, and its own handlers `camera.permission` and `camera.requestPermission` in the desktop libraries. The Lua API declares the permission with `permissions.declare` and offers `camera.permission()` and `camera.requestPermission()`. Every call that uses the camera requires the permission first.
- The Lua API is the same on every platform, and every native part answers the same methods with the same codes and messages, which the native API of `README.md` lists. A platform that cannot serve a call fails it with the code `unsupported` and the exact reason.
- The capture belongs to the process, so every native part stops it on `camera.reset`, which the Lua API sends when it loads, and an `owner` of `camera.start` stops it through a task that the owner holds.
- Every change updates `README.md`, the Lua API and every native part in the same change, and the sample in `sample/` shows every call.

## Verify

- Run the sample on this machine with `haylen app run sample` and `--target macos`, and on the iOS simulator, the Android emulator and the web with `--target`. Simulators have no camera, so a physical device shows the picture.
- Check the Lua with `luac -p source/init.lua`, the web module with `node --check web/camera.js` and the Swift with `swiftc -typecheck` against the plugin API of the engine and the Swift of `../permissions/apple/`, for iOS, Mac Catalyst, macOS, tvOS and visionOS.
- Compile the Kotlin module against the `haylen` library of the engine, and build the library of `native/` against the installed desktop SDK of the engine, whose `haylen::native` target gives it `HaylenNative.h` and nlohmann/json, with every warning as an error: with Clang on macOS, MSVC on Windows and GCC on Linux.
- The UI tests of `sample/ui-tests`: `haylen test --ui sample` with `--target ios-simulator`, `android`, and `ios` or `android` with `--device` on a phone, which answer the prompt, start each camera and take a photo.
