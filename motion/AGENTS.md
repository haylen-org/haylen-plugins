# 🧭 Motion — plugin guide

The Motion plugin reads the accelerometer, the gyroscope and the attitude of the device and owns the permission `motion`: Swift in `apple/`, a Kotlin library module in `android/`, an ES module in `web/`, and in `native/` a C++ library for the desktop player of macOS, Windows and Linux, whose `MotionPlugin` answers the methods with nlohmann/json and whose `MotionDevice` runs the sensors of Windows, or answers that macOS and Linux give apps none. Its Lua API lives in `source/init.lua`, and `README.md` documents it with what each platform answers.

## Rules

- The plugin follows the `AGENTS.md` of the Haylen repository and the plugin format of its `docs/platform/plugins.md`. Code, comments and docs are written in English, comments are rare complete sentences, and nothing names another engine or a company beyond the platforms.
- It uses the APIs of each platform alone, never a third-party library.
- The Lua API is the same on every platform, with the axes and units of its README. A platform without the sensors fails `motion.start` with the code `unsupported` and the exact reason, and answers the permission `motion` with `unsupported`.
- The plugin owns the permission `motion` through the `permissions` plugin, which it lists in `dependencies`: `Permission` and `Permissions` of `permissions/apple/` on Apple platforms, `com.haylen.plugins.permissions` on Android and `registerPermission` and `requirePermission` of `haylen-plugin:permissions` on the web register it and ask for it in `start` before a sensor runs, and the desktop libraries answer `motion.permission` and `motion.requestPermission` themselves and check the sensors before a start. The Lua API offers `motion.permission()` and `motion.requestPermission()`, which the `permissions` plugin answers.
- Readings reach Lua as the batched event `reading`, so Lua receives one list per frame, in the axes of the device in its natural orientation with the quarter turns of the screen, and only `source/init.lua` turns them into the axes of the screen and measures the tilt.
- The native part holds the `watch` call of a session while its sensors run and stops them when the call is given up, so the sensors never outlive the app that started them. The sensors stop while the app is in the background, and on Windows, whose library hears nothing of the state of the app, no readings go out while the window of the app is minimized.
- The motion of gamepads belongs to the engine, as `input.startGamepadMotion`, and never to this plugin.
- Every change updates `README.md`, the Lua API and every native part in the same change, and the sample in `sample/` shows every call.

## Verify

- Run the sample on this machine with `haylen app run sample`, and on the iOS simulator, the Android emulator and the web with `--target`. Simulators have no motion sensors, so only an iPhone, an Android phone and a phone that opens the page move the readings.
- Check the Lua with `luac -p source/init.lua sample/source/main.lua`, the web module with `node --check web/motion.js` and the Swift with `swiftc -typecheck` against the plugin API of the engine, for iOS, Mac Catalyst, macOS, tvOS and visionOS.
- Compile the Kotlin module against the `haylen` library of the engine.
- Build `native/` against the installed desktop SDK of the engine with `-Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion -Wshadow -Werror` on macOS and Linux, and on Windows with MSVC and `/W4 /WX`, and call its handlers through a host with a stub of `HaylenNativeApi`. A computer without sensors answers `unsupported`, and only a tablet or a convertible moves the readings.
- The UI tests of `sample/ui-tests`: `haylen test --ui sample` with `--target ios-simulator`, `android`, and `ios` or `android` with `--device` on a phone at rest, which read the gravity of the Earth from the sensors.
