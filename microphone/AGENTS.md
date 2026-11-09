# 🧭 Microphone — plugin guide

This folder is the Microphone plugin of Haylen, which records the microphone of the device as mono samples into an audio stream named after its rate and owns the permission `microphone`, on every platform of Haylen: Swift in `apple/`, a Kotlin library module in `android/`, an ES module and its audio worklet in `web/` and a C++ library in `native/` for the desktop player of macOS (Objective-C++ with AVFoundation), Windows (WASAPI) and Linux (ALSA), whose `MicrophonePlugin` answers the methods with nlohmann/json and whose `MicrophoneDevice` records through the API of each system. Its Lua API lives in `source/init.lua`, and `README.md` documents it with what each platform answers. This file is binding for every change of the plugin.

## Rules

- The plugin follows the `AGENTS.md` of the Haylen repository and the plugin format of its `docs/platform/plugins.md`. Code, comments and docs are written in English, comments are rare complete sentences, and nothing names another engine or a company beyond the platforms.
- It uses the APIs of each platform alone, never a third-party library. The system libraries that a platform records with, such as ALSA on Linux, are part of the platform.
- The plugin owns the permission `microphone` through the `permissions` plugin, which it lists in `dependencies`: `Permission` and `Permissions` of `permissions/apple/` on Apple platforms, `Permission` and `Permissions` of `com.haylen.plugins.permissions` on Android, `registerPermission` and `requirePermission` of `haylen-plugin:permissions` on the web, and its own handlers `microphone.permission` and `microphone.requestPermission` in the desktop libraries. The Lua API declares the permission with `permissions.declare` and offers `microphone.permission()` and `microphone.requestPermission()`. A start requires the permission first.
- A stream keeps the rate it opened with and belongs to the process, so each rate has a stream of its own, `microphone-<rate>`, and every native part converts the input to the rate that the Lua API sends.
- The Lua API is the same on every platform, and every native part answers the same methods with the same codes and messages, which the native API of `README.md` lists. A platform that cannot serve a call fails it with the code `unsupported` and the exact reason.
- The recording belongs to the process, so every native part stops it on `microphone.reset`, which the Lua API sends when it loads, and an `owner` of `microphone.start` stops it through a task that the owner holds.
- Every change updates `README.md`, the Lua API and every native part in the same change, and the sample in `sample/` shows every call.

## Verify

- Run the sample on this machine with `haylen app run sample` and `--target macos`, and on the iOS simulator, the Android emulator and the web with `--target`, the web in a browser with a fake microphone.
- Check the Lua with `luac -p source/init.lua`, the web modules with `node --check` and the Swift with `swiftc -typecheck` against the plugin API of the engine and the Swift of `../permissions/apple/`, for iOS, Mac Catalyst, macOS, tvOS and visionOS.
- Compile the Kotlin module against the `haylen` library of the engine, and the C++ library of `native/` against the installed desktop SDK of the engine with `-Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion -Wshadow -Werror` on macOS and Linux, and with MSVC on Windows.
- The UI tests of `sample/ui-tests`: `haylen test --ui sample` with `--target android`, and `ios` or `android` with `--device` on a phone, which answer the prompt, record at both rates, read the level and play the recording back.
