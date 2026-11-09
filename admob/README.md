# 📺 AdMob

The AdMob plugin gives [Haylen](https://github.com/haylen-org/haylen) apps the banner, interstitial and rewarded ads of Google AdMob on iOS and Android, and the consent form of the User Messaging Platform of Google, which asks the person for consent where the law requires it. The ads behave like the rest of the app:

- Interstitial and rewarded ads, the consent form and the privacy options are screens of the plugin. The engine covers the app while they show, so the app stands still, stays silent and hears `appInactive` and `appActive` around them.
- The banner is a view of the overlay of the engine, which reserves its edge of the safe area. The interface of the app, anchored to the safe area, moves out of its way. The page that a tap on the banner opens covers the app until it closes.

| Platform | Native part | SDK |
| --- | --- | --- |
| iOS and iPadOS | `apple/AdMobPlugin.swift` | Google Mobile Ads `13.12.0` and User Messaging Platform `3.1.0`, as Swift packages. |
| Android | The library module in `android/` | `com.google.android.gms:play-services-ads` `25.5.0` and `com.google.android.ump:user-messaging-platform` `4.0.0`, through Gradle. |

## Installation

```sh
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path admob --reference --app my-app
```

The command lists the plugin in the `plugins` section of the `haylen.json` of the app as a reference to its folder in the repository of the Haylen plugins, with an empty text for the app ID of AdMob of each platform, which the app fills in:

```json
{
    "plugins": {
        "admob": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "admob",
            "parameters": {
                "iosAppId": "ca-app-pub-3940256099942544~1458002511",
                "androidAppId": "ca-app-pub-3940256099942544~3347511713"
            }
        }
    }
}
```

Without `--reference`, the command copies the plugin into `plugins/admob/` of the app instead. A parameter that the entry leaves out takes its default from `plugin.json`, so the app follows the defaults of newer versions of the plugin. To stay on one version of the plugin, the app names a commit in `ref` instead of the branch `main`.

The app IDs above are the ones of the test ads of Google, which serve test ads without an account, and `admob.testUnits` holds the test ad units of each platform.

## Parameters

| Parameter | Platforms | Type | Default | Meaning |
| --- | --- | --- | --- | --- |
| `iosAppId` | iOS | string | Required | The app ID of the iOS app in AdMob, such as `ca-app-pub-3940256099942544~1458002511` of the test ads. |
| `androidAppId` | Android | string | Required | The app ID of the Android app in AdMob, such as `ca-app-pub-3940256099942544~3347511713` of the test ads. |
| `testDeviceIds` | All | array | `[]` | The IDs of the devices that always receive test ads, which the log of the SDK prints on the first request of each device. Simulators and emulators receive test ads without one. |

## Setup

1. Create an app for each platform in [AdMob](https://admob.google.com), and an ad unit for each kind of ad that the app shows. Give the app IDs to `iosAppId` and `androidAppId`, and the ad units to the calls of the Lua API.
2. Keep test ads while you develop: use the ad units of `admob.testUnits`, or add your devices to `testDeviceIds`. Clicking real ads of your own app breaks the policies of AdMob.
3. Create the consent message of your app in the Privacy and messaging section of AdMob, which `admob.requestConsent` shows where the law asks for it.
4. On iOS, the ads use the advertising identifier only when the person allows tracking. A consent message of AdMob may hold an explainer of the tracking prompt, and then `admob.requestConsent` shows the explainer and the prompt of the system after it, as the test app of Google does. Without one, the app asks before it starts the SDK: the [App Tracking Transparency](../app-tracking-transparency) plugin owns the permission `tracking`, and the app asks with `tracking.requestPermission()` of that plugin. AdMob shows ads without the permission too, which are less relevant to the person.

| Platform | What the plugin adds to the project |
| --- | --- |
| iOS | `GADApplicationIdentifier` with `iosAppId`, and the `SKAdNetworkItems` entry of Google, in the `Info.plist`. The two Swift packages. Add the `SKAdNetworkItems` of the ad networks that you mediate to the `Info.plist` of the app, next to the one of Google. |
| Android | The meta-data `com.google.android.gms.ads.APPLICATION_ID` with `androidAppId` in the manifest, and the two libraries, which bring the permissions that they need, such as `com.google.android.gms.permission.AD_ID`. |

## What each platform answers

| Call | iOS | Android |
| --- | --- | --- |
| `requestConsent` | The form shows only where the law asks for it, or where `debugGeography` is `'eea'`. A message with an explainer of the tracking prompt shows the explainer and the prompt of the system. Otherwise it answers at once with `notRequired`. | The form shows only where the law asks for it, or where `debugGeography` is `'eea'`. Otherwise it answers at once with `notRequired`. |
| `showBanner` | An adaptive banner as wide as the safe area of the window, in the large anchored size of Google. | The same, as wide as the safe area of the activity. |
| `showInterstitial`, `showRewarded` | The ad presents full screen over the app, and the call ends when the person closes it. | The same. |

The person closes full-screen ads and the consent forms, and the app cannot close them. So `call:cancel()` and the `timeout` of a call fail the call at once, while the ad stays until the person closes it and the app stays covered until then.

## Platforms without the plugin

| Platform | Reason |
| --- | --- |
| Mac Catalyst, tvOS, visionOS, macOS | Google Mobile Ads runs on iOS and iPadOS alone. |
| The web, Windows, Linux | AdMob has no SDK for them. |

On these platforms the plugin has no native part, so `admob.available` is `false` and every call fails with the code `noHandler`.

## Lua API

```lua
local admob = require('admob')
```

The calls return platform calls of `haylen.platform`, whose `await` gives the answer, or `nil` and an error with a `code` and a `message`.

### admob.available

Whether the native part of the plugin runs on this platform. Without it every call fails with the code `noHandler`.

### admob.testUnits

The ad units of the test ads of Google, `admob.testUnits.ios` and `admob.testUnits.android`, each with `banner`, `interstitial` and `rewarded`.

### admob.requestConsent(options)

Asks the person for consent with the form of the User Messaging Platform when the law asks for it, and does nothing visible otherwise. The `await` gives `{status, canRequestAds, privacyOptionsRequired}`, where `status` is `'obtained'`, `'required'`, `'notRequired'` or `'unknown'`. The table `options` is optional and takes these keys, to try the form outside the region where it shows:

| Key | Type | Meaning |
| --- | --- | --- |
| `debugGeography` | string | `'eea'` treats the device as one in the European Economic Area, and `'notEea'` as one outside it. |
| `testDeviceIds` | list | The hashed IDs of the devices that take `debugGeography`, which the log of the SDK prints. Simulators and emulators take it without one. |

The call fails with the code `consentFailed` when the form cannot load or show, and with `invalidParams` for a `debugGeography` of another name.

### admob.consentState()

The `await` gives the consent that the device holds now, `{status, canRequestAds, privacyOptionsRequired}`, without asking.

### admob.showPrivacyOptions()

Shows the privacy options form, which the app offers from its settings when `privacyOptionsRequired` is true. The `await` gives the consent once the person closes the form.

### admob.start()

Starts the SDK, which the app calls once `canRequestAds` is true and before it loads the first ad. The `await` gives `{started = true}`.

```lua
local admob = require('admob')
local tracking = require('app-tracking-transparency')
local async = require('async')
local haylen = require('haylen')

async.spawn(function()
    -- The App Tracking Transparency plugin shows the prompt of the tracking permission on iOS, and Android, which has no such prompt, answers "granted".
    tracking.requestPermission():await()

    local consent = admob.requestConsent():await()
    if not (consent and consent.canRequestAds) then
        return
    end
    admob.start():await()
    admob.showBanner(admob.testUnits[haylen.platform].banner, 'bottom')
end)
```

### admob.showBanner(adUnitId, position)

Shows an adaptive banner of the ad unit at the `'bottom'`, the default, or the `'top'` of the safe area, which reserves that edge, so the interface of the app anchored to the safe area moves out of its way. A banner that shows already goes away first. The banner keeps the width that it took when it showed, so an app whose `orientation` is `any` shows it again after the screen turns. On Android a new activity, such as one that a change of the language creates, places the banner again by itself. The `await` gives `{}` once the banner is placed, and `onBannerLoaded` and `onBannerFailed` tell whether an ad came. Another position raises `The position of a banner is "top" or "bottom", not "<position>".`.

### admob.hideBanner()

Takes the banner away and gives its edge of the safe area back. The `await` gives `{}`.

### admob.onBannerLoaded(listener, options), admob.onBannerFailed(listener, options)

Call `listener({width, height})`, the size of the banner in points or dp, when a banner loads, and `listener({message, code})`, with the error code of the SDK, when one fails. The table `options` may hold an `owner`, such as a scene, and the listener ends with it. Each returns the connection, whose `disconnect()` stops the listener.

```lua
local admob = require('admob')
local scene = require('haylen.scene')

scene.push({
    enter = function(self)
        admob.onBannerLoaded(function(size) print('The banner is ' .. size.height .. ' tall.') end, {owner = self})
        admob.onBannerFailed(function(failure) print('No banner: ' .. failure.message) end, {owner = self})
    end,
})
```

### admob.loadInterstitial(adUnitId), admob.showInterstitial()

Load an interstitial ad, and show it. The `await` of `loadInterstitial` gives `{loaded = true}`, or fails with the code `loadFailed`, whose `data.errorCode` is the error code of the SDK. The `await` of `showInterstitial` gives `{shown = true, rewarded = false}` once the person closes the ad. It fails with the code `notLoaded` when no ad was loaded, and `showFailed` when the ad could not show. Each ad shows once, so the app loads the next one after it showed.

```lua
local admob = require('admob')
local async = require('async')
local haylen = require('haylen')

async.spawn(function()
    local loaded, err = admob.loadInterstitial(admob.testUnits[haylen.platform].interstitial):await()
    if not loaded then
        print('No interstitial: ' .. err.message)
        return
    end
    admob.showInterstitial():await()
end)
```

### admob.loadRewarded(adUnitId), admob.showRewarded()

Load a rewarded ad, and show it, with the same answers and codes as the interstitial ad. The `await` of `showRewarded` gives `{shown, rewarded, type, amount}` once the person closes the ad, where `rewarded` tells whether the person earned the reward, and `type` and `amount` are the reward of the ad unit.

```lua
local admob = require('admob')
local async = require('async')
local haylen = require('haylen')

async.spawn(function()
    admob.loadRewarded(admob.testUnits[haylen.platform].rewarded):await()
    local result = admob.showRewarded():await()
    if result and result.rewarded then
        print('Earned ' .. result.amount .. ' ' .. result.type .. '.')
    end
end)
```

## Native API

| Method, screen or event | Params or payload | Answer |
| --- | --- | --- |
| `admob.start` | `{}` | `{started}` |
| `admob.consentState` | `{}` | `{status, canRequestAds, privacyOptionsRequired}` |
| `admob.consent` (screen) | `{debugGeography, testDeviceIds}` | `{status, canRequestAds, privacyOptionsRequired}` |
| `admob.privacyOptions` (screen) | `{}` | `{status, canRequestAds, privacyOptionsRequired}` |
| `admob.showBanner` | `{adUnitId, position}` | `{}` |
| `admob.hideBanner` | `{}` | `{}` |
| `admob.loadInterstitial`, `admob.loadRewarded` | `{adUnitId}` | `{loaded}` |
| `admob.interstitial`, `admob.rewarded` (screens) | `{}` | `{shown, rewarded, type, amount}` |
| `admob.bannerLoaded` (event) | `{width, height}` | |
| `admob.bannerFailed` (event) | `{message, code}` | |

## License

MIT, like Haylen.
