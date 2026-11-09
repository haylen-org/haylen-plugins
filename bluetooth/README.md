# 📡 Bluetooth

The Bluetooth plugin makes a [Haylen](https://github.com/haylen-org/haylen) app a central of Bluetooth Low Energy: it scans for nearby devices, connects to them, finds their services and characteristics, reads and writes their values and hears the values that they notify, such as a heart rate monitor, a sensor, a light or a game controller of its own kind. Values cross as strings of bytes, never as text. It owns the permission `bluetooth`, which the app checks and asks for with `bluetooth.permission()` and `bluetooth.requestPermission()` of the plugin, which the [Permissions](../permissions) plugin answers. It uses the APIs of each platform alone.

| Platform | Native part | What it uses |
| --- | --- | --- |
| iOS, iPadOS, Mac Catalyst, tvOS, visionOS and the macOS app | `apple/BluetoothPlugin.swift` and `apple/BluetoothCentral.swift` | CoreBluetooth. |
| Android | The library module in `android/` | The Bluetooth Low Energy API of Android, `BluetoothLeScanner` and `BluetoothGatt`. |
| Web | `web/bluetooth.js` | Web Bluetooth, in the browsers that have it, such as Chrome and Edge on Windows, macOS, Linux, ChromeOS and Android. |
| Windows | The C++ library of `native/` | `Windows.Devices.Bluetooth` and `Windows.Devices.Bluetooth.Advertisement` of the Windows Runtime, through C++/WinRT. |
| Linux | The C++ library of `native/` | BlueZ, the Bluetooth service of Linux, on the system bus through libdbus. |

The tooling builds the C++ library of `native/` for Windows and Linux against the SDK of the engine, which gives it the native API of the engine and nlohmann/json, with which it reads and writes the JSON of every call and event.

## Installation

```sh
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path permissions --reference --app my-app
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path bluetooth --reference --app my-app
```

The plugin depends on the `permissions` plugin, which owns the permission contract, so the app lists it too. The commands list both plugins in the `plugins` section of the `haylen.json` of the app as references to their folders in the repository of the Haylen plugins:

```json
{
    "plugins": {
        "permissions": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "permissions"
        },
        "bluetooth": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "bluetooth"
        }
    }
}
```

Without `--reference`, the command copies the plugin into `plugins/bluetooth/` of the app instead. A parameter that the entry leaves out takes its default from `plugin.json`, so the app follows the defaults of newer versions of the plugin. To stay on one version of the plugin, the app names a commit in `ref` instead of the branch `main`.

## Parameters

| Parameter | Platforms | Type | Default | Meaning |
| --- | --- | --- | --- | --- |
| `bluetoothUsage` | Apple platforms | string | `The app connects to Bluetooth devices.` | The text of the prompt of the system, `NSBluetoothAlwaysUsageDescription` of the `Info.plist`, which tells the person why the app asks. |
| `macBluetooth` | macOS, Mac Catalyst | boolean | `true` | Whether the Mac app signs with the entitlement `com.apple.security.device.bluetooth`, which a Mac app in the App Sandbox needs to use Bluetooth. |

## Setup

### Apple platforms

The plugin declares `CoreBluetooth.framework`, the usage description `NSBluetoothAlwaysUsageDescription` with the value of `bluetoothUsage` and, on the Mac, the entitlement of the App Sandbox. The system shows its prompt the first time the app asks for the permission or uses Bluetooth. Simulators have no Bluetooth, so there the permission answers `granted` without a prompt and every call that needs the radio fails with the code `unsupported`.

### Android

The plugin declares the permissions that Android asks for:

- From Android 12 on, `BLUETOOTH_SCAN` with `neverForLocation`, so Android never derives a location from a scan, which also leaves out the beacons that only a location would reveal, and `BLUETOOTH_CONNECT`.
- Up to Android 11, `BLUETOOTH` and `BLUETOOTH_ADMIN`, and `ACCESS_FINE_LOCATION`, without which a scan finds nothing. A scan also finds nothing there while the location of the device is off in the settings.

The permissions of Android 11 and earlier carry `maxSdkVersion="30"`. An app that also uses the location on later versions declares `ACCESS_FINE_LOCATION` in its own manifest without the attribute, which wins in the merged manifest. The feature `android.hardware.bluetooth_le` is not required, so devices without it still install the app, and the calls there fail with the code `unsupported`.

### Web

The page must be a secure context, served over HTTPS or from `localhost`, in a browser with Web Bluetooth. A page in a frame needs `allow="bluetooth"` on its frame. The web works differently from the other platforms:

- A page never scans by itself. `scan` opens the chooser of the browser, which lists the nearby devices that advertise the services of the scan, or every device for a scan without services. The person picks one device, which reaches `onFound` alone, without `rssi` and `manufacturerData`, and the scan ends once the chooser closes. The option `seconds` changes nothing, and `stopScan` has nothing to stop.
- The browser shows the chooser only right after a press of the person, so the app scans from the press of a button, and a scan that comes later fails with the code `notAllowed`.
- The page reaches only the services that the scan named, so a scan without services reaches no service of the device. The app names in `services` every service that it uses.
- The id of a device belongs to the page, and the page reaches again only the devices that the person picked since it loaded.

### Windows

The C++ library of `native/` calls the Windows Runtime through C++/WinRT, whose headers come with the Windows SDK, so the machine that builds the app needs nothing else. Windows asks the person nothing before a desktop app uses Bluetooth Low Energy, so the permission is `granted` on a computer whose adapter has Bluetooth Low Energy, and `bluetooth.permission()` fails with the code `unsupported` and the reason without one. Windows works differently from the other platforms in some ways:

- A scan listens actively, so the names that devices give in their scan responses reach the app. A device whose advertisement has no name reaches `onFound` once its scan response came, or a second after its first advertisement without one.
- Windows has no call that connects. A connection is a session of GATT that asks Windows to keep the device connected, and it answers once Windows connected the device, or fails with the code `connectFailed` after 30 seconds.
- Windows has no call that disconnects either. The function `disconnect` lets go of the device and its session, after which Windows ends the connection unless another app holds the device. A device that ends the connection or goes out of range ends the session too, so the app connects again, as on the other platforms.
- Windows reads the services and the characteristics from the device each time the app asks. An operation that the device refuses, such as one on a characteristic that needs a paired device, fails with the code `failed`.

### Linux

The C++ library of `native/` links libdbus, whose headers come with the package `libdbus-1-dev` of Debian and Ubuntu, or `dbus-devel` of Fedora, which the machine that builds the app needs. The computer that runs the app needs BlueZ, the service `bluetooth` of the system, which owns `org.bluez` on the system bus and which every Linux desktop with Bluetooth runs. BlueZ shows no prompt. The policy of BlueZ on the system bus decides which users reach it, and most desktops let every user of the session reach it, so the permission is `granted` while BlueZ runs with an adapter, and `denied` on a system whose policy refuses the user. Linux works differently from the other platforms in some ways:

- BlueZ joins the discovery filters of every app of the computer, so it may report more devices than a scan asked for. The plugin passes on only the devices that advertise one of the services of the scan.
- A device that an earlier scan of any app found and that BlueZ still sees reaches `onFound` as soon as the scan starts.
- A connection belongs to the computer, not to the app, so a device that another app connected counts as connected, and `disconnect` ends the connection for every app. The event `onDisconnected` reaches the app only for the devices that it connected itself.
- A connection answers once BlueZ found the services of the device, and fails with the code `connectFailed` when that takes more than 30 seconds.
- BlueZ gives the data of each maker apart, so `manufacturerData` holds the id and the bytes of the first maker that the device advertises.

## What each platform answers

| Platform | `bluetooth.permission()` | The id of a device |
| --- | --- | --- |
| iOS, iPadOS, Mac Catalyst, tvOS, visionOS, macOS | `prompt` until the person answers, then `granted` or `denied`. | A UUID that CoreBluetooth gives the device for this app, the same across launches. |
| Android 12 and later | `prompt` until the person answers the prompt of nearby devices, then `granted` or `denied`, and `denied` once Android no longer asks. | The address of the device. |
| Android 11 and earlier | The same for the precise location. | The address of the device. |
| Web | `granted` where the browser reaches a Bluetooth adapter, since the chooser of each scan is where the person allows a device, and a failure with the code `unsupported` and the reason otherwise. | An id that the browser gives the device for the page. |
| Windows | `granted` on a computer whose adapter has Bluetooth Low Energy, and a failure with the code `unsupported` and the reason without one. | The address of the device, such as `AA:BB:CC:DD:EE:FF`. |
| Linux | `granted` while BlueZ runs on the system bus with an adapter, `denied` when the policy of the system bus refuses the app, a failure with the code `unsupported` and the reason without a system bus, BlueZ or an adapter, and `unknown` when BlueZ answers with another error. | The address of the device, such as `AA:BB:CC:DD:EE:FF`. |

## Platforms without the plugin

| Platform | Reason |
| --- | --- |
| macOS in the desktop player | The desktop player, which `haylen app run` starts by default, has no `Info.plist` with the usage description of Bluetooth, and macOS ends a process that uses Bluetooth without it. The macOS app that `haylen app run --target macos` builds runs the Apple part. |

On this platform the plugin has no native part, so `bluetooth.available` is `false` and every call fails with the code `noHandler`, `bluetooth.permission()` and `bluetooth.requestPermission()` among them.

## Lua API

```lua
local bluetooth = require('bluetooth')
```

A UUID of a service or a characteristic is a string, in its full form, such as `'0000180d-0000-1000-8000-00805f9b34fb'`, or in the short form of 4 or 8 hexadecimal digits that the Bluetooth SIG assigns, such as `'180d'`. The plugin answers every UUID in its full form in lowercase, so the app compares UUIDs as strings. A UUID that is neither form raises `The service "<value>" is not a UUID. Give 4 or 8 hexadecimal digits, or the full form such as "0000180d-0000-1000-8000-00805f9b34fb".`, and the same for a characteristic. A UUID that is no string raises `The service is a UUID string, such as "180d" or "0000180d-0000-1000-8000-00805f9b34fb".`, and the same for a characteristic.

An id of a device that is no string or is empty raises `The function "bluetooth.<name>" takes the id of a device, a string that "onFound" gives.`, where `<name>` is the function, such as `connect`. A table `options` that is no table raises `The options of "bluetooth.<name>" are a table.`, and a key that the function does not take raises `Unknown option "<key>".`.

Every call fails with the code `denied` when the person refused the permission, `poweredOff` while Bluetooth is off, `unsupported` on a device without Bluetooth Low Energy, `unknownDevice` for an id that names no device the system knows, `notConnected` for a device that is not connected or that disconnected during the call, `unknownService` and `unknownCharacteristic` for a UUID that the device lacks, and `failed` with the error of the device. An id stays valid after the scan that found it: Apple platforms find a device that an earlier scan found again, and Android takes the address of any device, so a device that is out of range fails to connect with the code `connectFailed` or `timeout` instead.

### bluetooth.available

Whether the native part of the plugin runs on this platform. Without it every call fails with the code `noHandler`.

### bluetooth.permission()

Reads the state of the permission `bluetooth`, as far as the platform tells it, without asking the person. It returns a call of `haylen.platform`, whose `await` gives `'granted'`, `'prompt'`, `'denied'` or `'unknown'`, or `nil` and an error with the code `unsupported`, the reason as `message` and `data.missing` for a requirement that the project lacks. A platform without the native part of the plugin fails it with the code `noHandler`, as every call of the plugin. Like every platform call, a failure that nothing awaits stops the app.

```lua
local async = require('async')
local bluetooth = require('bluetooth')

async.spawn(function()
    local state, failure = bluetooth.permission():await()
    print(state and 'The permission bluetooth is ' .. state .. '.' or failure.code .. ': ' .. failure.message)
end)
```

### bluetooth.requestPermission()

Asks the person for the permission `bluetooth` with the prompt of the system while the state is `'prompt'`, and returns a call of `haylen.platform`, whose `await` gives the state that the person left. Any other state answers at once, without a prompt. A platform without the capability, or a project that lacks what the prompt needs, such as the `NSBluetoothAlwaysUsageDescription` of the `Info.plist`, fails it with the code `unsupported`, the reason as `message` and, for the project, `data.missing`.

Every call but `stopScan` and `disconnect` asks for the permission first where the app does not hold it yet, so an app asks itself only to pick the moment. A call that the person refused fails with the code `denied` and the sentence `The person has not allowed Bluetooth. Ask for it with "bluetooth.requestPermission('bluetooth')", which shows the prompt of the system while the system still asks, or the person allows it in the settings of the system.`, and a call whose project lacks a requirement fails with the code `unsupported` and `data.missing`.

```lua
local async = require('async')
local bluetooth = require('bluetooth')

async.spawn(function()
    local state, failure = bluetooth.requestPermission():await()
    print(state and 'Bluetooth is ' .. state .. '.' or failure.code .. ': ' .. failure.message)
end)
```

### bluetooth.scan(options)

Scans for devices that advertise and returns a platform call whose `await` gives `{}` once the scan ends. Each device that the scan finds reaches the listeners of `onFound` once per scan. A scan that starts ends the one that runs, whose call then gives `{}`. The table `options` is optional:

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `services` | list of UUIDs | Every device | Finds only the devices that advertise one of these services. On the web they are also the services that the page may reach. |
| `seconds` | number | `10` | How long the scan runs. |
| `owner` | table or userdata | None | An owner, such as a scene, whose end stops the scan. |

The call fails with the code `scanFailed` when the system stops the scan, and on the web with `notAllowed` for a scan that did not come right after a press. A `services` that is no table raises `The "services" of a scan are a list of UUIDs.`, and a `seconds` that is not a number above `0` raises `The "seconds" of a scan are a number above 0.`.

```lua
local bluetooth = require('bluetooth')
local scene = require('haylen.scene')

scene.push({
    enter = function(self)
        bluetooth.onFound(function(devices)
            for _, device in ipairs(devices) do
                print('Found ' .. (device.name or device.id) .. '.')
            end
        end, {owner = self})
        bluetooth.scan({services = {'180d'}, seconds = 5, owner = self})
    end,
})
```

### bluetooth.stopScan()

Stops the scan that runs, whose call then gives `{}`. Returns a platform call whose `await` gives `{}`.

### bluetooth.connect(id, options)

Connects to the device `id` that a scan found, and returns a platform call whose `await` gives `{id, name}`. A device that is connected already answers at once. The table `options` takes `timeout`, the seconds after which the call fails with the code `timeout` and the attempt stops, since Apple platforms keep trying to connect until the app gives up. The call fails with the code `connectFailed` when the device does not connect.

### bluetooth.disconnect(id)

Disconnects from the device `id`, and returns a platform call whose `await` gives `{}` once it disconnected. A device that is not connected answers at once.

### bluetooth.services(id)

Returns a platform call whose `await` gives the list of the UUIDs of the services of the connected device `id`.

### bluetooth.characteristics(id, service)

Returns a platform call whose `await` gives the list of the characteristics of the service `service` of the connected device `id`, each `{uuid, properties}`, where `properties` lists what the characteristic allows: `'read'`, `'write'`, `'writeWithoutResponse'`, `'notify'` and `'indicate'`.

### bluetooth.read(id, service, characteristic)

Reads the value of a characteristic, and returns a platform call whose `await` gives `{value}`, with the value as a string of bytes.

```lua
local async = require('async')
local bluetooth = require('bluetooth')

-- Reads the level of the battery service, one byte from 0 to 100.
async.spawn(function()
    local result, err = bluetooth.read(deviceId, '180f', '2a19'):await()
    print(result and ('The battery is at ' .. result.value:byte() .. ' percent.') or err.message)
end)
```

### bluetooth.write(id, service, characteristic, bytes, options)

Writes the string of bytes `bytes` into a characteristic, and returns a platform call whose `await` gives `{}`. The table `options` takes `response`, `true` by default, which waits until the device confirms the write, while `false` writes without a response, for a characteristic that allows `writeWithoutResponse`. A value that is not a string raises `The function "bluetooth.write" takes the value as a string of bytes.`, and a `response` that is no boolean raises `The option "response" of "bluetooth.write" is a boolean.`.

```lua
local bluetooth = require('bluetooth')

-- Turns a light on, with the byte 1, without waiting for an answer.
bluetooth.write(deviceId, lightService, switchCharacteristic, '\1', {response = false})
```

### bluetooth.subscribe(id, service, characteristic), bluetooth.unsubscribe(id, service, characteristic)

Turn on or off the notifications of a characteristic, or its indications when it only indicates, and return a platform call whose `await` gives `{}`. The values that a characteristic sends while it is subscribed reach the listeners of `onChanged`. A characteristic that neither notifies nor indicates fails with the code `notSupported`.

### bluetooth.onFound(listener, options)

Calls `listener(devices)` once per frame with the list of the devices that the scan found since the frame before, and returns the connection of the listener, whose `disconnect()` stops it. Each device is `{id, name, rssi, services, manufacturerData}`: its id, the name that it advertises, or `nil`, the strength of its signal in dBm, the UUIDs of the services that it advertises, and the data of its maker as a string of bytes that starts with the id of the company in little endian, or `nil`. The table `options` takes the `owner` of the listener.

### bluetooth.onChanged(listener, options)

Calls `listener(changes)` once per frame with the list of the values that subscribed characteristics sent since the frame before, each `{id, service, characteristic, value}`, with the value as a string of bytes, and returns the connection of the listener. The table `options` takes the `owner` of the listener.

```lua
local bluetooth = require('bluetooth')

bluetooth.onChanged(function(changes)
    for _, change in ipairs(changes) do
        if change.characteristic == '00002a37-0000-1000-8000-00805f9b34fb' then
            print('The heart beats ' .. change.value:byte(2) .. ' times a minute.')
        end
    end
end)
```

### bluetooth.onDisconnected(listener, options)

Calls `listener({id, reason})` when a connected device disconnects, because the app disconnected, the device ended the connection, it went out of range or Bluetooth turned off, and returns the connection of the listener. The table `options` takes the `owner` of the listener.

## Native API

| Method or event | Params or payload | Answer |
| --- | --- | --- |
| `bluetooth.scan` | `{services, seconds}` | `{}` once the scan ends |
| `bluetooth.stopScan` | `{}` | `{}` |
| `bluetooth.connect` | `{id}` | `{id, name}` |
| `bluetooth.disconnect` | `{id}` | `{}` |
| `bluetooth.services` | `{id}` | `[uuid]` |
| `bluetooth.characteristics` | `{id, service}` | `[{uuid, properties}]` |
| `bluetooth.read` | `{id, service, characteristic}` | `{value}` with bytes |
| `bluetooth.write` | `{id, service, characteristic, value, response}` with bytes | `{}` |
| `bluetooth.subscribe`, `bluetooth.unsubscribe` | `{id, service, characteristic}` | `{}` |
| `bluetooth.permission`, `bluetooth.requestPermission` | `{name}` | The name of the state, or a failure with the code `unsupported`, the reason and `data.missing`, which the Permissions plugin answers on Apple platforms, Android and the web for the permission that the native part registers, and the library of `native/` answers on Windows and Linux. |
| `bluetooth.found` (batched event) | `{id, name, rssi, services, manufacturerData}` | |
| `bluetooth.changed` (batched event) | `{id, service, characteristic, value}` | |
| `bluetooth.disconnected` (event) | `{id, reason}` | |

## Sample

The app in `sample/` references the plugin with `"path": ".."`. It scans, lists the devices it finds as buttons, connects to the one the person presses, and reads, writes and subscribes to every characteristic of the device that allows it, with the answers and the events on screen:

```sh
haylen app run sample --target ios --device <iPhone>
haylen app run sample --target android
haylen app run sample --target web
haylen app run sample --target windows
haylen app run sample --target linux
```

The simulators of Apple have no Bluetooth, so on Apple platforms the sample needs a device. On the web it needs a browser with Web Bluetooth on a computer with an adapter.

The UI tests in `sample/ui-tests` answer the prompt or the dialog of Bluetooth and run a scan of eight seconds to its end without an error, whatever devices advertise nearby. The simulators of Apple have no Bluetooth, so the iOS test runs on a device. They run on the emulator and devices:

```sh
haylen test --ui sample --target ios-simulator
haylen test --ui sample --target android
haylen test --ui sample --target ios --device <name or UDID>
```

## License

MIT, like Haylen.
