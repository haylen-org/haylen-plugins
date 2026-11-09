# 🧭 Dialogs — plugin guide

This plugin gives Haylen apps the native dialogs of the system: messages with up to three buttons, and the pickers of files to open, of a place to save data, of a folder and of photos. It follows the `AGENTS.md` of the Haylen repository and the plugin format that `docs/platform/plugins.md` of that repository describes, and this file only adds what is particular to it.

## Rules

- The Lua API of `source/` is the same on every platform. It checks every option with the messages that `README.md` lists, and the native parts trust what it sends.
- Every platform answers the five methods `dialogs.message`, `dialogs.openFiles`, `dialogs.saveFile`, `dialogs.openFolder` and `dialogs.openPhotos` with the JSON of the native API in `README.md`. A dialog that a platform lacks fails with the code `unsupported` and a sentence that says why, and `README.md` states the gap.
- The plugin uses the APIs of each platform alone: UIKit, AppKit and PhotosUI on Apple platforms, the Activity Result API and AppCompat on Android, the elements and pickers of the browser on the web, the shell and the Common Controls on Windows and GTK 3, loaded at run time, on Linux. It owns no permission, since every picker of the system hands over only what the person picks.
- A dialog never blocks the app. A cancel or a timeout of the app closes the dialog where the platform can, and the dialog that closes answers nothing.
- Picked files that have no path the app can read are copied into the folders that `README.md` lists, and the plugin empties them when it starts.
- The desktop part reads each request with `DialogsRequest` and answers with `DialogsAnswer` on every system, both with nlohmann/json of the SDK, and hands the request to `MacosDialogs`, `WindowsDialogs` or `LinuxDialogs`. The C ABI of `HaylenNativeApi` stays at the init function and the handlers, which forward to `DialogsPlugin`.
- Every change updates `README.md` and the sample in the same change.

## Layout

```text
plugin.json   The manifest.
source/       The Lua API: init.lua, and picked-files.lua, the call of the web that writes the picked bytes into the storage.
apple/        Swift for iOS, iPadOS, Mac Catalyst, visionOS, tvOS and the macOS app.
android/      The Kotlin library module.
web/          The ES module of the page.
native/       The desktop library in C++20: the requests and answers that every system shares, and the dialogs of each system, Objective-C++ on macOS for the desktop player, the shell on Windows and GTK 3 on Linux.
sample/       A Lua app that references the plugin with "path": ".." and shows every call.
```

## Verify

- Lua: `luac -p source/*.lua sample/source/*.lua`.
- Web: `node --check web/dialogs.js`.
- Apple: `swiftc -typecheck` of `apple/*.swift` with `engine/platform/apple/HaylenBridgeAsync.swift`, the bridging header `HaylenBridging.h` of the Apple template and the headers of the engine and of the data view of Varn from the SDK that `haylen engine` builds, for the iOS, macOS, tvOS, visionOS and Mac Catalyst SDKs.
- Android: a Gradle build of `android/` against the `haylen-plugins` library of the engine.
- Desktops: a build of `native/` against the installed desktop SDK of the engine with `-Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion -Wshadow -Werror` on macOS and Linux, and with MSVC and `/W4 /WX` on Windows.
- Every platform: `haylen app run sample --target <target>` and `haylen app verify sample --target <target>`, then press every button of the sample with the mouse, touch, the keyboard, a gamepad and a TV remote where the platform has them.
- The UI tests of `sample/ui-tests/apple`: `haylen test --ui sample --target ios-simulator` on an iPhone and an iPad simulator, which answer a message and pick a file and a photo. A run leaves `dialogs-report.json` in the files of the simulator, which the check then deletes.
