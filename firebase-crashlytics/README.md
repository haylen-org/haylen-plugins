# 💥 Firebase Crashlytics

The Firebase Crashlytics plugin gives [Haylen](https://github.com/haylen-org/haylen) apps the crash reports of Firebase Crashlytics. Native crashes reach Crashlytics on their own, and so does every Lua error that stops the app, as a non-fatal error whose stack is the stack of the Lua code, so the console shows the file, the line and the function of each frame. The app adds lines to the log of the next report, names the user, sets custom keys, records errors of its own and turns the reports on or off. It reports through the default Firebase app that the plugin [`firebase`](../firebase) configures, which the app lists too.

| Platform | Native part | What it uses |
| --- | --- | --- |
| iOS and iPadOS | `apple/FirebaseCrashlyticsPlugin.swift` | `FirebaseCrashlytics` of the Firebase Apple SDK, a Swift package at the exact version that `plugin.json` pins, and its script `run`, which uploads the symbols of Release builds. |
| Android | The library module in `android/` | `firebase-crashlytics` of the Firebase Android SDK, at the version of the Firebase BoM that `android/build.gradle.kts` pins, and the Crashlytics Gradle plugin that `plugin.json` pins. |

## Installation

The plugin needs the plugin `firebase`:

```sh
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path firebase --reference --app my-app
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path firebase-crashlytics --reference --app my-app
```

The commands list both plugins in the `plugins` section of the `haylen.json` of the app as references to their folders in the repository of the Haylen plugins, with an empty text for each required parameter, which the app fills in with the configuration of its Firebase project:

```json
{
    "plugins": {
        "firebase": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "firebase",
            "parameters": {
                "servicesPlist": "platform/firebase/GoogleService-Info.plist",
                "servicesJson": "platform/firebase/google-services.json",
                "webConfig": {
                    "apiKey": "AIza...",
                    "appId": "1:123456789012:web:0123456789abcdef"
                }
            }
        },
        "firebase-crashlytics": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "firebase-crashlytics"
        }
    }
}
```

Without `--reference`, the commands copy the plugins into `plugins/firebase/` and `plugins/firebase-crashlytics/` of the app instead. A parameter that an entry leaves out takes its default from `plugin.json`, so the app follows the defaults of newer versions of the plugins. To stay on one version of the plugins, the app names a commit in `ref` instead of the branch `main`.

## Parameters

| Parameter | Platforms | Type | Default | Meaning |
| --- | --- | --- | --- | --- |
| `collectionEnabled` | All | boolean | `true` | Whether Crashlytics sends reports from the start. It writes `FirebaseCrashlyticsCollectionEnabled` into the `Info.plist` on iOS and `firebase_crashlytics_collection_enabled` into the manifest on Android. |
| `reportLuaErrors` | All | boolean | `true` | Whether every Lua error that stops the app, the one that its error screen shows, reaches Crashlytics as a non-fatal error with the stack of the Lua code. |

## Setup

1. Open Crashlytics in the Firebase console and follow its first step, which waits for the first report of the app.
2. Run the app on a device, call `crashlytics.crash()`, and start the app again, which sends the report of the crash.

### iOS

The plugin adds a build phase that runs the script `run` of Crashlytics for every Release build, which uploads the dSYM, so the reports of the App Store and TestFlight show the names of the native frames. The phase writes no file, so it sets `basedOnDependencyAnalysis` to `false` and runs on every build. The script finds the checkout of the package at `SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run` of the derived data of the build, and it reads the `GoogleService-Info.plist` of the app bundle, so the file of `servicesPlist` of the plugin `firebase` keeps that name. The upload needs the network and a real Firebase project. A C++ app builds its Swift packages in a folder of its own, outside the derived data of its build, and Haylen names that folder to no build script, so the script finds no checkout there and a Release build of a C++ app with this plugin stops at it.

The Lua errors reach the plugin through `appDidFail(with:)` of the plugin protocol of Haylen. Crashlytics logs at the start of the app that each fatal signal "has a non-Crashlytics handler". That handler is the crash guard of Haylen, which writes a report of each native crash for the next start of the app and then hands the crash to the handlers that were there before it, the ones of Crashlytics, so Crashlytics still reports every crash.

### Android

The plugin applies the Crashlytics Gradle plugin, which uploads the mapping file of R8 with every Release build, so the reports show the names that R8 replaced. The upload needs the network and a real Firebase project. The Lua errors reach the plugin through `onAppError` of the plugin class.

## What each platform answers

Every call fails with the code `notConfigured` when no default Firebase app runs, as the README of the plugin `firebase` describes, and the errors of the app then reach no report. Crashlytics keeps the reports on the device and sends them when the app starts again, so a project that names no real Firebase project answers every call and keeps its reports.

## Platforms without the plugin

| Platform | Reason |
| --- | --- |
| Web | Crashlytics has no SDK for the web. |
| Mac Catalyst, tvOS and the macOS app | `FirebaseCrashlytics` builds for them, but the plugin is verified only on iOS, so it gives them no native part. A platform becomes `native` in `implementations` once the plugin runs there. |
| visionOS | The Firebase Apple SDK does not list visionOS among the platforms of its package. |
| Windows, Linux and macOS in the desktop player | Firebase offers no Crashlytics SDK for desktop apps. |

On these platforms the plugin has no native part, so `crashlytics.available` is `false` and every call fails with the code `noHandler`.

## Lua API

```lua
local crashlytics = require('firebase-crashlytics')
```

Every function returns a platform call of `haylen.platform`, which a coroutine awaits for the answer or the error. A call that only sends something needs no await.

### crashlytics.available

Whether the native part of the plugin runs on this platform: `true` on iOS and Android.

### crashlytics.log(message)

Adds a line to the log that the next report carries, such as the steps that led to a crash. The `await` gives `{logged}`. A message that is no string raises `The function "crashlytics.log" takes a string.`.

```lua
local crashlytics = require('firebase-crashlytics')

crashlytics.log('Entered the boss room.')
```

### crashlytics.setUserId(id)

Names the user of the next reports, or clears the name with `nil`.

```lua
local crashlytics = require('firebase-crashlytics')

crashlytics.setUserId('player-42')
```

### crashlytics.setCustomKeys(keys)

Sets custom keys of the next reports from a table whose keys are strings and whose values are strings, numbers or booleans. Another value raises `The custom key "<key>" takes a string, a number or a boolean.`.

```lua
local crashlytics = require('firebase-crashlytics')

crashlytics.setCustomKeys({level = 3, mode = 'arena', sound = true})
```

### crashlytics.recordError(message, frames)

Records a non-fatal error with its message and, optionally, the frames of its stack: a list of `{source, line, function}` tables from the innermost call outward, whose `source` is a string and whose `line` is an integer.

```lua
local crashlytics = require('firebase-crashlytics')

local ok, err = pcall(loadSave)
if not ok then
    crashlytics.recordError('The save did not load: ' .. tostring(err), {{source = 'source/save.lua', line = 12, ['function'] = 'loadSave'}})
end
```

### crashlytics.setCollectionEnabled(enabled)

Turns the reports of this device on or off. The `await` gives `{enabled}`.

```lua
local crashlytics = require('firebase-crashlytics')

crashlytics.setCollectionEnabled(false)
```

### crashlytics.didCrashOnPreviousExecution()

The `await` gives `{crashed}`, whether the previous run of the app crashed, so the app may apologize or offer to send feedback.

```lua
local async = require('async')
local crashlytics = require('firebase-crashlytics')

async.spawn(function()
    local previous = crashlytics.didCrashOnPreviousExecution():await()
    if previous and previous.crashed then
        print('The last run crashed.')
    end
end)
```

### crashlytics.sendUnsentReports(), crashlytics.deleteUnsentReports()

Send or delete the reports that wait while the collection is off. The `await` gives `{sent}` or `{deleted}`.

```lua
local crashlytics = require('firebase-crashlytics')

crashlytics.sendUnsentReports()
```

### crashlytics.crash()

Crashes the app half a second after the answer, so a project checks that its crashes reach Crashlytics. Never call it in a build that people play.

```lua
local crashlytics = require('firebase-crashlytics')

crashlytics.crash()
```

## Native API

| Method | Params | Answer |
| --- | --- | --- |
| `firebase-crashlytics.log` | `{message}` | `{logged}` |
| `firebase-crashlytics.setUserId` | `{id}` | `null` |
| `firebase-crashlytics.setCustomKeys` | `{<key> = value}` | `null` |
| `firebase-crashlytics.recordError` | `{message, frames}` | `null` |
| `firebase-crashlytics.setCollectionEnabled` | `{enabled}` | `{enabled}` |
| `firebase-crashlytics.didCrashOnPreviousExecution` | `{}` | `{crashed}` |
| `firebase-crashlytics.sendUnsentReports` | `{}` | `{sent}` |
| `firebase-crashlytics.deleteUnsentReports` | `{}` | `{deleted}` |
| `firebase-crashlytics.crash` | `{}` | `{crashing}` |

The native parts fail a call whose parameters they cannot take with the code `invalidParams`.

## License

MIT, like Haylen.
