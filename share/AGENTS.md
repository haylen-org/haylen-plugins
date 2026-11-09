# 🧭 Share — plugin guide

This folder is the Share plugin of Haylen: the share sheet of the system for a text, a url and files, which answers whether the person shared or closed it. This file is binding for every change of the plugin.

## Rules

- The plugin follows the `AGENTS.md` of the Haylen repository and the plugin format of its `docs/platform/plugins.md`, with the writing, comment and naming standards of both.
- It uses the APIs of each platform alone, `UIActivityViewController` and `NSSharingServicePicker` on Apple platforms and in the macOS desktop player, the chooser of `ACTION_SEND` with a `FileProvider` of its own on Android, the share UI of `IDataTransferManagerInterop` on Windows and the Web Share API on the web, and never a third-party library.
- The Lua API of `source/init.lua` is the same on every platform. A platform that cannot serve a call fails it with a code and a sentence that says why, and a platform without the plugin is a gap that `README.md` states with its reason.
- The desktop part in `native/` is C++20, with Objective-C++ for AppKit on macOS and C++/WinRT on Windows. Every system reads the share with `ShareRequest` and answers with `ShareAnswer`, which parse and write the JSON with nlohmann/json of the SDK, and the C ABI of `HaylenNativeApi` stays at the init function and the handler, which forward to `SharePlugin`.
- Files cross the bridge as bytes, which each native part writes into a folder of its own that it empties before every share.
- The sheet covers the app while it shows, and its anchor arrives in fractions of the window, which the Lua API computes from a rectangle in design units.
- Every change updates `README.md`, which documents the complete Lua API, the setup of each platform and what each platform answers, and the sample in `sample/`, which shows every kind of share.

## Verify

- Lua: `luac -p source/init.lua sample/source/main.lua`.
- Web: `node --check web/share.js`.
- Apple: `swiftc -typecheck` of `apple/*.swift` with the Swift helpers and the plugin headers of the engine, for the SDKs of iOS, Mac Catalyst, visionOS and macOS, and a build of `native/` against the installed desktop SDK of the engine with `-Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion -Wshadow -Werror`.
- Windows: a build of `native/` with MSVC and `/W4 /WX`, and a test host that loads the library and calls `share.share` over a window of its own.
- Android: a compile of the Kotlin and the lint of the module against the `haylen-plugins` library of the engine.
- The sample: `haylen app run sample` and `haylen app verify sample` on each target of the platforms that the plugin declares, such as the player of this Mac, `--target ios-simulator`, `android`, `web` and `windows`, where each kind of share opens the sheet and answers.
- The UI tests of `sample/ui-tests/apple`: `haylen test --ui sample --target ios-simulator` on an iPhone and an iPad simulator, which complete and close the sheet.
