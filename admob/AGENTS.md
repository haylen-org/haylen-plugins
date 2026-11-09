# 🧭 AdMob — plugin guide

This folder is the AdMob plugin of Haylen: the banner, interstitial and rewarded ads of Google AdMob and the consent forms of the User Messaging Platform of Google, on iOS and Android. This file is binding for every change of the plugin.

## Rules

- The plugin follows the `AGENTS.md` of the Haylen repository and the plugin format of its `docs/platform/plugins.md`, with the writing, comment and naming standards of both.
- It wraps Google Mobile Ads and the User Messaging Platform alone, each at its latest release, pinned exactly: the Swift packages with `exactVersion` in `plugin.json` and the Gradle libraries with their version in `android/build.gradle.kts`. An update adopts the current API of the SDK everywhere, without a call that the SDK marks deprecated.
- Every ad and form that covers the app is a screen of the plugin, so the engine covers the app while it shows. The banner is a view of the overlay of the context, with `reserve` set, and the page that a tap on it opens covers the app through `coverApp` and `uncoverApp`.
- The app cannot close an ad or a form of Google, so the screens set an empty cancel handler, and a cancel of the app waits for the person to close them.
- The tracking prompt of Apple belongs to the App Tracking Transparency plugin, which the app asks with `tracking.requestPermission()` of that plugin. The plugin never asks for it and never requires that plugin.
- The Lua API of `source/init.lua` is the same on every platform, and it raises an error for a value that no platform takes, such as a banner position other than `top` and `bottom`. A platform without the plugin is a gap that `README.md` states with its reason.
- The plugin keeps the official test app IDs and ad units of Google in `README.md` and `admob.testUnits`, and never a real ID.
- Every change updates `README.md`, which documents the complete Lua API, the setup of each platform and what each platform answers.

## Verify

- Lua: `luac -p source/init.lua`.
- Apple: `swiftc -typecheck` of `apple/*.swift` with the Swift helpers and the plugin headers of the engine and the frameworks of the two Swift packages, for the SDK of the iOS simulator, without a warning.
- Android: a build of the module in the Android project of a test app, without a warning of the Kotlin compiler.
- A test app made with `haylen new` that references the plugin with `haylen plugin add <this folder> --reference`, with the test app IDs of Google, and whose `source/main.lua` asks for consent, starts the SDK, shows a banner and loads and shows an interstitial and a rewarded ad of `admob.testUnits`: `haylen app build` and `haylen app run` with `--target ios-simulator` and `--target android`, and the same in a C++ app made with `haylen new --kind cpp` on the iOS simulator. The banner, the interstitial ad and the rewarded ad show test ads in screenshots of the simulator and the emulator, and close.
