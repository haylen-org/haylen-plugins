# 🧭 Notifications — plugin guide

This folder is the Notifications plugin of Haylen: local notifications that an app schedules, cancels and lists, the tap of the person that opens the app, and the permission `notifications`, which the plugin owns through the `permissions` plugin. This file is binding for every change of the plugin.

## Rules

- The plugin follows the `AGENTS.md` of the Haylen repository and the plugin format of its `docs/platform/plugins.md`, with the writing, comment and naming standards of both.
- It uses the APIs of each platform alone, UserNotifications on Apple platforms, `AlarmManager` and `NotificationManager` on Android, the Notification API on the web, the toasts of the Windows Runtime through C++/WinRT on Windows and the notification server of the session bus through libdbus on Linux, and never a third-party library.
- The Lua API of `source/init.lua` is the same on every platform. A platform that cannot serve a call fails it with the code `unsupported` and a sentence that says why, and a platform without the plugin is a gap that `README.md` states with its reason.
- The plugin owns the permission `notifications` through the `permissions` plugin, which it lists in `dependencies`: `Permission` and `Permissions` of `permissions/apple/` on Apple platforms, the classes of `com.haylen.plugins.permissions` on Android, `registerPermission` and `requirePermission` of `haylen-plugin:permissions` on the web, and the handlers `notifications.permission` and `notifications.requestPermission` of its own in the libraries of `native/` on Windows and Linux. The app checks and asks for it with `notifications.permission()` and `notifications.requestPermission()`, which the Lua module declares through `permissions.declare`, and every call that posts a notification requires the permission first.
- The notifications of the plugin carry the prefix `notifications.` in their identifiers or tags, or the group `notifications` on Windows, so the plugin lists, cancels and answers only its own notifications. The tap reaches the app as the retained event `opened`.
- On Apple platforms the plugin owns the delegate of the notification center: its object `Notifications` becomes the delegate as the plugin class loads, before launching ends, and hands every notification and response to the plugin class and to the `NotificationsDelegate` of each plugin that depends on it and registers with `Notifications.addDelegate(_:)`, joining the presentation options of all of them. No other plugin sets the delegate of the center.
- On Linux the server keeps no notification that waits, so `source/linux.lua` answers the methods in Lua and the C++ library of `native/` only shows and closes notifications, with the texts of a notification in the byte buffers of the call.
- The C++ library of `native/` reads and writes its JSON with nlohmann/json, which the target `haylen::native` of the desktop SDK gives it, and never by hand.
- Every change updates `README.md`, which documents the complete Lua API, the setup of each platform and what each platform answers, and the sample in `sample/`, which shows every call.

## Verify

- Lua: `luac -p source/*.lua sample/source/main.lua`.
- Web: `node --check web/notifications.js`.
- Apple: `swiftc -typecheck` of `apple/*.swift` and `../permissions/apple/*.swift` with the Swift helpers and the plugin headers of the engine, for the SDKs of iOS, Mac Catalyst, visionOS and macOS.
- Android: a compile of the Kotlin and the lint of the module against the `haylen-plugins` and `haylen-links` libraries of the engine and the module of `../permissions/android`.
- Windows: a build of `native/` with MSVC and `/W4 /WX`, and a host with a stub of `HaylenNativeApi` that calls every handler without a shortcut and with one, in the session of the person and without a window, scheduling only toasts of far dates that it cancels.
- Linux: a build of `native/` against the desktop SDK with `-Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion -Wshadow -Werror` and a run against a notification server on a session bus of its own.
- The sample: `haylen app run sample` and `haylen app verify sample` on each platform that the plugin declares, such as `--target ios-simulator`, `android` and `web`, where a notification is scheduled, shows and opens the app.
- The UI tests of `sample/ui-tests`: `haylen test --ui sample --target ios-simulator` on an iPhone simulator and `--target android` on the emulator, which allow the prompt or the dialog, tap the notifications while the sample shows, from the home screen and after the sample ended or left the recent apps, and check the lists and the cancels.
