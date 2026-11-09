# 🧭 Firebase Analytics — plugin guide

This folder is the Firebase Analytics plugin of Haylen: the events, the user, the user properties, the consent and the collection of Google Analytics for Firebase, logged into the default Firebase app that the plugin `firebase` configures. This file is binding for every change of the plugin.

## Rules

- The plugin follows the `AGENTS.md` of the Haylen repository and the plugin format of its `docs/platform/plugins.md`, with the writing, comment, naming and clean code standards of both.
- It requires the plugin `firebase` and wraps the Analytics SDK of each platform and no other third-party library: `FirebaseAnalytics` of the Firebase Apple SDK as a Swift package with `exactVersion`, `firebase-analytics` through the Firebase BoM with its version on Android, and the Analytics module of the Firebase JavaScript SDK from the address of its version on the web. Every one stays at the latest release, at the same versions as the plugin `firebase`.
- Every call checks that the default Firebase app runs and fails with the code `notConfigured` otherwise, and a parameter that a native part cannot take fails with the code `invalidParams`. The Lua API checks the types of its arguments first and raises an error that says what it takes.
- The Lua API of `source/init.lua` is the same on every platform. A platform that cannot serve a call fails it with the code `unsupported` and a sentence that says why, such as `resetAnalyticsData` on the web, and a platform without the plugin is a gap that `README.md` states with its reason.
- Every change updates `README.md`, which documents the complete Lua API, the setup of each platform and what each platform answers.

## Verify

- Lua: `luac -p source/init.lua`.
- Web: `node --check web/firebase-analytics.js`.
- The test app that the `AGENTS.md` of the plugin `firebase` describes, on the iOS simulator, the Android emulator and the web, where every call answers, and `haylen app build` of each target, and the C++ app on the iOS simulator.
- A real Firebase project shows the events in the DebugView of its console.
