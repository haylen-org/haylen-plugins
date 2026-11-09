# 🧭 Bluetooth — plugin guide

This folder is the Bluetooth plugin of Haylen: Bluetooth Low Energy as a central, with scans, connections, services, characteristics, reads, writes and notifications, and the permission `bluetooth`, which the plugin owns through the `permissions` plugin. This file is binding for every change of the plugin.

## Rules

- The plugin follows the `AGENTS.md` of the Haylen repository and the plugin format of its `docs/platform/plugins.md`, with the writing, comment and naming standards of both.
- It uses the APIs of each platform alone, CoreBluetooth on Apple platforms, the Bluetooth Low Energy API of Android, Web Bluetooth, the Windows Runtime through C++/WinRT and BlueZ on the system bus of Linux through libdbus, and never a third-party library.
- The Lua API of `source/init.lua` is the same on every platform, except the scan of the web, whose chooser `README.md` describes. A platform that cannot serve a call fails it with a code and a sentence that says why, and a platform without the plugin is a gap that `README.md` states with its reason.
- The plugin owns the permission `bluetooth` through the `permissions` plugin, which it lists in `dependencies`: `Permission` and `Permissions` of `permissions/apple/` on Apple platforms, `com.haylen.plugins.permissions` on Android and `registerPermission` and `requirePermission` of `haylen-plugin:permissions` on the web register it and ask for it before every call but `stopScan` and `disconnect`. The Windows and Linux libraries answer `bluetooth.permission` and `bluetooth.requestPermission` themselves and check the adapter before every use. The Lua API offers `bluetooth.permission()` and `bluetooth.requestPermission()`, which the `permissions` plugin answers.
- Values cross the bridge as bytes, never as text, and every UUID crosses in its full form in lowercase.
- The parameters of the native methods are the ones that `source/init.lua` sends, and a native part fails a call whose parameter is missing or of another type instead of a default of its own. An empty list of Lua crosses the bridge as an empty object, which the native parts read as an empty list.
- The found devices and the notified values reach the app as batched events, so Lua receives one list per frame.
- Android runs one operation of GATT at a time on a connection, so each device keeps a queue of operations, and every callback of the system continues on the main thread.
- The Windows and Linux libraries are C++20 classes behind the C function `bluetooth_haylen_init`, which read and write every JSON of the bridge with nlohmann/json of the engine SDK. `BluetoothRequest` reads the parameters of every call and `BluetoothBridge` writes the answers and the events for both systems, while `WindowsBluetooth` and `LinuxBluetooth` each keep the central of their system.
- The Windows library does all its work with the Windows Runtime on one thread of its own in the multithreaded apartment, which it starts once per process and keeps across restarts of the app.
- The Linux library does all its work with BlueZ on one thread of its own, with a connection of its own to the system bus, so the frame thread never waits for BlueZ, and every wait of that thread has a bound.
- Every change updates `README.md`, which documents the complete Lua API, the setup of each platform and what each platform answers, and the sample in `sample/`, which shows every call.

## Verify

- Lua: `luac -p source/init.lua sample/source/main.lua`.
- Web: `node --check web/bluetooth.js`.
- Apple: `swiftc -typecheck` of `apple/*.swift` with the Swift helpers and the plugin headers of the engine, for the SDKs of iOS, Mac Catalyst, tvOS, visionOS and macOS.
- Android: a compile of the Kotlin and the lint of the module against the `haylen-plugins` library of the engine.
- Windows: a build of `native/` with MSVC and `/W4 /WX`, and a host with a stub of `HaylenNativeApi` that calls every handler, scans the devices that advertise nearby and checks the failures of a device that is not connected.
- Linux: a build of `native/` with CMake against the CMake package of the engine SDK and `-Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion -Wshadow -Werror` in a container of the Linux image of the CI, and a host with a stub of `HaylenNativeApi` that calls every handler against a fake BlueZ, an object tree of `org.bluez` on a private bus that `DBUS_SYSTEM_BUS_ADDRESS` names, also under the address and undefined behaviour sanitizers.
- The sample: `haylen app run sample --target <target>` and `haylen app verify sample --target <target>` on a device of each platform, since the simulators of Apple have no Bluetooth, with a device that advertises nearby.
- The UI tests of `sample/ui-tests`: `haylen test --ui sample` with `--target android`, and `ios` or `android` with `--device` on a phone, which answer the prompt and scan for eight seconds.
