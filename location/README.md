# 📍 Location

The Location plugin for [Haylen](https://github.com/haylen-org/haylen) apps reads the location of the device, one fix at a time or as updates while the device moves, also in the background where the platform allows it. It owns the permissions `location`, `preciseLocation` and `backgroundLocation`, which the app checks and asks for with `location.permission(name)` and `location.requestPermission(name)` of the plugin, which the [Permissions](../permissions) plugin answers. Its Lua API is the same on every platform, and a platform that cannot serve a call answers why.

| Platform | Native part | Location |
| --- | --- | --- |
| iPhone and iPad | `apple/`, Swift | Core Location, with the precise location that a person who allowed the approximate one grants for the time the app is in use, and updates in the background. |
| Mac Catalyst and macOS app | `apple/`, Swift | Core Location. A Mac gives the location of an app that runs in the background as it does in front. |
| tvOS | `apple/`, Swift | Core Location gives one fix and no updates. |
| visionOS | `apple/`, Swift | Core Location while the app is in use. |
| Android | The library module in `android/` | `LocationManager` with the fused provider from Android 12, and the GPS or the network before, with a foreground service for the updates in the background. |
| Web | `web/location.js` | `navigator.geolocation` on secure pages, while the page shows. |
| macOS desktop player | The library of `native/`, C++ | None. Core Location gives the location only to an app bundle whose `Info.plist` holds `NSLocationUsageDescription`, and the player has no bundle, so every call answers `unsupported` and points to `haylen app run --target macos`. |
| Windows | The library of `native/`, C++ | The `Geolocator` of the location API of Windows. |
| Linux | The library of `native/`, C++ | GeoClue over the system bus of D-Bus, which asks the person through the agent of the desktop. |

## Installation

The plugin depends on the [Permissions](../permissions) plugin, which registers and asks for its permissions, so the app lists both:

```sh
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path permissions --reference --app my-app
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path location --reference --app my-app
```

The commands list the plugins in the `plugins` section of the `haylen.json` of the app as references to their folders in the repository of the Haylen plugins, and pin the repository to its current commit in `haylen.lock`:

```json
{
    "plugins": {
        "permissions": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "permissions"
        },
        "location": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "location"
        }
    }
}
```

Without `--reference`, the command copies the plugin into `plugins/location/` of the app instead. A parameter that the entry leaves out takes its default from `plugin.json`, so the app follows the defaults of newer versions of the plugin. Every build takes the commit of `haylen.lock`, and `haylen plugin update location --app my-app` pins the commit that `main` names now.

## Parameters

| Parameter | Type | Default | Meaning |
| --- | --- | --- | --- |
| `locationUsage` | string | `"The app uses the location."` | The `NSLocationWhenInUseUsageDescription` and `NSLocationUsageDescription` of the Apple platforms, which the prompt of the location shows. |
| `preciseLocationUsage` | string | `"The app needs the precise location for this."` | The text of the prompt that asks a person who allowed the approximate location for the precise one, the key `preciseLocation` of `NSLocationTemporaryUsageDescriptionDictionary`. |
| `backgroundLocationUsage` | string | none | The `NSLocationAlwaysAndWhenInUseUsageDescription` of iOS and iPadOS, which only an app that reads the location in the background gives, and which the `Info.plist` leaves out without a value. |
| `backgroundNotification` | string | `"The app follows the location."` | The text of the notification that Android shows while a watch keeps the location in the background. |
| `macEntitlement` | boolean | `true` | Whether the macOS app signs with the entitlement `com.apple.security.personal-information.location`, without which the hardened runtime gives it no location. It has a value on macOS alone. |

## Setup

- **Apple platforms.** The plugin gives the `Info.plist` its `NSLocationWhenInUseUsageDescription` and `NSLocationUsageDescription` from `locationUsage`, and the key `preciseLocation` of `NSLocationTemporaryUsageDescriptionDictionary` from `preciseLocationUsage`. The macOS app signs with the entitlement `com.apple.security.personal-information.location` while `macEntitlement` is `true`. It links `CoreLocation.framework`.
- **The location in the background on iPhones and iPads.** The app gives the parameter `backgroundLocationUsage` a text, which becomes `NSLocationAlwaysAndWhenInUseUsageDescription`, and adds the mode `location` to `UIBackgroundModes` in `platforms.ios.infoPlist` of its `haylen.json`, which `watch` with `background` checks. Without them the permission and the watch answer `unsupported` with `data.missing`.
- **Android.** The manifest of the module declares `ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION`, so the prompt offers the precise location next to the approximate one, the location features as not required, and the foreground service `LocationWatchService` of type `location`. An app that watches in the background adds the permissions below to `platforms.android.manifest.permissions` of its `haylen.json`, which no other app needs and which Google Play asks about, and the plugin answers `unsupported` with `data.missing` without them.

```json
{
    "platforms": {
        "ios": {"infoPlist": {"UIBackgroundModes": ["location"]}},
        "android": {
            "manifest": {"permissions": ["android.permission.ACCESS_BACKGROUND_LOCATION", "android.permission.FOREGROUND_SERVICE", "android.permission.FOREGROUND_SERVICE_LOCATION"]}
        }
    }
}
```

- **Web.** The page needs a secure context, `https` or `localhost`, and a permissions policy that allows `geolocation`.
- **Windows.** The privacy settings of Windows let apps read the location, and the library asks through `AppCapability` while the settings ask the person.
- **Linux.** The system runs GeoClue and the desktop runs its agent, and GeoClue names the app by the identifier of `haylen.json`, which the Linux app gives its desktop entry, so the desktop player that runs an app without its desktop entry may be refused. The library links `libdbus-1`.

## Lua API

```lua
local location = require('location')
```

Every function that talks to the native part returns a call of `haylen.platform`, whose `await` inside a coroutine gives the answer, or `nil` and an error with `message`, `code` and `data`. A call asks for the permission it needs where the app does not hold it yet, the way `location.requestPermission(name)` does: `location`, or `preciseLocation` for a precise call, and `backgroundLocation` too for a watch in the background. The updates belong to the process, so the Lua API of every app that starts stops updates that an earlier app left running.

A place is a table with these fields, where a field that the device does not know is `nil`:

| Field | Type | Meaning |
| --- | --- | --- |
| `latitude`, `longitude` | number | The position in degrees. |
| `accuracy` | number | The radius in meters around the position that holds the device. |
| `altitude` | number or `nil` | Meters above the sea. Android tells it from version 14, and browsers measure only above the ellipsoid of WGS 84, so the web leaves it out. |
| `speed` | number or `nil` | Meters per second. |
| `heading` | number or `nil` | Degrees from true north, clockwise, of the way the device moves. |
| `timestamp` | number | Seconds since 1970 of the moment of the fix. |

### location.current(options)

Asks for one fix and gives a place. The table `options` is optional:

| Option | Type | Default | Meaning |
| --- | --- | --- | --- |
| `precise` | boolean | `false` | Whether the app needs the precise location, which asks for the permission `preciseLocation` and the best accuracy of the device. Without it the fix has the precision that the person allows. |
| `timeout` | number | `30` | Seconds after the permission without a fix, after which the call fails with the code `timeout`. |

Options that are no table raise `The options of "location.current" are a table.`, an unknown key raises `Unknown option "<key>".`, a `precise` that is no boolean raises `The option "precise" of "location.current" is a boolean.`, and a timeout that is no positive number raises `The option "timeout" of "location.current" is a positive number of seconds.`.

```lua
local async = require('async')
local location = require('location')

async.spawn(function()
    local place, err = location.current({timeout = 10}):await()
    print(place and string.format('%.5f, %.5f within %d m', place.latitude, place.longitude, place.accuracy) or err.message)
end)
```

### location.watch(options)

Starts the updates of the location and resolves once they run. The places reach the listeners of `location.onChanged`. A watch that runs stops first. The table `options` is optional:

| Option | Type | Default | Meaning |
| --- | --- | --- | --- |
| `distance` | number | `0` | The meters the device moves before the next update. The web, whose browsers have no such filter, sends a place only once it lies that far from the last one it sent. |
| `precise` | boolean | `false` | Whether the app needs the precise location, as for `location.current`. |
| `background` | boolean | `false` | Whether the updates go on while the app is in the background, which asks for the permission `backgroundLocation` too. Android shows the notification of `backgroundNotification` while they do. The web, tvOS and visionOS fail it with `unsupported`. |
| `owner` | table or userdata | none | The owner whose end stops the updates, such as a scene. Without it they run until `location.stop()`. |

Options that are no table raise `The options of "location.watch" are a table.`, an unknown key raises `Unknown option "<key>".`, a `precise` that is no boolean raises `The option "precise" of "location.watch" is a boolean.`, a distance that is no number of 0 or more raises `The option "distance" of "location.watch" is a number of meters, 0 or more.`, a `background` that is no boolean raises `The option "background" of "location.watch" is a boolean.`, and an owner that is not a table or a userdata raises `An owner must be a table or a userdata, not <type>.`. Apple TV gives one fix and no updates, so a watch fails there with `unsupported`.

```lua
local location = require('location')
local scene = require('haylen.scene')

scene.push({
    enter = function(self)
        location.onChanged(function(places)
            self.place = places[#places]
        end, {owner = self})
        scene.spawn(self, function()
            local _, err = location.watch({distance = 25, owner = self}):await()
            if err then
                print('No updates: ' .. err.message)
            end
        end)
    end,
})
```

### location.stop()

Stops the updates. Updates that do not run stop nothing, and the call still answers.

### location.onChanged(listener, options)

Calls `listener(places)` once per frame with the list of the places that arrived since the frame before, oldest first, so the newest place is `places[#places]`, and returns the connection of the listener, whose `disconnect()` stops it. The table `options` takes `owner`. An app that the engine halts in the background receives the places of that time in one list when it runs again.

### location.onStopped(listener, options)

Calls `listener({message, code})` when the updates stop by themselves, such as with the code `denied` when the person takes the permission back or `locationOff` when the location of the device is turned off, and returns the connection of the listener. The table `options` takes `owner`.

### location.permission(name)

Reads the state of the permission `name`, which is `'location'`, `'preciseLocation'` or `'backgroundLocation'`, as far as the platform tells it, without asking the person. It returns a call of `haylen.platform` whose `await` gives `'granted'`, `'prompt'`, `'denied'` or `'unknown'`. A platform without the capability fails the call with the code `unsupported` and the reason as `message`, such as `A page reads the location only while it shows.` for `backgroundLocation` on the web, and a platform without the native part of the plugin fails it with `noHandler`, as every call of the plugin. A missing name raises `The plugin "location" owns the permissions "location", "preciseLocation" and "backgroundLocation", so "location.permission" takes the name of one of them.`, and a name of another plugin raises `The plugin "location" owns no permission "<name>". It owns "location", "preciseLocation" and "backgroundLocation".`. Like every platform call, a failure that nothing awaits stops the app. [What each platform answers](#what-each-platform-answers) lists the states.

```lua
local async = require('async')
local location = require('location')

async.spawn(function()
    local state, failure = location.permission('location'):await()
    if state == 'prompt' then
        print('The app explains why it wants the location before it asks.')
    elseif not state then
        print(failure.code .. ': ' .. failure.message)
    end
end)
```

### location.requestPermission(name)

Asks the person for the permission `name` with the prompt of the system while its state is `'prompt'`, and returns a call of `haylen.platform` whose `await` gives the state that the person left: `'granted'`, `'denied'`, `'unknown'`, or `'prompt'` when the system did not ask. A permission that the app holds, or that the person refused, answers at once without a prompt. Where the platform asks for the location in the background only after the location, as Android does, `'backgroundLocation'` asks for `'location'` first. A project that lacks what the prompt needs, such as the usage description of the `Info.plist` or the permission of the Android manifest, fails the call with the code `unsupported`, the sentence that names what is missing and `data.missing`, which lists each requirement as `{kind, name, file, snippet}`, and so does a platform without the capability, with its reason. The names and the errors are those of `location.permission`.

Once a request did not allow a permission, the calls that need it fail with the code `denied` and the sentence `The person has not allowed the location. Ask for it with "location.requestPermission('location')", which shows the prompt of the system while the system still asks, or the person allows it in the settings of the system.`, which names `the precise location` with `'preciseLocation'` and `the location in the background` with `'backgroundLocation'` for the other two. Where the system did not show its prompt, the sentence is `The system did not show its prompt for the location, so the app does not hold it yet. Ask for it again later with "location.requestPermission('location')".`.

```lua
local async = require('async')
local location = require('location')

async.spawn(function()
    local state, failure = location.requestPermission('location'):await()
    if state == 'granted' then
        state, failure = location.requestPermission('backgroundLocation'):await()
    end
    print(state and 'The location in the background is ' .. state .. '.' or failure.code .. ': ' .. failure.message)
end)
```

## Errors

| Code | Message | When |
| --- | --- | --- |
| `denied` | The refusal sentence above. | The person refused the permission that the call needs. |
| `unsupported` | The reason, such as `Apple TV gives one fix of the location but no updates.` or `A page reads the location only while it shows.`, with `data.missing` for a requirement that the project lacks. | The platform has no such capability for the app. |
| `locationOff` | `The location of the device is turned off. The person turns it on in the settings of the system.` | The person turned the location of the device off. |
| `locationUnknown` | `The location is unknown: <reason>` | The device found no fix. |
| `timeout` | `No fix of the location came within <seconds> seconds.` | No fix came within the timeout of `location.current`. |
| `cancelled` | A sentence such as `A new watch of the location replaced this one before it started.` | On Linux, a watch that a new watch or `location.stop` replaced before GeoClue started, or a call of an app that ended. |
| `invalidParams` | A sentence that names the parameters that the call lacks. | On Windows and Linux, a call of the native API without the parameters that the Lua API sends. |

## Native API

| Method or event | Params or payload | Answer |
| --- | --- | --- |
| `location.reset` | `{}` | `null` |
| `location.current` | `{precise, timeout, desktopId}` | A place |
| `location.watch` | `{distance, precise, background, desktopId}` | `null` |
| `location.stop` | `{}` | `null` |
| `location.permission`, `location.requestPermission` | `{name}` | The name of the state, or a failure with the code `unsupported`, the reason and `data.missing`, which the Permissions plugin answers for the permissions that the native part registers on Apple platforms, Android and the web, and the library of `native/` answers on desktops |
| `location.changed` (batched event) | A place | |
| `location.stopped` (event) | `{message, code}` | |

The Lua API sends `desktopId`, the identifier of the app, on Linux alone, where GeoClue names the app by it.

## What each platform answers

| Platform | `location.permission('location')` | `location.permission('preciseLocation')` | `location.permission('backgroundLocation')` |
| --- | --- | --- | --- |
| iPhone and iPad | The authorization of Core Location: `prompt`, then `granted` for the location while in use or always, or `denied`. | `granted` with the full accuracy, and `prompt` while the person allows only the approximate location, whose request shows the prompt of the temporary precise location with the text of `preciseLocationUsage`. A person who keeps the approximate location in the first prompt answers `denied`. | `granted` for the location always, and `prompt` while the person allows it only in use, until iOS showed its prompt once, after which it answers `denied`, since iOS asks once. |
| Mac Catalyst and macOS app | The authorization of Core Location. | As on iPhones. | The same as `location`, since a Mac gives the location of an app in the background as in front. |
| tvOS and visionOS | The authorization of Core Location. | As on iPhones. | `unsupported`, since the device reads the location only while the app is in use. |
| Android | `granted` at any precision, `prompt`, or `denied` once Android no longer shows the prompt. | `granted` with `ACCESS_FINE_LOCATION`, whose request offers the precise location to a person who allowed the approximate one. | From Android 10 `ACCESS_BACKGROUND_LOCATION`, which Android asks for after the location, on a page of the settings from Android 11, and before Android 10 the same as `location`. |
| Web | The state of the Permissions API for `geolocation`, or `unknown`. | The same as `location`, since a browser decides the precision of its one location. | `unsupported`, since a page reads the location only while it shows. |
| macOS desktop player | `unsupported`, as above. | `unsupported`. | `unsupported`. |
| Windows | The setting of the privacy of the location through `AppCapability`: `granted`, `prompt`, `denied`, or `unknown` on a Windows without that API. | The same as `location`, since Windows gives the precision that its settings allow. | The same as `location`, since a desktop app runs in the background as in front. |
| Linux | `unknown`, since GeoClue asks through the agent of the desktop when the app reads the location and tells nothing before, and `unsupported` without GeoClue on the system bus. A desktop without an agent that answers GeoClue within 10 seconds fails the calls with `unsupported`. | The same as `location`. | The same as `location`. |

A state of `unsupported` fails the call of `location.permission` and `location.requestPermission` with the code `unsupported` and its reason.

## Platforms without the plugin

Every platform of Haylen runs a native part of the plugin. The desktop player of macOS, which `haylen app run` starts without `--target`, runs the library of `native/`, but Core Location gives the location only to an app bundle, so every call there fails with the code `unsupported` and every permission answers `unsupported`. The macOS app, which `haylen app run --target macos` builds, runs the Apple part.

## Sample

The app in `sample/` references the plugin with `"path": ".."` and the Permissions plugin with `"path": "../../permissions"`, and has a button for every call and permission, with the last place and the answer of each call:

```sh
haylen app run sample --target macos
haylen app run sample --target ios-simulator
haylen app run sample --target android
haylen app run sample --target web
```

The UI tests in `sample/ui-tests` simulate a place, through the location of the test on Apple platforms and through test providers on Android, answer the prompt of the location, read one fix of that place, ask for the location in the background, which iOS asks for in a second prompt, Android 10 in a dialog and later versions of Android on a page of their settings, and watch the location in the background. They run on the simulators, the emulator and devices:

```sh
haylen test --ui sample --target ios-simulator
haylen test --ui sample --target android
haylen test --ui sample --target ios --device <name or UDID>
```

## License

MIT, like Haylen.
