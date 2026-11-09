# 📨 Firebase Cloud Messaging

The Firebase Cloud Messaging plugin gives [Haylen](https://github.com/haylen-org/haylen) apps push notifications and data messages: the app registers its app instance with Cloud Messaging by its Firebase installation ID, which its server sends messages to, subscribes to topics, hears every message that arrives while it runs and hears the tap on the notification of a message, also the tap that launched it. It receives through the default Firebase app that the plugin [`firebase`](../firebase) configures. The permission `notifications`, which notifications need, belongs to the plugin [`notifications`](../notifications), so the app lists both and asks with `notifications.requestPermission()`.

| Platform | Native part | What it uses |
| --- | --- | --- |
| iOS and iPadOS | `apple/FirebaseMessagingPlugin.swift` | `FirebaseMessaging` of the Firebase Apple SDK, a Swift package at the exact version that `plugin.json` pins, over the push notifications of Apple, with the events of the notification center through the `NotificationsDelegate` of the plugin `notifications`. |
| Android | The library module in `android/` | `firebase-messaging` of the Firebase Android SDK, at the version of the Firebase BoM that `android/build.gradle.kts` pins, and `HaylenLinkActivity` of the `haylen-links` library for the taps. |
| Web | `web/firebase-messaging.js` and `web/firebase-messaging-sw.js` | The Messaging module of the Firebase JavaScript SDK, an ES module from the Firebase CDN at the version in its address, with a service worker of the plugin. |

## Installation

The plugin needs the plugins `firebase` and `notifications`, and `notifications` needs the plugin `permissions`:

```sh
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path firebase --reference --app my-app
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path permissions --reference --app my-app
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path notifications --reference --app my-app
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path firebase-messaging --reference --app my-app
```

The commands list the plugins in the `plugins` section of the `haylen.json` of the app as references to their folders in the repository of the Haylen plugins, with an empty text for each required parameter, which the app fills in with the configuration of its Firebase project and the key of its web push certificate:

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
                    "messagingSenderId": "123456789012"
                }
            }
        },
        "permissions": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "permissions"
        },
        "notifications": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "notifications"
        },
        "firebase-messaging": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "firebase-messaging",
            "parameters": {
                "vapidKey": "BK..."
            }
        }
    }
}
```

Without `--reference`, the commands copy the plugins into `plugins/firebase/`, `plugins/permissions/`, `plugins/notifications/` and `plugins/firebase-messaging/` of the app instead. A parameter that an entry leaves out takes its default from `plugin.json`, so the app follows the defaults of newer versions of the plugins. To stay on one version of the plugins, the app names a commit in `ref` instead of the branch `main`.

## Parameters

| Parameter | Platforms | Type | Default | Meaning |
| --- | --- | --- | --- | --- |
| `apsEnvironment` | iOS | string | `development` | The push environment of Apple, `development` for builds of Xcode and `production` for the App Store and TestFlight, which becomes the entitlement `aps-environment`. |
| `showInForeground` | iOS, Android | boolean | `true` | Whether the notification of a message shows while the app is in front, besides reaching the app as a message. |
| `vapidKey` | Web | string | Required | The public key of the web push certificate of the Firebase project, from the Cloud Messaging settings of the project. |
| `notificationChannel` | Android | string | `default` | The id of the notification channel that the notifications of messages use when the message names none. The plugin creates it with the name `Messages`. |

## The permission

The plugin declares no permission of its own. The plugin `notifications` owns the permission `notifications`, which the app checks and asks for with `notifications.permission()` and `notifications.requestPermission()` of that plugin:

```lua
local async = require('async')
local messaging = require('firebase-messaging')
local notifications = require('notifications')

