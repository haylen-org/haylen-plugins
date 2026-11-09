# 🧭 Local Network — plugin guide

The Local Network plugin owns the permission `localNetwork`, shows the picker of the services of one type on the local network and advertises a service of the app, with Swift in `apple/`, a Kotlin library module in `android/` and an ES module in `web/`. Its Lua API lives in `source/init.lua`, and `README.md` documents it with what each platform asks for and answers. This file is binding for every change of the plugin.

## Rules

- The plugin follows the `AGENTS.md` of the Haylen repository and the plugin format of its `docs/platform/plugins.md`, with the writing, comment and naming standards of both.
- It uses the APIs of each platform alone, `NWBrowser`, `NWConnection` and DNS-SD on Apple platforms, `NsdManager` with its picker on Android and the Permissions API on the web, and never a third-party library. The app owns its sockets through the module `socket`, so the plugin finds, resolves and advertises services and never carries their data.
- The plugin owns its permission through the `permissions` plugin, which it lists in `dependencies`: its Lua module declares it with `permissions.declare`, the Apple part registers it with `Permissions.register` of `permissions/apple/`, the Android part with `com.haylen.plugins.permissions`, and the web part with `registerPermission` of `haylen-plugin:permissions`.
- The plugin respects every limit of the platforms. Apple platforms tell an app nothing of the local network prompt, so the permission answers `unknown` there and the plugin never guesses an answer from a failed search. Android 17 gates the local network behind `ACCESS_LOCAL_NETWORK` only for an app that targets it, and the picker of `NsdManager` comes with the update 22 of the extensions of Android 13, so an older device answers `unsupported` with its reason. Browsers give pages no API of DNS-SD.
- Apple platforms find and advertise only the types of `NSBonjourServices`, which the parameter `bonjourServices` fills, and the plugin checks the type before it calls the system.
- The advertisement belongs to the process, so every native part stops it on `local-network.reset`, which the Lua API sends when it loads, and an `owner` of `localNetwork.advertise` stops it through a task that the owner holds.
- Windows and Linux have no native part, since their desktops reach the local network without a permission, and the README states the gap.
- Every change updates `README.md`, the Lua API and every native part in the same change, and the sample in `sample/` with its UI tests.

## Verify

- Lua: `luac -p source/init.lua sample/source/main.lua`.
- Web: `node --check web/local-network.js`.
- Apple: `swiftc -typecheck` in the Swift 6 language mode of `apple/*.swift` with the Swift of `permissions/apple/`, the Swift helpers and the plugin headers of the engine, for the SDKs of iOS, Mac Catalyst, tvOS, visionOS and macOS.
- Android: a compile of the Kotlin module against the `haylen-plugins` library of the engine, which the build of the sample makes.
- The sample: its UI tests with `haylen test --ui sample --target ios-simulator` and `--target android` on an emulator of Android 17, whose picker of the system the Android test answers.
