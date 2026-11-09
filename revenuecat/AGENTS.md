# 🧭 RevenueCat — plugin guide

This folder is the RevenueCat plugin of Haylen: in-app purchases and subscriptions through RevenueCat on Apple platforms and Android, with offerings, purchases, restores, entitlements and the user of the app. This file is binding for every change of the plugin.

## Rules

- The plugin follows the `AGENTS.md` of the Haylen repository and the plugin format of its `docs/platform/plugins.md`, with the writing, comment and naming standards of both.
- It wraps the RevenueCat SDK alone, at its latest release, pinned exactly: the Swift package with `exactVersion` in `plugin.json` and the Gradle library with its version in `android/build.gradle.kts`. An update adopts the current API of the SDK everywhere and reads the migration notes of every major version.
- The purchase is a screen of the plugin, so the engine covers the app while the sheet of the store shows. The app cannot close that sheet, so the screen sets an empty cancel handler.
- Failures carry one vocabulary of codes on every platform: each error code of RevenueCat in camelCase without the word `Error`, from the tables of `RevenueCatErrors` in the Apple and Android parts, which name every case of the SDK, and `cancelled` for a purchase that the person closes. A new error code of the SDK gets its name in both tables.
- Customer info that changes on its own reaches the app as the retained event `customerInfoUpdated`.
- The Lua API of `source/init.lua` is the same on every platform. A platform without the plugin is a gap that `README.md` states with its reason.
- The repository never holds an API key of RevenueCat. Checks use a placeholder key, from an environment variable or a plainly fake value, so the calls that need the backend fail with their typed codes.
- Every change updates `README.md`, which documents the complete Lua API, the setup of each platform and what each platform answers.

## Verify

- Lua: `luac -p source/init.lua`.
- Apple: a build of a test app for each platform that `plugin.json` lists, without a warning of the Swift compiler in the sources of the plugin.
- Android: a build of the module in the Android project of a test app, without a warning of the Kotlin compiler.
- A test app made with `haylen new` that references the plugin with `haylen plugin add <this folder> --reference`, with a placeholder key, and whose `source/main.lua` calls every function of the Lua API: `haylen app build` and `haylen app run` with `--target ios-simulator`, `tvos-simulator`, `catalyst`, `macos` and `android`, and the same in a C++ app made with `haylen new --kind cpp` on the iOS simulator. Every call answers or fails with a typed code, and none crashes.
- Real purchases, restores and renewals need a RevenueCat project with products in the stores, sandbox accounts and a device, which a person checks.