async.spawn(function()
    local state = notifications.requestPermission():await()
    if state == 'granted' then
        local registration, err = messaging.register():await()
        print(registration and registration.installationId or err.message)
    end
end)
```

On iOS and Android the registration needs no permission, and without it the messages still reach the app while it runs, while their notifications do not show. On the web the registration needs the permission, and the SDK would show the prompt of the browser itself, so `register` fails with the code `denied` while the page does not hold it, and the app asks first.

## Registration

Cloud Messaging registers the app instance by its Firebase installation ID, which the SDK of every platform offers in place of the registration tokens that it deprecates. The plugin turns that registration on, with `FirebaseMessagingInstallationIdEnabled` in the `Info.plist` on iOS and the meta-data `firebase_messaging_installation_id_enabled` in the manifest on Android, so the plugin offers no token. The app sends the installation ID of `register` and `onRegistered` to its server, which sends messages to it through Cloud Messaging. On iOS and Android Firebase registers on its own when the app starts while `setAutoInitEnabled` leaves it on, and every registration reaches `onRegistered`.

The Firebase references of [`FirebaseMessaging` on Android](https://firebase.google.com/docs/reference/android/com/google/firebase/messaging/FirebaseMessaging) and [`Messaging` on Apple platforms](https://firebase.google.com/docs/reference/swift/firebasemessaging/api/reference/Classes/Messaging), and the [web guide of Cloud Messaging](https://firebase.google.com/docs/cloud-messaging/web/get-started#access-registration-token), mark the token APIs deprecated and name `register` and `unregister` in their place.

## Setup

### iOS

1. Create an APNs authentication key in the Apple Developer portal, under Keys, and upload it in the Cloud Messaging settings of the Firebase project.
2. The plugin adds the entitlement `aps-environment` with the value of `apsEnvironment`, and the background mode `remote-notification`, so data messages reach the app in the background too. The app signs with a provisioning profile that has the Push Notifications capability.
3. The plugin `firebase` turns off the swizzling of Firebase. The runtime of Haylen hands the device token of APNs to this plugin, and the plugin `notifications`, which owns the delegate of the notification center, hands it the events of the center, since this plugin registers as a [`NotificationsDelegate`](../notifications/README.md#the-delegate-of-the-notification-center). The plugin passes both on to Firebase.

The plugin registers the app for remote notifications as it launches. It answers the notification center only for the notifications of Firebase, which carry `gcm.message_id`, and leaves every other notification, such as one of the plugin `notifications`, to the plugin that posted it. The plugin `notifications` shows a notification in front with the options of every delegate together, so each plugin shows its own.

Simulators of Apple silicon Macs receive the notifications that the command `xcrun simctl push` hands them, and a device receives the messages of Firebase.

### Android

1. The plugin declares the permission `POST_NOTIFICATIONS` for the notifications that it shows while the app is in front, which the plugin `notifications` asks the person for.
2. Notifications without a channel of their own use the channel of `notificationChannel`, which the plugin creates.
3. A tap on a notification that Firebase shows while the app is in the background starts the app with the message. While the app is in front the plugin shows the notification itself when `showInForeground` is true and the person allows notifications. Messages whose `click_action` is `com.haylen.plugins.firebasemessaging.OPEN` open the app through the link activity of Haylen, like the ones that the plugin shows.

Devices and emulators need the services of Google Play to receive messages.

### Web

1. Generate a key pair for web push in the Cloud Messaging settings of the Firebase project, and give its public key to `vapidKey`.
2. The page is served over HTTPS, or from `localhost`, for the service worker of the plugin, which shows the notifications of messages that arrive while the page is in the background. The site serves it from `plugins/firebase-messaging/`.
3. The web SDK has no topics, so the server of the app subscribes the app instance of the page with the Admin SDK of Firebase.

## What each platform answers

| Call or event | iOS | Android | Web |
| --- | --- | --- | --- |
| `register` | The installation ID, once APNs gave the device its token, or the code `unavailable` with the reason of Firebase. | The installation ID, or the code `unavailable` with the reason of Firebase, such as on a device without the services of Google. | The code `denied` while the page does not hold the permission `notifications`, then the installation ID, or the code `unavailable` with the reason of Firebase. |
| `subscribe`, `unsubscribe` | The topic, or the code `unavailable`. | The topic, or the code `unavailable`. | The code `unsupported`. |
| `setAutoInitEnabled` | `{enabled}` | `{enabled}` | The code `unsupported`, since the web registers only when the app calls `register`. |
| `onMessage` | Messages in front, and data messages in the background. | Every message that the service of the plugin receives while the process runs. | Messages while the page is in front. The service worker shows the others. |
| `onOpened` | Every tap on a notification of a message. | Every tap on a notification of a message. | No tap reaches the app, since the service worker of Firebase opens the page of the message. |
| `onRegistrationFailed` | When APNs refuses the device, such as an app signed without `aps-environment`. | Never. | Never. |

Every call fails with the code `notConfigured` when no default Firebase app runs, as the README of the plugin `firebase` describes. A project that names no real Firebase project starts and answers, while `register`, `unregister`, `subscribe` and `unsubscribe` fail with the code `unavailable`.

## Platforms without the plugin

| Platform | Reason |
| --- | --- |
| Mac Catalyst and the macOS app | `FirebaseMessaging` builds for them, but the plugin is verified only on iOS, so it gives them no native part, and the macOS app delivers the device token of APNs through `NSApplication`, which the Apple part does not serve. A platform becomes `native` in `implementations` once the plugin runs there. |
| tvOS | Apple TV shows no notification banners, lists or sounds, only a badge, so it has no notification that a tap opens. |
| visionOS | The Firebase Apple SDK does not list visionOS among the platforms of its package. |
| Windows, Linux and macOS in the desktop player | Firebase offers no Cloud Messaging SDK for desktop apps. |

On these platforms the plugin has no native part, so `messaging.available` is `false` and every call fails with the code `noHandler`.

## Lua API

```lua
local messaging = require('firebase-messaging')
```

### messaging.available

Whether the native part of the plugin runs on this platform: `true` on iOS, Android and the web.

### messaging.register()

Registers the app instance with Cloud Messaging. The `await` gives `{installationId}`, the Firebase installation ID that the server of the app sends messages to, as [what each platform answers](#what-each-platform-answers) lists.

```lua
local async = require('async')
local messaging = require('firebase-messaging')

