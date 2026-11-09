# 📊 Google Analytics

The Google Analytics plugin sends the events of a [Haylen](https://github.com/haylen-org/haylen) web app to a property of Google Analytics 4 through gtag.js, with the user ID, user properties and the consent of the person. It needs no permission.

| Platform | Native part | What it uses |
| --- | --- | --- |
| Web | `web/google-analytics.js` | gtag.js of Google, which the plugin loads with the measurement ID of the app before the app starts. |

## Installation

```sh
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path google-analytics --reference --app my-app
```

The command lists the plugin in the `plugins` section of the `haylen.json` of the app as a reference to its folder in the repository of the Haylen plugins, with an empty `measurementId`, which the app fills in with the measurement ID of its web data stream:

```json
{
    "plugins": {
        "google-analytics": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "google-analytics",
            "parameters": {
                "measurementId": "G-XXXXXXXXXX"
            }
        }
    }
}
```

Without `--reference`, the command copies the plugin into `plugins/google-analytics/` of the app instead. A parameter that the entry leaves out takes its default from `plugin.json`, so the app follows the defaults of newer versions of the plugin. To stay on one version of the plugin, the app names a commit in `ref` instead of the branch `main`.

## Parameters

| Parameter | Type | Default | Meaning |
| --- | --- | --- | --- |
| `measurementId` | string | Required | The measurement ID of the web data stream of the Google Analytics property, such as `G-XXXXXXXXXX`. |
| `consentDefault` | string | `granted` | The consent that the page starts with for the storage of Analytics and of ads, `granted` or `denied`. Another value keeps the page from starting with a sentence that names it. |

## The version of gtag.js

Google serves gtag.js only from `https://www.googletagmanager.com/gtag/js?id=<measurement ID>`, an address without a version, and changes the script there without releases. So the plugin cannot pin it, and it uses the commands of gtag.js that the documentation of Google Analytics 4 describes: `consent`, `config`, `event`, `set` and `get`.

## Setup

1. Create a property in [Google Analytics](https://analytics.google.com) with a web data stream for the site of the app, and copy the measurement ID of the stream into `measurementId`.
2. Where the law asks for consent, start with `consentDefault` set to `denied` and call `setConsent` once the person chose.
3. Check the events in the Realtime report or in the DebugView of the property.

The plugin loads gtag.js while the app starts and does not wait for it. A page that cannot load it, such as one whose browser blocks trackers, starts anyway, logs `The page could not load gtag.js of Google Analytics, so it sends no events.` on the console, and fails every call with the code `unavailable`.

Apps on iOS and Android send their events through the plugin [`firebase-analytics`](../firebase-analytics), which reports to the same Analytics property once the Firebase project links it, so one property shows every platform.

## What each platform answers

| Platform | Where the events go |
| --- | --- |
| Web | The property of `measurementId`. A measurement ID that names no property, such as `G-XXXXXXXXXX`, still sends every request, which Google answers with `204` and drops. |

## Platforms without the plugin

| Platform | Reason |
| --- | --- |
| iOS, iPadOS, Mac Catalyst, tvOS, visionOS, macOS, Android, Windows, Linux | gtag.js runs in browsers alone. Apps send their events through the plugin `firebase-analytics`. |

On these platforms the plugin has no native part, so `analytics.available` is `false` and every call fails with the code `noHandler`.

## Lua API

```lua
local analytics = require('google-analytics')
```

### analytics.available

Whether the native part of the plugin runs on this platform, `true` on the web. Without it every call fails with the code `noHandler`.

### analytics.logEvent(name, params)

Sends an event with an optional table of parameters, and returns a platform call whose `await` gives `nil` once gtag.js took it. Use the [recommended events](https://support.google.com/analytics/answer/9267735) of Google Analytics where they fit. A name that is not a string with at least one character raises `The name of an event of Google Analytics is a string with at least one character, such as "level_up".`, and parameters that are not a table raise `The parameters of an event of Google Analytics are a table, such as {level = 3}.`.

```lua
local analytics = require('google-analytics')

analytics.logEvent('level_up', {level = 3})
```

### analytics.setUserId(id)

Names the user of the events that follow with a string, or clears the name with `nil`. Another value raises `The user ID of Google Analytics is a string, or nil to clear it.`.

### analytics.setUserProperties(properties)

Sets user properties from a table of texts and numbers, which the events that follow carry. Another value raises `The user properties of Google Analytics are a table of texts and numbers, such as {plan = "free"}.`.

```lua
local analytics = require('google-analytics')

analytics.setUserId('player-1')
analytics.setUserProperties({plan = 'free'})
analytics.logEvent('select_content', {content_type = 'chapter', content_id = 'two'})
```

### analytics.setConsent(consent)

Updates the consent of the person, a table whose keys `analyticsStorage`, `adStorage`, `adUserData` and `adPersonalization` take `'granted'` or `'denied'`. A key or a value outside these fails the call with the code `invalidParams`, and a value that is not a table raises `The consent of Google Analytics is a table, such as {analyticsStorage = "granted"}.`.

```lua
local analytics = require('google-analytics')

analytics.setConsent({analyticsStorage = 'granted', adStorage = 'denied', adUserData = 'denied', adPersonalization = 'denied'})
```

### analytics.clientId()

Returns a platform call whose `await` gives `{id}`, the client ID that Google Analytics gave the browser.

```lua
local async = require('async')
local analytics = require('google-analytics')

async.spawn(function()
    local client, err = analytics.clientId():await()
    print(client and client.id or err.message)
end)
```

Every call fails with the code `unavailable` when the page could not load gtag.js.

## Native API

| Method | Params | Answer |
| --- | --- | --- |
| `google-analytics.logEvent` | `{name, params}` | `null` |
| `google-analytics.setUserId` | `{id}` | `null` |
| `google-analytics.setUserProperties` | The properties | `null` |
| `google-analytics.setConsent` | `{analyticsStorage, adStorage, adUserData, adPersonalization}` | `null` |
| `google-analytics.clientId` | | `{id}` |

## Sample

The app in `sample/` references the plugin with `"path": ".."`, with the measurement ID `G-XXXXXXXXXX`, and has a button for each call, with the answers on screen and the requests in the network panel of the browser:

```sh
haylen app run sample --target web
```

## License

MIT, like Haylen.
