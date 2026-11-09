# 🧭 Firebase Crashlytics — plugin guide

This folder is the Firebase Crashlytics plugin of Haylen: the reports of native crashes and of every Lua error that stops the app, with the stack of the Lua code, and the log, the user, the custom keys and the recorded errors of the app, reported through the default Firebase app that the plugin `firebase` configures. This file is binding for every change of the plugin.

## Rules

- The plugin follows the `AGENTS.md` of the Haylen repository and the plugin format of its `docs/platform/plugins.md`, with the writing, comment, naming and clean code standards of both.
- It requires the plugin `firebase` and wraps the Crashlytics SDK of each platform and no other third-party library: `FirebaseCrashlytics` of the Firebase Apple SDK as a Swift package with `exactVersion` and its script `run` for the symbols of Release builds, and `firebase-crashlytics` through the Firebase BoM with its version and the Crashlytics Gradle plugin with its version on Android. Every one stays at the latest release, at the same versions as the plugin `firebase`, and the path of the script `run` in `plugin.json` follows the checkout of the package.
- The errors of the app arrive through the hooks of the plugin API of Haylen that the section "Errors of the app" of `docs/platform/plugins.md` names, `appDidFail(with:)` on Apple platforms and `onAppError` on Android, and become non-fatal errors whose frames are the frames of the Lua stack, while the parameter `reportLuaErrors` is true.
- Every call checks that the default Firebase app runs and fails with the code `notConfigured` otherwise, since the Apple SDK stops the process when Crashlytics runs without it. A parameter that a native part cannot take fails with the code `invalidParams`, and the Lua API checks the types of its arguments first.
- The Lua API of `source/init.lua` is the same on every platform, and a platform without the plugin is a gap that `README.md` states with its reason.
- Every change updates `README.md`, which documents the complete Lua API, the setup of each platform and what each platform answers.

## Verify

- Lua: `luac -p source/init.lua`.
- The test app that the `AGENTS.md` of the plugin `firebase` describes, on the iOS simulator and the Android emulator, where every call answers and the Lua error at its end reaches Crashlytics, which the log of Crashlytics shows with its debug output on, `-FIRDebugEnabled` on iOS and `adb shell setprop log.tag.FirebaseCrashlytics DEBUG` on Android, and `haylen app build` of each target, and the C++ app on the iOS simulator.
- A real Firebase project shows the crash of `crashlytics.crash()` and the Lua errors in its console after the next start of the app.
