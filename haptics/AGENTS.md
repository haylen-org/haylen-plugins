# 🧭 Haptics — plugin guide

This folder is the Haptics plugin of Haylen: the vibration of the device and the impacts, selection ticks and notification feedback of its haptic engine, with Swift in `apple/`, a Kotlin library module in `android/`, an ES module in `web/` and a C++ library in `native/`, with Objective-C++ on macOS, for the desktop player, Windows and Linux. The plugin owns no permission. This file is binding for every change of the plugin.

## Rules

- The plugin follows the `AGENTS.md` of the Haylen repository and the plugin format of its `docs/platform/plugins.md`, with the writing, comment and naming standards of both.
- It uses the APIs of each platform alone, Core Haptics and the feedback generators of UIKit on the iPhone, `NSHapticFeedbackManager` of AppKit on the Mac, the vibrator and the haptic feedback constants of Android, and the Vibration API on the web, and never a third-party library.
- The Lua API of `source/init.lua` is the same on every platform. A device that cannot play a call fails it with the code `unsupported` and the exact reason, a browser that refuses a vibration fails it with `denied`, and a refusal that nothing awaits is logged once per sentence and never stops the app.
- The plugin never guesses what the device felt. It answers what the platform tells, and `README.md` says where the platform tells nothing, such as the trackpad of a Mac.
- The Android module declares `android.permission.VIBRATE`, a permission that Android grants at install, and checks it with `HaylenRequirements` before it vibrates.
- The rumble of gamepads belongs to the engine, as `input.rumble`, and never to this plugin.
- Every change updates `README.md`, which documents the complete Lua API, the setup of each platform and what each platform answers, and the sample in `sample/`, which shows every call.

## Verify

- Lua: `luac -p source/init.lua sample/source/main.lua`.
- Web: `node --check web/haptics.js`.
- Apple: `swiftc -typecheck` of `apple/*.swift` with the Swift helpers and the plugin headers of the engine, for the SDKs of iOS, Mac Catalyst, tvOS, visionOS and macOS.
- Android: a compile of the Kotlin and the lint of the module against the `haylen-plugins` library of the engine.
- Desktop: a build of `native/` against the desktop SDK of the engine with `-Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion -Wshadow -Werror` on macOS and Linux and with MSVC and `/W4 /WX` on Windows. The library reads and writes its JSON with nlohmann/json, which the target `haylen::native` of the SDK gives it, and never by hand.
- The sample: `haylen app run sample` and `haylen app verify sample` on this machine, and with `--target` on the iOS simulator, the Android emulator and the web. Only a physical iPhone and an Android phone feel the haptics.
- The UI tests of `sample/ui-tests`: `haylen test --ui sample` with `--target ios-simulator`, `android`, and `ios` or `android` with `--device` on a phone, which check the answer of every feedback.
