# 🧭 App Tracking Transparency — plugin guide

This folder is the App Tracking Transparency plugin of Haylen: the permission `tracking`, which the plugin owns through the `permissions` plugin, with the prompt of Apple platforms, and the advertising identifier of the device. This file is binding for every change of the plugin.

## Rules

- The plugin follows the `AGENTS.md` of the Haylen repository and the plugin format of its `docs/platform/plugins.md`, with the writing, comment and naming standards of both.
- It uses the frameworks of the system alone, AppTrackingTransparency and AdSupport, and never a third-party library.
- Android and the web show no prompt for tracking, so their parts register the permission `tracking` with a state of `granted`: a `Permission` without permissions of the manifest on Android and a `check` that answers `granted` on the web. Their `advertisingId` fails with the code `unsupported` and a sentence that says why, since the advertising identifier of Android belongs to Google Play services, which the plugin does not bring, and the web has none.
- The plugin owns its permission through the `permissions` plugin, which it lists in `dependencies`: `Permission` and `Permissions` of `permissions/apple/` on Apple platforms, the classes of `com.haylen.plugins.permissions` on Android and `registerPermission` and `requirePermission` of `haylen-plugin:permissions` on the web. The app checks and asks for it with `tracking.permission()` and `tracking.requestPermission()`, which the Lua module declares through `permissions.declare`.
- Every call that needs tracking asks for the permission through `Permissions.require` or `requirePermission` first, so it fails with the code `denied` while the person does not allow it, instead of answering the identifier of zeros that the system gives then.
- The plugin maps the authorization of the system to the states of the Permissions plugin without retries: `notDetermined` is `prompt` and `restricted` is `denied`. The system shows the prompt only to an active app, and a request of an app that is not active answers `notDetermined` at once and leaves a prompt that shows later without telling the app, so the plugin asks only while the app is active and answers `prompt` otherwise.
- The Lua API of `source/init.lua` is the same on every platform. A platform without the plugin is a gap that `README.md` states with its reason.
- Every change updates `README.md`, which documents the complete Lua API, the setup and what each platform answers.

## Verify

- Lua: `luac -p source/init.lua`.
- Web: `node --check web/app-tracking-transparency.js`.
- Apple: `swiftc -typecheck` of `apple/*.swift` and `../permissions/apple/*.swift` with the Swift helpers and the plugin headers of the engine, for the SDKs of iOS, Mac Catalyst, tvOS and macOS.
- A test app made with `haylen new` that references the plugin and the `permissions` plugin with `haylen plugin add <folder> --reference`, and whose `source/main.lua` reads the permission, requests it and asks for the advertising identifier: `haylen app build` and `haylen app run` with `--target ios-simulator`, `tvos-simulator`, `catalyst`, `macos`, `android` and `web`, and the same in a C++ app made with `haylen new --kind cpp`.
- Its UI tests with `haylen test --ui <app> --target ios-simulator`, which tap `Allow` in the prompt of the system in one run and `Ask App Not to Track` in another, and check the states and the identifier that the app shows.
