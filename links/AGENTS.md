# 🧭 Links — plugin guide

The Links plugin opens a url with the app that the system picks for it, on every platform of Haylen: Swift in `apple/`, a Kotlin library module in `android/`, an ES module in `web/` and a C++ library in `native/`, with Objective-C++ on macOS, for the desktop player, Windows and Linux. Its Lua API lives in `source/init.lua`, and `README.md` documents it with what each platform answers. This file is binding for every change of the plugin.

## Rules

- The plugin follows the `AGENTS.md` of the Haylen repository and the plugin format of its `docs/platform/plugins.md`. Code, comments and docs are written in English, comments are rare complete sentences, and nothing names another engine or a company beyond the platforms.
- It uses the APIs of each platform alone, never a third-party library.
- The Lua API is the same on every platform. A url that no app takes fails with the code `unsupported` and the reason, a tab that a browser blocks fails with `denied`, and a refusal that nothing awaits is logged once and never stops the app.
- The plugin opens urls and nothing else. The links that open the app reach it as the event `linkOpened` of the engine.
- Every change updates `README.md`, the Lua API and every native part in the same change, and the sample in `sample/` shows every call.

## Verify

- Run the sample on this machine with `haylen app run sample`, and on the iOS simulator, the Android emulator and the web with `--target`.
- Check the Lua with `luac -p source/init.lua`, the web module with `node --check web/links.js` and the Swift with `swiftc -typecheck` against the plugin API of the engine.
- Build the sample for Windows and Linux with `haylen app build sample --target windows` or `linux`, where the C++ library opens urls through the shell and `xdg-open`. The library reads and writes its JSON with nlohmann/json, which the target `haylen::native` of the desktop SDK gives it, and never by hand, and it builds without warnings with `-Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion -Wshadow -Werror`.
