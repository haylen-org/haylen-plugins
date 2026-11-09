# 🔥 Firebase

The Firebase plugin gives [Haylen](https://github.com/haylen-org/haylen) apps the default Firebase app of their Firebase project, configured from the configuration files of the project before any Lua runs. The plugins [`firebase-analytics`](../firebase-analytics), [`firebase-crashlytics`](../firebase-crashlytics) and [`firebase-messaging`](../firebase-messaging) need it and use that app. The plugin also tells the app which Firebase app runs and turns the automatic data collection of every Firebase library on or off.

| Platform | Native part | What it uses |
| --- | --- | --- |
| iOS and iPadOS | `apple/FirebasePlugin.swift` | `FirebaseCore` of the Firebase Apple SDK, a Swift package at the exact version that `plugin.json` pins. |
| Android | The library module in `android/` | `firebase-common` of the Firebase Android SDK, at the version of the Firebase BoM that `android/build.gradle.kts` pins, and the Google services Gradle plugin that `plugin.json` pins. |
| Web | `web/firebase.js` | The app module of the Firebase JavaScript SDK, an ES module from the Firebase CDN at the version in its address. |

## Installation

```sh
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path firebase --reference --app my-app
```

The command lists the plugin in the `plugins` section of the `haylen.json` of the app as a reference to its folder in the repository of the Haylen plugins, with an empty text for each required parameter, which the app fills in with the configuration of its Firebase project:

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
                    "authDomain": "my-app.firebaseapp.com",
                    "projectId": "my-app",
                    "storageBucket": "my-app.firebasestorage.app",
                    "messagingSenderId": "123456789012",
                    "appId": "1:123456789012:web:0123456789abcdef",
                    "measurementId": "G-XXXXXXXXXX"
                }
            }
        }
    }
}
```

Without `--reference`, the command copies the plugin into `plugins/firebase/` of the app instead. A parameter that the entry leaves out takes its default from `plugin.json`, so the app follows the defaults of newer versions of the plugin. To stay on one version of the plugin, the app names a commit in `ref` instead of the branch `main`.

## Parameters

| Parameter | Platforms | Type | Required | Meaning |
| --- | --- | --- | --- | --- |
| `servicesPlist` | iOS | file | Yes | The `GoogleService-Info.plist` of the iOS app of the Firebase project, relative to the app folder. |
| `servicesJson` | Android | file | Yes | The `google-services.json` of the Android app of the Firebase project, relative to the app folder. |
| `webConfig` | Web | object | Yes | The configuration object of the web app of the Firebase project, with `apiKey`, `authDomain`, `projectId`, `appId`, `messagingSenderId` and `measurementId`. |

## Setup

1. Create a project in the [Firebase console](https://console.firebase.google.com) and add an app for each platform that the app ships to: an iOS app with the `identifier` of `haylen.json` as its bundle ID, an Android app with the same identifier as its package name, and a web app.
2. Download the `GoogleService-Info.plist` of the iOS app and the `google-services.json` of the Android app. Keep them in the app folder outside `source/` and `content/`, such as in `platform/firebase/`, so they never ship inside the package of the app.
3. Copy the configuration object of the web app from the settings of the project into `webConfig`.

### iOS

The plugin copies the file of `servicesPlist` into the app bundle under its own name, and configures the default Firebase app from it while the app launches. It turns off the swizzling of the application delegate by Firebase with `FirebaseAppDelegateProxyEnabled`, since the Haylen runtime hands the events of the app to the plugins that need them. Crashlytics uploads the symbols of a Release build only with a file named `GoogleService-Info.plist`, so keep that name.

### Android

The plugin copies the file of `servicesJson` to `app/google-services.json` of the Android project and applies the Google services Gradle plugin, which turns the file into the resources that configure Firebase when the process starts. The Android project that the tooling generates for the app receives the file on every build.

### Web

The plugin initializes the default Firebase app from `webConfig` before the app starts. A `webConfig` without `apiKey` or `appId` stops the page from loading with the code `notConfigured`.

## What each platform answers

| Platform | A missing or invalid configuration |
| --- | --- |
| iOS | The log says once that Firebase stays off, and every call of the Firebase plugins fails with the code `notConfigured`. |
| Android | The provider of Firebase configures no default app, and every call of the Firebase plugins fails with the code `notConfigured`. |
| Web | The page stops loading with the error of the plugin, since the configuration is part of the page. |

A configuration that names no real Firebase project still configures the app, so the calls answer, while the calls of the other Firebase plugins that reach the servers of Firebase fail with their typed codes.

## Platforms without the plugin

| Platform | Reason |
| --- | --- |
| Mac Catalyst, tvOS and the macOS app | The Firebase Apple SDK builds for them, but the plugin is verified only on iOS, so it gives them no native part. A platform becomes `native` in `implementations` once the plugin runs there. |
| visionOS | The Firebase Apple SDK does not list visionOS among the platforms of its package, and `FirebaseAnalytics` leaves it out. |
| Windows, Linux and macOS in the desktop player | Firebase offers no SDK of Analytics, Crashlytics or Cloud Messaging for desktop apps, which are the products that use the default app of this plugin. |

On these platforms the plugin has no native part, so `firebase.available` is `false` and every call fails with the code `noHandler`.

## Lua API

```lua
local firebase = require('firebase')
```

### firebase.available

Whether the native part of the plugin runs on this platform: `true` on iOS, Android and the web.

### firebase.app()

Returns a platform call whose `await` gives the default Firebase app as `{name, projectId, appId, senderId, dataCollection}`, or `nil` and an error with the code `notConfigured` when the configuration of the platform is missing or invalid.

```lua
local async = require('async')
local firebase = require('firebase')

async.spawn(function()
    local app, err = firebase.app():await()
    print(app and ('The Firebase project is ' .. app.projectId .. '.') or err.message)
end)
```

### firebase.setDataCollection(enabled)

Turns the automatic data collection of every Firebase library on or off, which an app keeps off until the person agrees where the law asks for consent. Returns a platform call whose `await` gives `{enabled}`. A value that is not a boolean raises `The function "firebase.setDataCollection" takes a boolean.`.

```lua
local firebase = require('firebase')

firebase.setDataCollection(false)
```

## Native API

| Method | Params | Answer |
| --- | --- | --- |
| `firebase.app` | `{}` | `{name, projectId, appId, senderId, dataCollection}` |
| `firebase.setDataCollection` | `{enabled}` | `{enabled}` |

Both fail with the code `notConfigured` when no default Firebase app runs.

## License

MIT, like Haylen.
