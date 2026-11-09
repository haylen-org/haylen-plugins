# 🧭 Media Session — plugin guide

This folder is the Media Session plugin of Haylen: what the app plays in the now-playing controls of the system, the commands of those controls, of the media keys and of the buttons of headsets and remotes, and the declarations that keep the sound of the app playing in the background, with Swift in `apple/`, a Kotlin library module in `android/`, an ES module in `web/` and a C++ library in `native/` for Windows. The plugin owns no permission. This file is binding for every change of the plugin.

## Rules

- The plugin follows the `AGENTS.md` of the Haylen repository and the plugin format of its `docs/platform/plugins.md`, with the writing, comment and naming standards of both.
- It uses the APIs of each platform alone, the info center and the remote commands of MediaPlayer on Apple platforms, the media session, the media notification and a foreground service of Android, the Media Session API on the web and the system media transport controls of the Windows Runtime, and never a third-party library.
- The Lua API of `source/init.lua` is the same on every platform. It checks every option in Lua with the sentences that its README lists, and `setNowPlaying` and `clear` are sends that answer nothing, so an app calls them as often as what plays changes, while `nowPlaying` reads back what the controls of the system hold.
- The controls belong to the process, so the Lua module clears them as it loads, and every app that starts takes the controls of an earlier app away.
- The commands reach the app as the event `media-session.command` with `{command}` and the `position` of a seek, with the names of the commands of the Lua API on every platform.
- The plugin declares what keeps an app that shows what it plays playing in the background, the mode `audio` of `UIBackgroundModes` on iOS, tvOS and visionOS and the foreground service of the type `mediaPlayback` with its permissions on Android, and the engine keeps its output running there because the app declares it. The media notification needs no `POST_NOTIFICATIONS`, so the module never declares it.
- Linux has no native part, since the plugin does not serve the MPRIS interface, and the README states the gap.
- Every change updates `README.md`, which documents the complete Lua API, the setup of each platform and what each platform answers, and the sample in `sample/`, which plays a loop in the controls and logs every command.

## Verify

- Lua: `luac -p source/init.lua sample/source/main.lua`.
- Web: `node --check web/media-session.js`.
- Apple: `swiftc -typecheck` of `apple/*.swift` with the Swift helpers and the plugin headers of the engine, for the SDKs of iOS, Mac Catalyst, tvOS, visionOS and macOS.
- Android: a compile of the Kotlin and the lint of the module against the `haylen-plugins` library of the engine, and its instrumented test `MediaSessionArtworkTest` on the emulator with `gradle connectedAndroidTest`.
- Windows: a build of `native/` against the desktop SDK of the engine with MSVC and `/W4 /WX`. The library reads and writes its JSON with nlohmann/json, which the target `haylen::native` of the SDK gives it, and never by hand.
- The sample: `haylen app run sample` with `--target` on macOS, the iOS simulator, the Android emulator, the web and Windows, and its UI tests with `haylen test --ui sample --target ios-simulator` and `--target android`. The lock screen of a physical iPhone and the media keys of a keyboard show the commands that the simulators cannot send.
