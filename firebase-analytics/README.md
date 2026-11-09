# 📊 Firebase Analytics

The Firebase Analytics plugin gives [Haylen](https://github.com/haylen-org/haylen) apps Google Analytics for Firebase: the app logs events with their parameters, names the user, sets user properties, tells the consent of the person and turns the collection on or off. It logs into the default Firebase app that the plugin [`firebase`](../firebase) configures, which the app lists too.

| Platform | Native part | What it uses |
| --- | --- | --- |
| iOS and iPadOS | `apple/FirebaseAnalyticsPlugin.swift` | `FirebaseAnalytics` of the Firebase Apple SDK, a Swift package at the exact version that `plugin.json` pins. |
| Android | The library module in `android/` | `firebase-analytics` of the Firebase Android SDK, at the version of the Firebase BoM that `android/build.gradle.kts` pins. |
| Web | `web/firebase-analytics.js` | The Analytics module of the Firebase JavaScript SDK, an ES module from the Firebase CDN at the version in its address. |

## Installation

The plugin needs the plugin `firebase`, which configures the Firebase app that it logs into:

```sh
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path firebase --reference --app my-app
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path firebase-analytics --reference --app my-app
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
                    "appId": "1:123456789012:web:0123456789abcdef",
                    "measurementId": "G-XXXXXXXXXX"
                }
            }
        },
        "firebase-analytics": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "firebase-analytics"
        }
    }
}
```

Without `--reference`, the commands copy the plugins into `plugins/firebase/` and `plugins/firebase-analytics/` of the app instead. A parameter that an entry leaves out takes its default from `plugin.json`, so the app follows the defaults of newer versions of the plugins. To stay on one version of the plugins, the app names a commit in `ref` instead of the branch `main`.

## Parameters

| Parameter | Platforms | Type | Default | Meaning |
| --- | --- | --- | --- | --- |
| `collectionEnabled` | All | boolean | `true` | Whether Analytics collects from the start. It writes `FIREBASE_ANALYTICS_COLLECTION_ENABLED` into the `Info.plist` on iOS and `firebase_analytics_collection_enabled` into the manifest on Android, and the web module turns the collection on or off as it loads. |

## Setup

1. Turn on Google Analytics in the settings of the Firebase project, which links the project to an Analytics property.
2. Download the configuration files again after that, since they then carry the identifiers of Analytics, and give the web app its `measurementId` in the `webConfig` of the plugin `firebase`.
3. Where the law asks for consent, start with `collectionEnabled` set to `false`, and call `setConsent` and `setCollectionEnabled(true)` once the person agrees.

The DebugView of the Firebase console shows the events of a device that runs in debug mode. On iOS the argument `-FIRDebugEnabled` of the launch turns it on, on Android the command `adb shell setprop debug.firebase.analytics.app <identifier>`, and on the web the debugger extension of Google Analytics in the browser.

## What each platform answers

| Call | iOS | Android | Web |
| --- | --- | --- | --- |
| `appInstanceId` | The app instance ID of Analytics, or `nil` while the collection is off. | The app instance ID of Analytics, or `nil` while the collection is off. | The client ID of Google Analytics, which stands in for the app instance. The SDK answers once Google Analytics knows the measurement ID, so with a configuration that names no real property the call never answers, and the app gives it up with `call:cancel()`. |
| `resetAnalyticsData` | Clears the data of Analytics on the device. | Clears the data of Analytics on the device. | Fails with the code `unsupported`, since the page keeps the data in the cookies of the site, which the page clears itself. |

Every call fails with the code `notConfigured` when no default Firebase app runs, as the README of the plugin `firebase` describes. Analytics sends its events later, in batches, so a call answers once the SDK took the event, and a project that names no real Firebase project still answers every call.

## Platforms without the plugin

| Platform | Reason |
| --- | --- |
| Mac Catalyst, tvOS and the macOS app | `FirebaseAnalytics` builds for them, but the plugin is verified only on iOS, so it gives them no native part. A platform becomes `native` in `implementations` once the plugin runs there. |
| visionOS | `FirebaseAnalytics` leaves visionOS out of its package. |
| Windows, Linux and macOS in the desktop player | Firebase offers no Analytics SDK for desktop apps. |

On these platforms the plugin has no native part, so `analytics.available` is `false` and every call fails with the code `noHandler`.

## Lua API

```lua
local analytics = require('firebase-analytics')
```

Every function returns a platform call of `haylen.platform`, which a coroutine awaits for the answer or the error. A call that only sends something needs no await.

### analytics.available

Whether the native part of the plugin runs on this platform: `true` on iOS, Android and the web.

### analytics.logEvent(name, params)

Logs the event `name` with an optional table of parameters, whose values are texts, numbers, flags or lists of item tables. Flags reach Analytics as `1` and `0` on Android. The [recommended events](https://support.google.com/analytics/answer/9267735) of Google Analytics, such as `level_up`, `post_score` or `purchase`, fill the reports of the console. A name that is no string with at least one character raises `The function "analytics.logEvent" takes the name of the event as a string with at least one character.`, and parameters that are no table raise `The parameters of the event "<name>" are a table.`.

```lua
local analytics = require('firebase-analytics')

analytics.logEvent('level_up', {level = 3, character = 'knight'})
analytics.logEvent('purchase', {currency = 'USD', value = 4.99, items = {{item_id = 'gems_100', item_name = '100 gems'}}})
```

### analytics.setUserId(id)

Names the user of the events that follow, or clears the name with `nil`.

```lua
local analytics = require('firebase-analytics')

analytics.setUserId('player-42')
```

### analytics.setUserProperty(name, value)

Sets the user property `name` to a string, or clears it with `nil`.

```lua
local analytics = require('firebase-analytics')

analytics.setUserProperty('favorite_mode', 'arena')
```

### analytics.setConsent(consent)

Sets the consent of the person: a table whose keys `analyticsStorage`, `adStorage`, `adUserData` and `adPersonalization` take `'granted'` or `'denied'`. Another key raises `Unknown option "<key>".`, and another value raises `The consent "<key>" takes "granted" or "denied".`.

```lua
local analytics = require('firebase-analytics')

analytics.setConsent({analyticsStorage = 'granted', adStorage = 'denied', adUserData = 'denied', adPersonalization = 'denied'})
```

### analytics.setCollectionEnabled(enabled)

Turns the collection of this device on or off. The `await` gives `{enabled}`.

```lua
local analytics = require('firebase-analytics')

analytics.setCollectionEnabled(true)
```

### analytics.appInstanceId()

The `await` gives `{id}`, the app instance ID of Analytics, as [what each platform answers](#what-each-platform-answers) lists.

```lua
local async = require('async')
local analytics = require('firebase-analytics')

async.spawn(function()
    local instance, err = analytics.appInstanceId():await()
    print(instance and instance.id or err.message)
end)
```

### analytics.resetAnalyticsData()

Clears the data that Analytics keeps on the device and starts a new app instance. The `await` gives `{reset}`, and the web fails it with the code `unsupported`.

```lua
local analytics = require('firebase-analytics')

analytics.resetAnalyticsData()
```

## Native API

| Method | Params | Answer |
| --- | --- | --- |
| `firebase-analytics.logEvent` | `{name, params}` | `null` |
| `firebase-analytics.setUserId` | `{id}` | `null` |
| `firebase-analytics.setUserProperty` | `{name, value}` | `null` |
| `firebase-analytics.setConsent` | `{analyticsStorage, adStorage, adUserData, adPersonalization}` | `null` |
| `firebase-analytics.setCollectionEnabled` | `{enabled}` | `{enabled}` |
| `firebase-analytics.appInstanceId` | `{}` | `{id}` |
| `firebase-analytics.resetAnalyticsData` | `{}` | `{reset}` |

The native parts fail a call whose parameters they cannot take with the code `invalidParams`.

## License

MIT, like Haylen.
