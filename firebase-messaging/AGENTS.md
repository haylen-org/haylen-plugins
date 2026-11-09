# 🧭 Firebase Cloud Messaging — plugin guide

This folder is the Firebase Cloud Messaging plugin of Haylen: the registration of the app instance by its Firebase installation ID, the topics, the messages that arrive while the app runs and the taps on their notifications, received through the default Firebase app that the plugin `firebase` configures. This file is binding for every change of the plugin.

## Rules

- The plugin follows the `AGENTS.md` of the Haylen repository and the plugin format of its `docs/platform/plugins.md`, with the writing, comment, naming and clean code standards of both.
- It requires the plugins `firebase` and `notifications`, and wraps the Cloud Messaging SDK of each platform and no other third-party library: `FirebaseMessaging` of the Firebase Apple SDK as a Swift package with `exactVersion`, `firebase-messaging` through the Firebase BoM with its version on Android, and the Messaging module of the Firebase JavaScript SDK from the address of its version on the web and in its service worker. Every one stays at the latest release, at the same versions as the plugin `firebase`.
- The plugin owns no permission. The permission `notifications` belongs to the plugin `notifications`, the app asks for it with `notifications.requestPermission()` of that plugin, and the plugin keeps no method that asks for a permission or reads its state. The registration of iOS and Android needs no permission. The registration of the web does, so the web part reads `Notification.permission` before the SDK could show its prompt and fails with the code `denied` and the sentence that tells the app how to ask.
- On Apple platforms the plugin depends on `notifications`, adopts its `NotificationsDelegate` and registers with `Notifications.addDelegate(_:)` as it loads, and answers the notification center only for the notifications of Firebase, which carry `gcm.message_id`, with no options for every other notification, so the plugin that posted it shows its own. It never sets the delegate of the center. On Android its notifications carry the tag `firebase-messaging`.
- The plugin registers by the Firebase installation ID, which the SDKs offer in place of the tokens they deprecate, and turns it on with `FirebaseMessagingInstallationIdEnabled` and `firebase_messaging_installation_id_enabled`. The taps reach the app as the retained event `messageOpened`, and the registrations as the retained event `registered`.
- Every call checks that the default Firebase app runs and fails with the code `notConfigured` otherwise. A platform that cannot serve a call fails it with the code `unsupported` and a sentence that says why, such as the topics of the web, and a platform without the plugin is a gap that `README.md` states with its reason.
- Every change updates `README.md`, which documents the complete Lua API, the setup of each platform and what each platform answers.

## Verify

- Lua: `luac -p source/init.lua`.
- Web: `node --check web/firebase-messaging.js web/firebase-messaging-sw.js`.
- The test app that the `AGENTS.md` of the plugin `firebase` describes, with the plugin `notifications`, on the iOS simulator, the Android emulator and the web, where every call answers with its typed code, a local notification of the plugin `notifications` shows while this plugin runs, and a payload with `gcm.message_id` that `xcrun simctl push` hands the simulator reaches `onMessage`, and `haylen app build` of each target, and the C++ app on the iOS simulator.
- The delivery of real messages and their taps needs a real Firebase project and a device: an iPhone signed with the Push Notifications capability, and an Android device or emulator with the services of Google Play.
