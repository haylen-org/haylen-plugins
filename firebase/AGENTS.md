# 🧭 Firebase — plugin guide

This folder is the Firebase plugin of Haylen: the default Firebase app of the Firebase project of an app, configured from the configuration files of the project before any Lua runs, which the plugins `firebase-analytics`, `firebase-crashlytics` and `firebase-messaging` use. This file is binding for every change of the plugin.

## Rules

- The plugin follows the `AGENTS.md` of the Haylen repository and the plugin format of its `docs/platform/plugins.md`, with the writing, comment, naming and clean code standards of both.
- It wraps the Firebase SDK of each platform and no other third-party library: `FirebaseCore` of the Firebase Apple SDK as a Swift package with `exactVersion`, `firebase-common` through the Firebase BoM with its version and the Google services Gradle plugin with its version on Android, and the app module of the Firebase JavaScript SDK from the address of its version on the web. Every one stays at the latest release, and the four Firebase plugins pin the same versions, since the Swift package `Firebase` of two plugins must agree.
- The configuration comes only from the parameters `servicesPlist`, `servicesJson` and `webConfig`, never from a file the plugin guesses. A missing or invalid configuration leaves Firebase off with one line of the log, and every call of the Firebase plugins then fails with the code `notConfigured`.
- The plugin turns off the swizzling of the application delegate by Firebase, since the runtime of Haylen hands the events of the app to the plugins.
- The Lua API of `source/init.lua` is the same on every platform, and a platform without the plugin is a gap that `README.md` states with its reason.
- Every change updates `README.md`, which documents the complete Lua API, the setup of each platform and what each platform answers.

## Verify

- Lua: `luac -p source/init.lua`.
- Web: `node --check web/firebase.js`.
- A test app made with `haylen new` in a scratch folder, which lists `firebase`, `notifications`, `firebase-analytics`, `firebase-crashlytics` and `firebase-messaging` with `haylen plugin add <folder> --reference`, takes a `GoogleService-Info.plist`, a `google-services.json` and a `webConfig` that name no real Firebase project, with the identifier of the app as the bundle ID and the package name, and calls every function of the Lua API of the four plugins. It runs with `haylen app run <app> --target ios-simulator`, `--target android` and `--target web`, and `haylen app build <app> --target <target>` passes for each.
- A C++ app made with `haylen new <folder> --kind cpp` with the same plugins builds and runs with `haylen app run <app> --target ios-simulator`.
- A real Firebase project replaces the placeholder files to check what reaches the console.
