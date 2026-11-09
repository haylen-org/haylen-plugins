# 🌐 Local Network

The Local Network plugin for [Haylen](https://github.com/haylen-org/haylen) apps lets an app work with devices on the same network, such as a game that finds the other players in the room, a remote for a device of the home or an app that runs the packages that `haylen app serve` serves. It owns the permission `localNetwork`, shows the picker of the services of one type on the local network, and advertises a service of the app. Its Lua API is the same on every platform.

| Platform | Native part | Permission `localNetwork` | Picker of services | Advertisement |
| --- | --- | --- | --- | --- |
| iOS, iPadOS, tvOS and visionOS | `apple/` | `unknown`, since the system asks by itself the first time the app reaches the local network and tells the app nothing. | A list of the plugin of the services that `NWBrowser` finds, over the app. | DNS-SD. |
| macOS and Mac Catalyst | `apple/` in the app | `unknown`, as on iOS, from macOS 15 on. | The same list, in a sheet of the window of the app on macOS and over the app on Mac Catalyst. | DNS-SD. |
| Android | The library module in `android/` | `ACCESS_LOCAL_NETWORK` on Android 17 and later, and `granted` before. | The picker of the system of `NsdManager`, which needs no permission. | `NsdManager`, after the permission. |
| Web | `web/local-network.js` | The `local-network` permission of the browsers with Local Network Access, and `unknown` elsewhere. | `unsupported`. | `unsupported`. |

On Windows, on Linux and in the desktop player of macOS the plugin has no native part, so its calls fail with the code `noHandler`. Those desktops reach the local network without a permission, and the app talks to devices it knows the address of with the module `socket` alone.

## Installation

```sh
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path local-network --reference --app my-app
```

The plugin depends on the [`permissions`](../permissions) plugin, which the app lists too:

```json
{
    "plugins": {
        "permissions": {"git": "https://github.com/haylen-org/haylen-plugins", "ref": "main", "path": "permissions"},
        "local-network": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "local-network",
            "parameters": {"bonjourServices": ["_my-game._tcp"]}
        }
    }
}
```

Without `--reference`, the command copies the plugin into `plugins/local-network/` of the app instead. To stay on one version of the plugin, the app names a commit in `ref` instead of the branch `main`.

## Parameters

| Parameter | Platforms | Default | Meaning |
| --- | --- | --- | --- |
| `localNetworkUsage` | Apple platforms | `'The app connects to devices on the local network.'` | The text of the local network prompt, the `NSLocalNetworkUsageDescription` of the `Info.plist`. |
| `bonjourServices` | Apple platforms | `[]` | The service types that the app finds and advertises, such as `"_my-game._tcp"`, the `NSBonjourServices` of the `Info.plist`. Apple platforms find and advertise no type that the list lacks, and the plugin fails such a call with the code `unsupported`. |

## What each platform asks for

- **Apple platforms.** The system shows its local network prompt, with the text of `localNetworkUsage`, the first time the app reaches the local network: when the picker starts to look, when the app advertises, or when the app connects to an address of the local network. The system tells the app nothing of the prompt or the answer, so the permission is `unknown` and `requestPermission` shows nothing. A person who refused allows the app again in the settings of the system, under privacy and the local network. The development of Haylen reaches iPhones through the tunnel of CoreDevice, which is no local network, so apps without this plugin never see the prompt.
- **Android.** Android 17 blocks the local network of an app that targets it until the person allows `ACCESS_LOCAL_NETWORK`, which the manifest of the module declares and which belongs to the group of nearby devices, so a person who allowed Bluetooth already allowed it. Earlier versions of Android reach the local network with `INTERNET`, and the permission answers `granted` there. The picker of services needs no permission: the address of the service the person picks becomes reachable for the app, also after a restart.
- **Web.** A browser with Local Network Access asks the person the first time the page reaches an address of the local network, and offers no call that shows the prompt, so `requestPermission` answers the state the browser holds. Pages find no services, since browsers give them no API of DNS-SD.

## When to use the picker instead of the permission

The picker suits an app that needs one device or one other app on the network at a time, such as a game that joins the game of a friend or a remote that drives one device: the person picks it, and on Android the app needs no permission and shows no prompt. The permission suits an app that needs the whole network, such as one that hosts a game for every player who joins, scans for devices on its own or receives connections, which is what an advertisement does. An app that only connects to addresses it already knows, such as the address of a server that the person types, needs the permission on Android 17 and later, and the prompt on Apple platforms comes by itself.

## Lua API

```lua
local localNetwork = require('local-network')
```

### localNetwork.permission() and localNetwork.requestPermission()

Return the platform call whose `await` gives the state of the permission `localNetwork`: `'granted'`, `'prompt'`, `'denied'` or `'unknown'`, as the table at the top says for each platform. `requestPermission` shows the prompt of the system while the state is `prompt`. A project that lacks the text of the prompt fails with the code `unsupported` and `data.missing`. The functions `permissions.state('localNetwork')` and `permissions.request('localNetwork')` of the Permissions plugin give the same.

```lua
local state = localNetwork.requestPermission():await()
if state == 'denied' then
    print('The person keeps the app off the local network.')
end
```

### localNetwork.pickService(type)

Shows the picker of the services of the type `type` on the local network and returns a platform call whose `await` gives the service that the person picks:

| Field | Meaning |
| --- | --- |
| `name` | The name of the service that people see. |
| `type` | The type, as the app asked for it. |
| `host` | The address that the app connects to, IPv4 where the service has one. |
| `port` | The port of the service. |
| `addresses` | Every address of the service. |

A type is `_`, a name of at most 15 letters, digits and dashes, and `._tcp` or `._udp`, such as `_my-game._tcp`, and another value raises `The service type "<type>" is not a type of DNS-SD. ...`. The call fails with the code `cancelled` and `The person closed the picker of services.` when the person closes the picker, with `unsupported` on the web, on an Android without the picker, which comes with Android 14 and the updates of the system that bring it, and on Apple platforms for a type that `bonjourServices` lacks, and with `failed` when the system refuses to show the picker.

```lua
local socket = require('socket')

local service, failure = localNetwork.pickService('_my-game._tcp'):await()
if service then
    local client = socket.tcp.connect(service.host, service.port, {timeoutMs = 5000}):await()
    client:send('hello'):await()
end
```

On Android the picker of the system shows the services and the person picks one. On Apple platforms the plugin shows a list of the services it finds, which updates while it shows. A tap on a service connects to it to learn its address, and a service that does not answer shows its reason in the list, where the person picks another one or cancels.

### localNetwork.advertise(options)

Advertises a service of the app on the local network until `localNetwork.stopAdvertising`, the end of `options.owner` or the next advertisement, which replaces it. The app listens on the port itself, such as with `socket.tcp.listen('0.0.0.0', 0)`.

| Option | Meaning |
| --- | --- |
| `type` | The type, such as `_my-game._tcp`, which on Apple platforms `bonjourServices` lists. |
| `name` | The name that people see, a text of 1 to 63 bytes. |
| `port` | The port where the app listens, from 1 to 65535. |
| `owner` | Optional. The owner whose end stops the advertisement. |

It returns a platform call whose `await` gives `{name, type, port}`, where `name` is the name that the network took, which differs from the name asked for when another service of the network holds it. On Android it asks for the permission `localNetwork` first and fails with the code `denied` while the person does not allow it. The web fails it with the code `unsupported`, and the system fails it with the code `failed`. An unknown option raises `Unknown option "<key>".`.

```lua
local listener = socket.tcp.listen('0.0.0.0', 0):await()
local advertised = localNetwork.advertise({type = '_my-game._tcp', name = 'The game of Ana', port = listener.port, owner = scene}):await()
```

### localNetwork.stopAdvertising()

Stops the advertisement of the app. Returns a platform call. The advertisement belongs to the process, so the Lua module stops an advertisement that an earlier app left when it loads.

## Sample

The app in [`sample/`](sample) listens on a port with the module `socket`, advertises it as the service `Haylen Sample` of the type `_haylen-sample._tcp`, picks a service of that type and connects to it, and its own service answers with a greeting. Its UI tests do the same on the iOS simulator and on the Android emulator:

```sh
haylen app run sample --target ios-simulator
haylen test --ui sample --target android
```

## Native API

- **Apple platforms.** `LocalNetworkPlugin` registers the permission with `Permissions.register`, the handlers `reset`, `advertise` and `stopAdvertising` and the screen `servicePicker`, whose SwiftUI list `LocalNetworkPickerView` shows the services of `LocalNetworkBrowser`. `LocalNetworkAdvertisement` registers the service with `DNSServiceRegister`.
- **Android.** `LocalNetworkPlugin` registers the permission `LocalNetworkPermission` with `Permissions.register` and the handlers `reset`, `pickService`, `advertise` and `stopAdvertising`. `LocalNetworkPicker` registers a `ServiceInfoCallback` with `DiscoveryRequest.FLAG_SHOW_PICKER`, and `LocalNetworkAdvertisement` registers the service with `NsdManager.registerService`.
- **Web.** `local-network.js` registers the permission with `registerPermission` of the Permissions plugin.

## License

MIT, like Haylen.