async.spawn(function()
    local registration, err = messaging.register():await()
    print(registration and registration.installationId or (err.code .. ': ' .. err.message))
end)
```

### messaging.unregister()

Unregisters the app instance, so the messages to its installation ID no longer arrive, until it registers again, which Firebase does on its own at the next start while `setAutoInitEnabled` leaves it on. The `await` gives `{installationId}`.

```lua
local messaging = require('firebase-messaging')

messaging.setAutoInitEnabled(false)
messaging.unregister()
```

### messaging.subscribe(topic), messaging.unsubscribe(topic)

Subscribe the device to a topic, or unsubscribe it, so a message to the topic reaches every device that subscribed. The `await` gives `{topic}`. A topic that is no string with at least one character raises `The function "messaging.subscribe" takes the name of the topic as a string with at least one character.`.

```lua
local messaging = require('firebase-messaging')

messaging.subscribe('news')
```

### messaging.setAutoInitEnabled(enabled)

Turns on or off the registration that Firebase makes on its own when the app starts, which an app turns off until the person agrees where the law asks for consent. The `await` gives `{enabled}`.

```lua
local messaging = require('firebase-messaging')

messaging.setAutoInitEnabled(false)
```

### messaging.onMessage(listener, options)

Calls `listener({messageId, title, body, data})` for every message that arrives while the app runs, whether it carries a notification or only data, and returns the connection of the listener, whose `disconnect()` stops it. The table `options` takes the `owner` of the listener, which ends it with its owner.

```lua
local messaging = require('firebase-messaging')

messaging.onMessage(function(message)
    print(message.title, message.data.reward)
end)
```

### messaging.onOpened(listener, options)

Calls `listener({messageId, title, body, data})` when the person taps the notification of a message. The event is retained, so the tap that launched the app reaches the first listener, such as one that `source/main.lua` adds.

```lua
local messaging = require('firebase-messaging')

messaging.onOpened(function(message)
    print('The person opened the message ' .. tostring(message.messageId) .. '.')
end)
```

### messaging.onRegistered(listener, options)

Calls `listener({installationId})` whenever Cloud Messaging registers the app instance, after `register` and on its own when the app starts, and the app sends the installation ID to its server. The event is retained, so the registration that came before the app listened reaches the first listener.

```lua
local messaging = require('firebase-messaging')

messaging.onRegistered(function(event)
    print('Send ' .. event.installationId .. ' to the server of the app.')
end)
```

### messaging.onRegistrationFailed(listener, options)

Calls `listener({message})` when Apple refuses to register the device for push, such as an app signed without the entitlement `aps-environment`. The event is retained.

```lua
local messaging = require('firebase-messaging')

messaging.onRegistrationFailed(function(event)
    print(event.message)
end)
```

## Native API

| Method or event | Params or payload | Answer |
| --- | --- | --- |
| `firebase-messaging.register` | `{}` | `{installationId}` |
| `firebase-messaging.unregister` | `{}` | `{installationId}` |
| `firebase-messaging.subscribe`, `firebase-messaging.unsubscribe` | `{topic}` | `{topic}` |
| `firebase-messaging.setAutoInitEnabled` | `{enabled}` | `{enabled}` |
| `firebase-messaging.messageReceived` (event) | `{messageId, title, body, data}` | |
| `firebase-messaging.messageOpened` (retained event) | `{messageId, title, body, data}` | |
| `firebase-messaging.registered` (retained event) | `{installationId}` | |
| `firebase-messaging.registrationFailed` (retained event) | `{message}` | |

## License

MIT, like Haylen.
