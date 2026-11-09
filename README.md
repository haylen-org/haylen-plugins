<p align="center">
    <a href="https://github.com/haylen-org/haylen-plugins" target="_blank" rel="noopener noreferrer"><img width="120" src="extras/images/symbol.svg" alt=""></a>
</p>

<h1 align="center">Haylen Plugins</h1>

<p align="center">
    <a href="https://github.com/haylen-org/haylen-plugins/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
    <a href="https://github.com/haylen-org/haylen"><img src="https://img.shields.io/badge/made%20for-Haylen-07112F.svg" alt="Made for Haylen"></a>
    <a href="https://github.com/varn-org/varn"><img src="https://img.shields.io/badge/Lua-Varn-000080.svg" alt="Lua through Varn"></a>
</p>

<p align="center">
The native plugins of Haylen apps: the optional capabilities of the device and the system, and the SDKs of ads, analytics, crash reports, messaging, purchases and store delivery, each with one Lua API on every platform.
</p>

<br>

## What it is

[Haylen](https://github.com/haylen-org/haylen) keeps in the engine only what every app needs to run. Every optional capability, such as the camera, the location or notifications, and every third-party SDK lives in a native plugin. This repository holds those plugins, one folder each, named after the id of the plugin. A plugin is a `plugin.json` with its parameters and what it brings to each platform, a Lua API in `source/`, and a native part for each platform it serves: Swift in `apple/`, a Kotlin library module in `android/`, an ES module in `web/` and a C or C++ library in `native/` for the desktops. The plugin format is the one that `docs/platform/plugins.md` of Haylen describes.

The README of each plugin documents its installation, its parameters, its setup on each platform, its complete Lua API and what each platform answers. A capability that a platform gates, such as the camera, is a permission that the plugin owns through the plugin [`permissions`](permissions), which holds the permission contract of every platform, and the app checks and asks for it with `<id>.permission()` and `<id>.requestPermission()` of the plugin, such as `camera.requestPermission()`. A plugin with a permission depends on `permissions`, so the app lists both.

## Plugins

| Plugin | Description | Platforms |
| --- | --- | --- |
| [`admob`](admob) | The banner, interstitial and rewarded ads of Google AdMob, with the consent form of the User Messaging Platform. | iOS, Android |
| [`app-tracking-transparency`](app-tracking-transparency) | The permission `tracking`, which asks the person on Apple platforms whether the app may track them, and the advertising identifier once they allow it. | iOS, Mac Catalyst, tvOS, macOS, Android, Web |
| [`background-assets`](background-assets) | The named packs of the content as asset packs that the App Store hosts with Background Assets, downloaded with the install or when the app asks for them. | iOS, tvOS, visionOS |
| [`bluetooth`](bluetooth) | Bluetooth Low Energy as a central: scans, connections, services, characteristics, reads, writes and notifications, with the permission `bluetooth`. | iOS, Mac Catalyst, tvOS, visionOS, macOS, Android, Web, Windows, Linux |
| [`camera`](camera) | The cameras of the device in a video stream, with photos as JPEG bytes and the permission `camera`. | iOS, Mac Catalyst, tvOS, visionOS, macOS, Android, Web, Windows, Linux |
| [`dialogs`](dialogs) | Native messages and the pickers of files to open, of a place to save, of a folder and of photos. | iOS, Mac Catalyst, tvOS, visionOS, macOS, Android, Web, Windows, Linux |
| [`firebase`](firebase) | Configures the Firebase app that the other Firebase plugins use. | iOS, Android, Web |
| [`firebase-analytics`](firebase-analytics) | Events, user properties and consent of Google Analytics through Firebase. | iOS, Android, Web |
| [`firebase-crashlytics`](firebase-crashlytics) | Crashes, the Lua errors that stop the app and the errors the app records, in Firebase Crashlytics. | iOS, Android |
| [`firebase-messaging`](firebase-messaging) | Push notifications and data messages of Firebase Cloud Messaging, with the registration of the app, topics and the taps that open the app. | iOS, Android, Web |
| [`google-analytics`](google-analytics) | The events, user properties and consent of a web app in Google Analytics 4 through gtag.js. | Web |
| [`haptics`](haptics) | Vibration and the impacts, selection ticks and notification feedback of the haptic engine. | iOS, Mac Catalyst, tvOS, visionOS, macOS, Android, Web, Windows, Linux |
| [`links`](links) | Opens a url with the app that the system picks for it. | iOS, Mac Catalyst, tvOS, visionOS, macOS, Android, Web, Windows, Linux |
| [`local-network`](local-network) | The permission `localNetwork`, the picker of the services of one type on the local network, which Android shows without the permission, and the advertisement of a service of the app. | iOS, Mac Catalyst, tvOS, visionOS, macOS, Android, Web |
| [`location`](location) | One fix of the location or its updates, also in the background, with the permissions `location`, `preciseLocation` and `backgroundLocation`. | iOS, Mac Catalyst, tvOS, visionOS, macOS, Android, Web, Windows, Linux |
| [`media-session`](media-session) | What the app plays in the now-playing controls of the system, the commands of those controls, of the media keys and of the buttons of headsets and remotes, and the sound of the app in the background. | iOS, Mac Catalyst, tvOS, visionOS, macOS, Android, Web, Windows |
| [`microphone`](microphone) | The microphone of the device in an audio stream of mono samples, with its level and the permission `microphone`. | iOS, Mac Catalyst, tvOS, visionOS, macOS, Android, Web, Windows, Linux |
| [`motion`](motion) | The accelerometer, the gyroscope and the attitude of the device, with the permission `motion`. | iOS, Mac Catalyst, tvOS, visionOS, macOS, Android, Web, Windows, Linux |
| [`notifications`](notifications) | Local notifications that the app schedules, cancels and lists, and the tap that opens the app, with the permission `notifications`. | iOS, Mac Catalyst, visionOS, macOS, Android, Web, Windows, Linux |
| [`permissions`](permissions) | The permission contract of the plugins that own a permission: the five states, the registration in each native part, one queue of the prompts of the system and `permissions.state` and `permissions.request` in Lua. | iOS, Mac Catalyst, tvOS, visionOS, macOS, Android, Web |
| [`play-asset-delivery`](play-asset-delivery) | The named packs of the content as asset packs of Google Play, downloaded right after the install or when the app asks for them. | Android |
| [`playgama`](playgama) | The platform, the player, the ads, the storage and the messages of the game platforms of Playgama Bridge. | Web |
| [`revenuecat`](revenuecat) | In-app purchases and subscriptions through RevenueCat, with offerings, purchases, restores, entitlements and the user of the app. | iOS, Mac Catalyst, tvOS, macOS, Android |
| [`share`](share) | The share sheet of the system for a text, a url and files. | iOS, Mac Catalyst, visionOS, macOS, Android, Web, Windows |

The table lists the platforms where each plugin has a native part. On every other platform the `implementations` of its `plugin.json` name `lua`: the Lua API runs without a native part, its calls fail with a typed code, and the README of the plugin says why the plugin does not serve that platform.

## Adding a plugin to an app

An app takes a plugin from its folder in this repository, at a branch, a tag or a commit:

```sh
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path camera --reference --app my-app
```

With `--reference`, the command lists the repository, the ref and the folder of the plugin in the `haylen.json` of the app, and pins the commit that the ref names in `haylen.lock`, which `haylen plugin update` moves to a newer commit:

```json
{
    "plugins": {
        "camera": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "camera"
        }
    }
}
```

Without `--reference`, the command copies the plugin into `plugins/camera/` of the app instead. A parameter that the entry leaves out takes its default from the `plugin.json` of the plugin, and the values that the app gives go under `parameters`. A Release build needs the pin of every referenced repository, so the app commits `haylen.lock` next to `haylen.json`.

## Samples and labs

- The system plugins each have a sample app in `sample/`, which references the plugin with `"path": ".."` and has a button for each call.
- [`plugin-lab`](plugin-lab) is a Lua app that references the SDK plugins and logs what each call answers, so they are checked on each platform from one app. It runs with the test ads of Google and with placeholder keys and configuration files in `plugin-lab/platform/firebase/` that name no real Firebase project or RevenueCat key, so everything builds, starts and answers, while the calls that need a real account fail with the typed codes of each plugin.
- [`pack-lab`](pack-lab) is a Lua app with two named packs of content and the two store plugins that deliver them, so a Release build checks the delivery of packs by Google Play and the App Store.

```sh
haylen app run plugin-lab --target ios-simulator
haylen app run plugin-lab --target android
haylen app run plugin-lab --target web
haylen app run pack-lab --target android --config Release
haylen app run pack-lab --target ios-simulator --config Release
```

## License

The plugins are free for personal and commercial work under the MIT License of [`LICENSE`](LICENSE). Every contribution becomes part of them under the same license.
