# 🕵️ App Tracking Transparency

The App Tracking Transparency plugin gives [Haylen](https://github.com/haylen-org/haylen) apps the permission `tracking`, which asks the person on Apple platforms whether the app may track them across the apps and websites of other companies, and the advertising identifier of the device once the person allows it. Apple requires that answer before an app or an ad SDK reads the advertising identifier. Android and the web show no prompt for tracking, so the permission answers `granted` there, and an app runs the same flow on every platform. The app checks and asks for the permission with `tracking.permission()` and `tracking.requestPermission()` of the plugin, which the [Permissions](../permissions) plugin answers, like every other permission of a plugin.

| Platform | Native part | What it uses |
| --- | --- | --- |
| iOS, iPadOS, Mac Catalyst, tvOS and the macOS app | `apple/AppTrackingTransparencyPlugin.swift` | AppTrackingTransparency for the permission and AdSupport for the advertising identifier. |
| Android | The library module in `android/` | The Permissions plugin alone, with no permission of the manifest. |
| Web | `web/app-tracking-transparency.js` | The Permissions plugin alone. |

## Installation

The plugin depends on the [Permissions](../permissions) plugin, which owns the contract of permissions, so the app lists both:

```sh
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path permissions --reference --app my-app
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path app-tracking-transparency --reference --app my-app
```

The commands list the plugins in the `plugins` section of the `haylen.json` of the app as references to their folders in the repository of the Haylen plugins:

```json
{
    "plugins": {
        "permissions": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "permissions"
        },
        "app-tracking-transparency": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "app-tracking-transparency"
        }
    }
}
```

Without `--reference`, each command copies its plugin into `plugins/<id>/` of the app instead. A parameter that the entry leaves out takes its default from `plugin.json`, so the app follows the defaults of newer versions of the plugin. To stay on one version of the plugin, the app names a commit in `ref` instead of the branch `main`.

## Parameters

| Parameter | Platforms | Type | Default | Meaning |
| --- | --- | --- | --- | --- |
| `trackingDescription` | Apple platforms | string | `Your data is used to show you ads that are more relevant to you.` | The text of the prompt that tells the person why the app asks, which becomes the `NSUserTrackingUsageDescription` of the `Info.plist`. App Review reads it, so write it in the words of your app. |

## Setup

On Apple platforms the plugin writes `trackingDescription` into the `Info.plist` of every platform as `NSUserTrackingUsageDescription`, and links `AppTrackingTransparency.framework` and `AdSupport.framework`. An app gives the text through the parameter, since the same key with another value in the `infoPlist` of a section of `platforms` in `haylen.json` stops the build. Without the key, `tracking.requestPermission()` shows no prompt, and it and `tracking.advertisingId()` fail with the code `unsupported` and the sentence that names the key and the `Info.plist` that lacks it, whose `data.missing` names them, since the system ends an app that asks without it.

The system shows the prompt once in the life of the app, and only while the app is active. So ask at a moment when the person understands why, such as right before the first ad or from the press of a button, never while the app launches. Ad SDKs, such as the one of the [AdMob](../admob) plugin, read the answer themselves, so the app asks before it starts them.

Android and the web need no setup. The Android part declares no permission of the manifest, and the web part needs nothing of the page.

## What each platform answers

| Platform | `tracking.permission()` | `tracking.requestPermission()` |
| --- | --- | --- |
| iOS, iPadOS, Mac Catalyst, tvOS, macOS | `prompt` until the person answers, then `granted` or `denied`. A device that a parent or an organization restricts never lets the person allow tracking, so it answers `denied`. | Shows the prompt while the state is `prompt` and the app is active, and answers the choice of the person. The system shows the prompt only to an active app, so a request while the app is not active, such as during its launch, shows nothing and answers `prompt`, and the app asks again once it is active, such as from the press of a button. Answers the state at once otherwise. |
| Android | `granted`, since Android shows no prompt for tracking. | `granted` without a prompt. |
| Web | `granted`, since browsers show no prompt for tracking. | `granted` without a prompt. |

The call `tracking.advertisingId()` answers the identifier on Apple platforms. Android fails it with the code `unsupported`, since its advertising identifier belongs to Google Play services, which this plugin does not bring, and the web fails it with the code `unsupported`, since the web has no advertising identifier.

## Platforms without the plugin

| Platform | Reason |
| --- | --- |
| Windows, Linux | These systems have no tracking prompt and no advertising identifier. |
| visionOS | The SDK of visionOS has no AdSupport, so it gives apps no advertising identifier. |
| macOS in the desktop player | The player of `haylen app run` loads the native libraries of plugins alone, and this plugin has none. The macOS app, `haylen app run --target macos`, runs the Apple part. |

On these platforms the plugin has no native part, so `tracking.available` is `false`, `tracking.advertisingId` fails with the code `noHandler`, and so do `tracking.permission()` and `tracking.requestPermission()`.

## Lua API

```lua
local tracking = require('app-tracking-transparency')
```

### tracking.available

Whether the native part of the plugin runs on this platform. Without it every call fails with the code `noHandler`.

### tracking.permission()

Reads the state of the permission `tracking`, which the plugin owns, without asking the person. It returns a call of `haylen.platform` whose `await` gives `'granted'`, `'prompt'`, `'denied'` or `'unknown'`. A platform without the capability fails the call with the code `unsupported` and the reason as `message`, with `data.missing` for a requirement that the project lacks, and a platform without the native part fails it with `noHandler`, as every call of the plugin. Like every platform call, a failure that nothing awaits stops the app.

```lua
local async = require('async')
local tracking = require('app-tracking-transparency')

async.spawn(function()
    local state, failure = tracking.permission():await()
    print(state and 'Tracking is ' .. state .. '.' or failure.code .. ': ' .. failure.message)
end)
```

### tracking.requestPermission()

Asks the person for the permission `tracking` with the prompt of the system, only while the state is `'prompt'`, and returns a call of `haylen.platform` whose `await` gives the state that the person left. Any other state answers at once, without a prompt. A platform without the capability, or an `Info.plist` without `NSUserTrackingUsageDescription`, fails the call with the code `unsupported` and the reason as `message`, with `data.missing` for the key that the project lacks, and a platform without the native part fails it with `noHandler`. Like every platform call, a failure that nothing awaits stops the app. The app asks at a moment that it picks, since the system shows the prompt once in the life of the app.

A call that needs tracking while the person does not allow it fails with the code `denied` and the sentence `The person has not allowed tracking across the apps and websites of other companies. Ask for it with "app-tracking-transparency.requestPermission('tracking')", which shows the prompt of the system while the system still asks, or the person allows it in the settings of the system.`.

```lua
local async = require('async')
local tracking = require('app-tracking-transparency')

async.spawn(function()
    local state, failure = tracking.requestPermission():await()
    if not state then
        print(failure.code .. ': ' .. failure.message)
        return
    end
    print('Tracking is ' .. state .. '.')
end)
```

### tracking.advertisingId()

Returns a platform call whose `await` gives `{id}`, the advertising identifier of the device, such as `'6D2A1F4C-0B7E-4C1D-9E3A-2F8B5C7D9A10'`. The call needs the permission `tracking`: where the person has not answered yet, it shows the prompt first, as every use of a permission does. On Apple platforms it fails with the code `denied` while the person does not allow tracking, with the sentence of [`tracking.requestPermission()`](#trackingrequestpermission), and with the code `unsupported` when the `Info.plist` lacks `NSUserTrackingUsageDescription`. Simulators give an identifier of zeros. Android and the web fail it with the code `unsupported`, as [what each platform answers](#what-each-platform-answers) says.

```lua
local async = require('async')
local tracking = require('app-tracking-transparency')

async.spawn(function()
    local result, err = tracking.advertisingId():await()
    print(result and result.id or err.code)
end)
```

## Native API

| Method | Params | Answer |
| --- | --- | --- |
| `app-tracking-transparency.advertisingId` | `{}` | `{id}` |
| `app-tracking-transparency.permission`, `app-tracking-transparency.requestPermission` | `{name}` | The name of the state, or a failure with the code `unsupported`, the reason and `data.missing`, which the Permissions plugin answers on Apple platforms, Android and the web from the permission that the plugin registers there. |

## License

MIT, like Haylen.
