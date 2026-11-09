# 🧭 Location — plugin guide

The Location plugin reads the location of the device, one fix or its updates, and owns the permissions `location`, `preciseLocation` and `backgroundLocation`, on every platform of Haylen: Swift in `apple/`, a Kotlin library module with its foreground service in `android/`, an ES module in `web/` and a C++20 library in `native/` for the desktops, whose macOS part answers `unsupported` because the desktop player has no app bundle. Its Lua API lives in `source/init.lua`, and `README.md` documents it with what each platform answers.

## Rules

- The plugin follows the `AGENTS.md` of the Haylen repository and the plugin format of its `docs/platform/plugins.md`. Code, comments and docs are written in English, comments are rare complete sentences, and nothing names another engine or a company beyond the platforms.
- It uses the APIs of each platform alone, never a third-party library. The system services that a platform tells the location through, such as GeoClue over D-Bus on Linux, are part of the platform.
- The library of `native/` follows the native demo of the Haylen test project: `Location.cpp` holds only the C init function, which forwards to `MacosLocation`, `WindowsLocation` or `LinuxLocation`, the CMake project picks the files of each system, `LocationBridge` answers the engine, and every JSON value goes through nlohmann/json of the `haylen::native` target of the SDK. On Linux `GeoClueSession` holds the client of GeoClue on the thread of the library, and on Windows `WindowsLocationWorker`, `WindowsLocationPermission`, `WindowsLocationPlace` and `WindowsLocationWatch` serve `WindowsLocation`.
- The plugin owns its three permissions through the `permissions` plugin, which it lists in `dependencies`: its Lua module declares them with `permissions.declare` and offers `location.permission(name)` and `location.requestPermission(name)`, its native parts register and require them with `Permission` and `Permissions` of `permissions/apple/` on Apple platforms, `com.haylen.plugins.permissions` on Android and `registerPermission` and `requirePermission` of `haylen-plugin:permissions` on the web, and the desktop libraries answer `location.permission` and `location.requestPermission` with handlers of their own. A call requires `location`, or `preciseLocation` when it is precise, and a watch in the background `backgroundLocation` too.
- The plugin respects every limit of the platforms: iOS asks for the location in the background once, Android asks for it after the location in a prompt or a page of its own, the precise location of iOS is temporary, and Apple TV, Apple Vision Pro and the web read the location only in use. A limit is an answer of `unsupported` or `denied` with its reason, never a workaround.
- A place holds only what the system knows, and the altitude only above the sea.
- The Android module never declares the permissions of the location in the background, which only the apps that use them add, and checks them with `HaylenRequirements`.
- The updates belong to the process, so every native part stops them on `location.reset`, which the Lua API sends when it loads, and an `owner` of `location.watch` stops them through a task that the owner holds.
- Every change updates `README.md`, the Lua API and every native part in the same change, and the sample in `sample/` shows every call.

## Verify

- Run the sample with `haylen app run sample --target macos`, and on the iOS simulator, whose location `xcrun simctl location` sets, the Android emulator and the web with `--target`.
- Check the Lua with `luac -p source/init.lua`, the web module with `node --check web/location.js` and the Swift with `swiftc -typecheck` against the plugin API of the engine and the Swift of `permissions/apple/`, for iOS, Mac Catalyst, macOS, tvOS and visionOS.
- Compile the Kotlin module against the `haylen` library of the engine, and the library of `native/` against the desktop SDK of the engine with `find_package(haylen CONFIG REQUIRED)` and every warning of the engine as an error, with MSVC on Windows, GCC on Linux and Clang on macOS.
- The UI tests of `sample/ui-tests`: `haylen test --ui sample` with `--target ios-simulator`, `android`, and `ios` or `android` with `--device` on a phone, which answer the prompts, read the simulated place and watch it in the background.
