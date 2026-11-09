# 🔔 Notifications

The Notifications plugin gives [Haylen](https://github.com/haylen-org/haylen) apps local notifications: the app schedules a notification for a number of seconds from now or for a date, cancels it, lists the notifications that wait and the ones that show, and hears the tap of the person on one of them, also the tap that launched the app. It owns the permission `notifications`, which the app checks and asks for with `notifications.permission()` and `notifications.requestPermission()` of the plugin, which the [Permissions](../permissions) plugin answers. It uses the APIs of each platform alone.

| Platform | Native part | What it uses |
| --- | --- | --- |
| iOS, iPadOS, Mac Catalyst, visionOS and the macOS app | `apple/NotificationsPlugin.swift` | UserNotifications, with the delegate of the notification center in `apple/Notifications.swift`, which the plugin owns and shares with the plugins that depend on it. |
| Android | The library module in `android/` | `AlarmManager` for the notifications that wait, `NotificationManager` with two channels, and `HaylenLinkActivity` of the `haylen-links` library for the taps. |
| Web | `web/notifications.js` | The Notification API. |
| Windows | The C++ library of `native/` | The toasts of `Windows.UI.Notifications` under the AppUserModelID of the Start menu shortcut of the app, with a toast activator of COM for the taps, through C++/WinRT. |
| Linux | The C++ library of `native/` and `source/linux.lua` | The notification server of the desktop, `org.freedesktop.Notifications` on the session bus, through libdbus. |

## Installation

The plugin depends on the [Permissions](../permissions) plugin, which owns the contract of permissions, so the app lists both:

```sh
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path permissions --reference --app my-app
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path notifications --reference --app my-app
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
        "notifications": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "notifications"
        }
    }
}
```

Without `--reference`, each command copies its plugin into `plugins/<id>/` of the app instead. A parameter that the entry leaves out takes its default from `plugin.json`, so the app follows the defaults of newer versions of the plugin. To stay on one version of the plugin, the app names a commit in `ref` instead of the branch `main`.

## Parameters

| Parameter | Platforms | Type | Default | Meaning |
| --- | --- | --- | --- | --- |
| `channelName` | Android | string | `Notifications` | The name of the notification channel with sound, which the person sees in the settings of the app. |
| `silentChannelName` | Android | string | `Silent notifications` | The name of the notification channel without sound, which the notifications with `sound = false` use. |

## Setup

### Apple platforms

The plugin declares `UserNotifications.framework`, which the app then links. As its plugin class loads, while the app launches and before launching ends, the plugin makes its object `Notifications` the delegate of the notification center, so the system hands it the tap that launched the app. Nothing else is needed. The notifications of the plugin show while the app is in front too. Another plugin that posts or receives notifications, such as `firebase-messaging`, never replaces that delegate: it depends on this plugin and receives the events of the center through the [delegate of the notification center](#the-delegate-of-the-notification-center).

### Android

The plugin declares the permission `POST_NOTIFICATIONS`, which Android 13 and later ask the person for, and `RECEIVE_BOOT_COMPLETED`, after which it sets the alarms of the notifications that wait again, since a restart of the device drops every alarm. Each notification waits for an alarm that goes off while the device idles too, at about its time: Android may move it by some minutes while the device sleeps, since the plugin uses no exact alarms, which Android keeps for alarm clocks and calendars. A force stop of the app drops its alarms until the app starts again, and every start of the app sets them again.

The small icon of the notifications is the bell of `res/drawable/notifications_icon.xml`. An app shows its own icon with a drawable of the same name in `app/src/main/res/drawable/` of its Android project, which wins over the one of the plugin. The status bar tints the icon, so it is white with transparency.

### Web

The page must be a secure context, served over HTTPS or from `localhost`. The page of a Haylen app has no service worker, so:

- a notification waits in a timer of the page and shows only while the page stays open, and a hidden tab may show it late, since browsers slow down the timers of hidden pages;
- `delivered` fails with the code `unsupported`, since only a service worker lists the notifications that the browser shows;
- browsers on phones, such as Chrome on Android, show notifications only through a service worker, so there a notification does not show and the console says why.

### Windows

The C++ library of `native/` calls the Windows Runtime through C++/WinRT, whose headers come with the Windows SDK. Windows keeps the toasts that wait while the app is closed, as Apple platforms and Android do. Windows shows the toasts of a desktop app only under the AppUserModelID of a shortcut of the Start menu, and it hands the tap on a toast to the COM class that the shortcut names as its toast activator, which it starts the app for when the app is closed. So the installer of the app creates that shortcut, with the identifier of `haylen.json` as its AppUserModelID, and registers the class as a local server of the executable. The plugin looks for both. Without them every call fails with the code `unsupported` and the sentence that names the shortcut, `notifications.permission()` among them, whose `data.missing` names it, and the log says once what is missing. An app that `haylen app run --target windows` starts has no such shortcut until its installer ran on the computer.

The installer that `haylen app package --target windows --format installer` makes with Inno Setup through CPack gives its shortcuts no AppUserModelID and registers no toast activator, and neither `haylen.json` nor `plugin.json` has a key that adds them. So an app that this installer puts on the computer shows no toasts of the plugin, and the plugin answers `unsupported` with `data.missing` as above. This is a gap of the Windows project that the tooling generates. An installer that shows the toasts holds the shortcuts, the class and the run at the end of the setup, with the name, the executable and the identifier of the app and a class id of its own that never changes, such as one that the command `uuidgen` makes, as in this Inno Setup script:

```ini
[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Icons]
Name: "{autoprograms}\My App"; Filename: "{app}\my-app.exe"; AppUserModelID: "com.example.myapp"; AppUserModelToastActivatorCLSID: "8A3B1C2D-4E5F-4A6B-9C7D-0E1F2A3B4C5D"
Name: "{autodesktop}\My App"; Filename: "{app}\my-app.exe"; AppUserModelID: "com.example.myapp"; Tasks: desktopicon

[Registry]
Root: HKA; Subkey: "Software\Classes\CLSID\{{8A3B1C2D-4E5F-4A6B-9C7D-0E1F2A3B4C5D}\LocalServer32"; ValueType: string; ValueData: """{app}\my-app.exe"""; Flags: uninsdeletekey

[Run]
Filename: "{app}\my-app.exe"; Description: "{cm:LaunchProgram,My App}"; Flags: nowait postinstall skipifsilent
```

Windows keeps no setting of the notifications of an app until the app showed its first toast, so until then `notifications.permission()` answers `unknown`, and a schedule goes on. The person turns the notifications of the app off in the settings of Windows, and then the permission answers `denied`. Windows takes ids of at most 64 characters, and it has no badge on the icon of a desktop app, so `badge` changes nothing there.

### Linux

The C++ library of `native/` links libdbus, whose headers come with the package `libdbus-1-dev` of Debian and Ubuntu, or `dbus-devel` of Fedora, which the machine that builds the app needs. The notification server of the desktop shows each notification at once and keeps none that waits, so the Lua module waits for each notification with the event loop of the app, while the app runs. A notification whose time comes while the app is closed does not show. The server names the app after the desktop entry that the Linux project of Haylen installs under the identifier of the app.

## What each platform answers

| Platform | `notifications.permission()` | `delivered` | The tap that launched the app |
| --- | --- | --- | --- |
| iOS, iPadOS, Mac Catalyst, visionOS, macOS | `prompt` until the person answers, then `granted` or `denied`. A provisional or an ephemeral authorization counts as `granted`. | The notifications in the Notification Center. | Reaches `onOpened`. |
| Android 13 and later | `prompt` until the person answers, then `granted` or `denied`, and `denied` once Android no longer asks. | The notifications that the notification shade shows. | Reaches `onOpened`. |
| Android 12 and earlier | `granted`, or `denied` when the person turned the notifications of the app off in the settings, which no prompt turns on again. | The notifications that the notification shade shows. | Reaches `onOpened`. |
| Web | `prompt` until the person answers, then `granted` or `denied`. | Fails with `unsupported`. | The page shows notifications only while it is open, so a tap reaches the page that runs. |
| Windows | A failure with the code `unsupported`, the sentence that names the shortcut of the installer and `data.missing` without it, `unknown` until the app showed its first toast, then `granted`, or `denied` once the person turned the notifications of the app off. | The toasts of the plugin in the notification center of Windows. | Windows starts the app through its toast activator, and the tap reaches `onOpened`. |
| Linux | `granted` while a notification server runs on the session bus, and a failure with the code `unsupported` and the reason otherwise. | The notifications that the server shows, until the person closes them. | The server reports taps only to the app that runs. |

## Platforms without the plugin

| Platform | Reason |
| --- | --- |
| tvOS | Apple TV shows no notification banners, lists or sounds, only a badge on the icon of the app. |
| macOS in the desktop player | The player of `haylen app run` runs without an app bundle, and the system keeps notifications only for an app with one. The macOS app, `haylen app run --target macos`, runs the Apple part. |

On these platforms the plugin has no native part, so `notifications.available` is `false` and every call fails with the code `noHandler`, `notifications.permission()` and `notifications.requestPermission()` among them.

## Lua API

```lua
local notifications = require('notifications')
```

### notifications.available

Whether the native part of the plugin runs on this platform. Without it every call fails with the code `noHandler`.

### notifications.permission()

Reads the state of the permission `notifications`, which the plugin owns, without asking the person. It returns a call of `haylen.platform` whose `await` gives `'granted'`, `'prompt'`, `'denied'` or `'unknown'`, as [what each platform answers](#what-each-platform-answers) lists. A platform without the capability fails the call with the code `unsupported` and the reason as `message`, with `data.missing` for a requirement that the project lacks, and a platform without the native part fails it with `noHandler`, as every call of the plugin. Like every platform call, a failure that nothing awaits stops the app.

```lua
local async = require('async')
local notifications = require('notifications')

async.spawn(function()
    local state, failure = notifications.permission():await()
    print(state and 'The notifications are ' .. state .. '.' or failure.code .. ': ' .. failure.message)
end)
```

### notifications.requestPermission()

Asks the person for the permission `notifications` with the prompt of the system, only while the state is `'prompt'`, and returns a call of `haylen.platform` whose `await` gives the state that the person left. Any other state answers at once, without a prompt. A platform without the capability fails the call with the code `unsupported` and the reason as `message`, with `data.missing` for a requirement that the project lacks, and a platform without the native part fails it with `noHandler`. Like every platform call, a failure that nothing awaits stops the app.

Every call that posts a notification asks for the permission first where the app does not hold it yet, so an app may ask at a moment that it picks instead. A call that the person refused fails with the code `denied` and the sentence `The person has not allowed notifications. Ask for it with "notifications.requestPermission('notifications')", which shows the prompt of the system while the system still asks, or the person allows it in the settings of the system.`.

```lua
local async = require('async')
local notifications = require('notifications')

async.spawn(function()
    local state, failure = notifications.requestPermission():await()
    if failure and failure.code == 'unsupported' then
        print('This device shows no notifications: ' .. failure.message)
    else
        print(state and 'The notifications are ' .. state .. '.' or failure.message)
    end
end)
```

### notifications.schedule(options)

Schedules a notification and returns a platform call whose `await` gives `{id, date}`, with the Unix time in seconds when the notification shows. A notification with the id of another notification of the app replaces it. The table `options` takes these keys:

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `id` | string | Required | The id of the notification, which `cancel`, the lists and `onOpened` give back. |
| `title` | string | Required | The title of the notification. |
| `body` | string | `''` | The text under the title. |
| `seconds` | number | | The seconds from now after which the notification shows, above `0`. Apple platforms wait at least one second. |
| `date` | number | | The Unix time in seconds when the notification shows, such as `os.time() + 3600`, which must not have passed. A notification takes either `seconds` or `date`. On Apple platforms a date follows a change of the clock or of the time zone. |
| `sound` | boolean | `true` | Whether the notification plays the sound of the system. |
| `badge` | integer | | The number on the icon of the app, `0` to clear it, on Apple platforms and on the launchers of Android that show numbers. |
| `data` | any JSON value | | Data of the app that `onOpened` and the lists give back. |

The call fails with the code `denied` when the person refused the permission, and with `unsupported` where the platform cannot show notifications. Options that are not valid raise an error at once: `The function "notifications.schedule" takes a table of options.`, `Unknown option "<key>".`, `A notification needs an "id" that is a string with at least one character.`, `The notification "<id>" needs a "title" that is a string.`, `The "body" of the notification "<id>" is a string.`, `The "sound" of the notification "<id>" is a boolean.`, `The "badge" of the notification "<id>" is an integer of 0 or more.`, `The notification "<id>" needs either "seconds" or "date".`, `The "seconds" of the notification "<id>" are a number above 0.` and `The "date" of the notification "<id>" is a Unix time in seconds that has not passed yet.`.

```lua
local async = require('async')
local notifications = require('notifications')

async.spawn(function()
    local scheduled, err = notifications.schedule({id = 'energy', title = 'Energy is full', body = 'Come back and play.', seconds = 3600, data = {screen = 'map'}}):await()
    print(scheduled and ('It shows at ' .. os.date('%H:%M', math.floor(scheduled.date)) .. '.') or err.message)
end)
```

### notifications.cancel(id)

Cancels the notification `id`, whether it still waits or already shows. Returns a platform call whose `await` gives `{}`. An id that names no notification changes nothing. An id that is not a string raises `The function "notifications.cancel" takes the id of a notification, a string with at least one character.`.

```lua
require('notifications').cancel('energy')
```

### notifications.cancelAll()

Cancels every notification of the plugin, those that wait and those that show. Notifications that other plugins post stay. Returns a platform call whose `await` gives `{}`.

### notifications.pending()

Returns a platform call whose `await` gives the list of the notifications that wait, in the order of their dates, each `{id, title, body, date, data}` with the Unix time in seconds when it shows.

```lua
local async = require('async')
local notifications = require('notifications')

async.spawn(function()
    for _, notification in ipairs(notifications.pending():await()) do
        print(notification.id .. ' shows at ' .. os.date('%c', math.floor(notification.date)) .. '.')
    end
end)
```

### notifications.delivered()

Returns a platform call whose `await` gives the list of the notifications of the plugin that the system shows, in the order they showed, each `{id, title, body, date, data}` with the Unix time in seconds when it showed. It fails with the code `unsupported` on the web.

### notifications.onOpened(listener, options)

Calls `listener({id, data})` when the person taps a notification of the plugin, and returns the connection of the listener, whose `disconnect()` stops it. The event is retained, so the tap that launched the app reaches the first listener, such as one that `source/main.lua` adds. The table `options` takes the `owner` of the listener, which ends it with its owner.

```lua
local notifications = require('notifications')

notifications.onOpened(function(event)
    print('The person opened ' .. event.id .. '.')
    if event.data and event.data.screen == 'map' then
        print('Show the map.')
    end
end)
```

## Native API

| Method or event | Params or payload | Answer |
| --- | --- | --- |
| `notifications.schedule` | `{id, title, body, seconds or date, sound, badge, data}` | `{id, date}` |
| `notifications.cancel` | `{id}` | `{}` |
| `notifications.cancelAll` | `{}` | `{}` |
| `notifications.pending` | `{}` | `[{id, title, body, date, data}]` |
| `notifications.delivered` | `{}` | `[{id, title, body, date, data}]` |
| `notifications.permission`, `notifications.requestPermission` | `{name}` | The name of the state, or a failure with the code `unsupported`, the reason and `data.missing`, which the Permissions plugin answers on Apple platforms, Android and the web, and the library of `native/` answers on Windows and Linux |
| `notifications.opened` (retained event) | `{id, data}` | |
| `notifications.configure` (Windows) | `{identifier}` | `{}` |
| `notifications.show`, `notifications.showSilent` (Linux) | The title, the body, the name of the app and its identifier as four byte buffers | `{serverId}` |
| `notifications.close` (Linux) | `[serverId]` | `{}` |
| `notifications.activated` (Linux event) | `{serverId}` | |
| `notifications.closed` (Linux event) | `{serverId}` | |

On Windows the C++ library answers the methods of the plugin, once the Lua module sent it `notifications.configure` with the identifier of the app as it loads, and it sends the tap as `notifications.opened`.

On Linux the Lua module answers the methods of the plugin, and the C++ library answers `notifications.show`, `notifications.showSilent`, `notifications.close` and the permission. The library sends `notifications.activated` when the person clicks a notification, which the Lua module turns into `notifications.opened`, and `notifications.closed` when the notification goes away.

### The delegate of the notification center

On Apple platforms the plugin owns the delegate of `UNUserNotificationCenter`, and a plugin that depends on it receives the notifications and the responses of the center through the Swift protocol `NotificationsDelegate` of `apple/NotificationsDelegate.swift`. Both methods are optional, and the delegates hear them on the main thread:

| Method | What the delegate does |
| --- | --- |
| `userNotificationCenter(_:willPresent:withCompletionHandler:)` | Answers once with the presentation options of a notification that arrives while the app is in front. The notification shows with the union of the options of every delegate, so a delegate answers `[]` for a notification that is not its own. |
| `userNotificationCenter(_:didReceive:withCompletionHandler:)` | Handles the response to a notification, such as a tap, and calls the completion handler once. The center hears that the response was handled once every delegate called it. |

The plugin class of the dependent plugin adopts the protocol and registers itself with `Notifications.addDelegate(_:)` in its `load(with:)`, which runs while the app launches, after the plugin `notifications` loaded, so it also receives the response to a notification that launched the app. The delegates hear each event in the order they registered, this plugin first. The plugin lists `notifications` in the `dependencies` of its `plugin.json`, so the app takes both, and its Swift reaches the protocol in the same app target:

```swift
@objc(MessagesPlugin)
final class MessagesPlugin: NSObject, HaylenPlugin, NotificationsDelegate {
    func load(with context: HaylenPluginContext) {
        Notifications.addDelegate(self)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(notification.request.identifier.hasPrefix("messages.") ? [.banner, .sound] : [])
    }
}
```

## Sample

The app in `sample/` references the plugin with `"path": ".."` and has a button for every call, with the answers on screen:

```sh
haylen app run sample --target ios-simulator
haylen app run sample --target android
haylen app run sample --target web
haylen app run sample --target windows
```

The UI tests in `sample/ui-tests` allow the notifications in the prompt or the dialog of the system, schedule one, and tap it while the sample shows, from the home screen and after the sample ended or left the recent apps, so the tap reaches `onOpened` each time, and they check the lists of what waits and what showed. They run on the iOS simulator and the Android emulator, and on devices:

```sh
haylen test --ui sample --target ios-simulator
haylen test --ui sample --target android
```

## License

MIT, like Haylen.
