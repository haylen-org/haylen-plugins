# 🎵 Media Session

The Media Session plugin for [Haylen](https://github.com/haylen-org/haylen) apps shows what the app plays in the now-playing controls of the system, such as the lock screen and the control center of iPhones, the media notification of Android, the media controls of Windows and the media hub of browsers. From then on the media keys of keyboards, the buttons of headsets and the play and pause buttons of TV remotes reach the app as commands. An app that shows what it plays also keeps playing in the background, as [playing in the background](#playing-in-the-background) describes. Its Lua API is the same on every platform.

| Platform | Native part | Controls | Media keys and buttons |
| --- | --- | --- | --- |
| iOS and iPadOS | `apple/MediaSessionPlugin.swift` | The lock screen, the control center and the Dynamic Island, through the info center and the remote commands of MediaPlayer. | Headsets, CarPlay and the other accessories. |
| tvOS | `apple/MediaSessionPlugin.swift` | The now-playing screen of the Apple TV. | The play and pause button of the Siri Remote and of other remotes. |
| visionOS | `apple/MediaSessionPlugin.swift` | The now-playing controls of Apple Vision Pro. | Headsets and the other accessories. |
| macOS and Mac Catalyst | `apple/MediaSessionPlugin.swift` in the app | The now-playing item of the control center and of the menu bar, with the playback state that the media keys follow. | The media keys of the keyboard and the buttons of headsets. |
| Android | The library module in `android/` | The media notification of the shade and the lock screen, of a media session. Android 13 and later draw the controls from the commands. | Headsets, Bluetooth devices and the media buttons of TV remotes. The button that toggles reaches the app as `'togglePlayPause'`. |
| Web | `web/media-session.js` | The media hub of the browser and the lock screen of phones, through the Media Session API. The browser shows them only while the page plays sound. | The media keys of the keyboard and of headsets. A browser that lacks an action leaves it out. |
| Windows | The C++ library of `native/` | The media flyout of the volume and of the lock screen, through the system media transport controls of the window of the app. | The media keys of the keyboard and of headsets. |

On Linux and in the desktop player of macOS the plugin has no native part, as [platforms without controls](#platforms-without-controls) explains.

## Installation

```sh
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path media-session --reference --app my-app
```

The command lists the plugin in the `plugins` section of the `haylen.json` of the app as a reference to its folder in the repository of the Haylen plugins:

```json
{
    "plugins": {
        "media-session": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "media-session"
        }
    }
}
```

Without `--reference`, the command copies the plugin into `plugins/media-session/` of the app instead. To stay on one version of the plugin, the app names a commit in `ref` instead of the branch `main`.

## Parameters

| Parameter | Platforms | Default | Meaning |
| --- | --- | --- | --- |
| `channelName` | Android | `'Playback'` | The name of the notification channel of the media notification, which the person sees in the settings of the app. |

## Setup

- **Apple platforms.** The plugin links `MediaPlayer.framework`, and adds the mode `audio` to `UIBackgroundModes` of the `Info.plist` on iOS, tvOS and visionOS. The lock screen of an iPhone shows an app whose audio session plays, so an app that shows what it plays sets `audio.iosSession` of its `haylen.json` to `playback`, the only category that iOS and tvOS play in the background.
- **Android.** The manifest of the module declares the foreground service `com.haylen.plugins.mediasession.MediaSessionService` of the type `mediaPlayback` with the permissions `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, which Android grants at install. The media notification needs no `POST_NOTIFICATIONS`, since Android exempts the notifications of a media session from it. Google Play asks apps with a foreground service to declare its type in the Play Console.
- **Web.** Nothing. A browser without the Media Session API shows no controls, and the calls change nothing there.
- **Windows.** The tooling builds the C++ library of `native/` with CMake against the desktop SDK of the engine, links `runtimeobject` and places the library next to the app, and the Lua API loads it. The controls belong to the window of the app.

```json
{
    "audio": {"iosSession": "playback"},
    "plugins": {
        "media-session": {"git": "https://github.com/haylen-org/haylen-plugins", "ref": "main", "path": "media-session"}
    }
}
```

## Playing in the background

An app that shows what it plays in the controls of the system is a player, such as a music player, a radio, a podcast app or a meditation app, which keeps playing when the person leaves it. The plugin declares that to each system, and the engine keeps the audio output of the app running in the background exactly when the app declares it:

| Platform | What the plugin declares | What happens |
| --- | --- | --- |
| iOS, iPadOS, tvOS and visionOS | The mode `audio` of `UIBackgroundModes` in the `Info.plist`. | While the `playback` session plays, UIKit lets the app run, and the engine keeps its output running. Once the sound stops, UIKit suspends the app, and the controls of the lock screen wake it again. |
| Mac Catalyst and macOS | Nothing. | A Mac app keeps running in the background and plays on. |
| Android | The foreground service of the type `mediaPlayback` in the manifest of the module. | While the app shows what it plays as playing, the service keeps the app in the foreground with the media notification, so Android neither freezes nor ends it, and the app keeps the audio focus. When the app pauses, the service stops and the notification stays in the shade. Android lets an app start the service only while it is in the foreground or right after a command of its media session, and a refusal logs a warning. |
| Web | Nothing. | A hidden page keeps running the frames of the app from timers, which browsers do not slow down while the page plays sound. |
| Windows | Nothing. | A desktop app keeps running in the background and plays on. |

The rest of the app follows the lifecycle options of its `haylen.json`. With `lifecycle.pauseOnBackground` left at `true`, scenes, timers and tweens stand still while the sound plays on, and the app still hears the commands of the controls. A player that moves to the next track in the background sets `pauseOnBackground` to `false`, so its timers and the end of each track keep running there.

## Lua API

```lua
local mediaSession = require('media-session')
```

### mediaSession.setNowPlaying(info)

Shows what the app plays in the now-playing controls of the system. From then on the commands of the controls, the media keys and the buttons of headsets and remotes reach the listeners of [`mediaSession.on('command')`](#mediasessiononevent-listener-options).

A second call replaces what showed. So an app calls it again when the track, the position or the playing state changes. While it plays, the controls move the position on by themselves. Every app that starts takes what an earlier app of the process showed out of the controls. The table `info` takes these keys:

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `title`, `artist`, `album` | string | `''` | The texts that the controls show. |
| `duration` | number | `0` | The length in seconds. The value `0` is a length that is not known, such as a live stream, which shows no position. |
| `position` | number | `0` | Where the playback is, in seconds. |
| `playing` | boolean | `false` | Whether it plays, which the play and pause control shows. |
| `artwork` | string | none | The bytes of a PNG or JPEG image, such as what `assets.bytes` returns, which cross to the native part as a byte buffer. Bytes that are no image show no artwork. |
| `commands` | list of strings | every command | The controls to offer: `'play'`, `'pause'`, `'togglePlayPause'`, `'stop'`, `'next'`, `'previous'` and `'seek'`. |

The function returns nothing, so an app calls it as often as it needs. These are its errors:

- A value that is not a table raises `The function "mediaSession.setNowPlaying" takes a table of what plays, not a <type>.`.
- An unknown key raises `Unknown option "<key>".`.
- A text, number or boolean key of another type raises `The option "<key>" of "setNowPlaying" is invalid: <type> expected, got <type>.`.
- A negative duration or position raises `The duration and the position of what plays cannot be negative.`.
- An artwork that is not a string raises `The option "artwork" must be the bytes of a PNG or JPEG image.`.
- A `commands` value that is not a table raises `The option "commands" must be a list of command names.`.
- An unknown command raises `The option "commands" names "<name>", which is not "play", "pause", "togglePlayPause", "stop", "next", "previous" or "seek".`.

```lua
local assets = require('haylen.assets')
local audio = require('haylen.audio')
local mediaSession = require('media-session')

local track = {title = 'Harbor at dawn', artist = 'The island band', album = 'Tides', duration = 184}
local voice = audio.playMusic(assets.load('music/harbor.ogg', 'sound', {stream = true}))
local function show(playing)
    mediaSession.setNowPlaying({title = track.title, artist = track.artist, album = track.album, duration = track.duration, position = audio.cursor(voice), playing = playing, artwork = assets.bytes('music/tides.png'), commands = {'play', 'pause', 'togglePlayPause', 'seek'}})
end
show(true)

mediaSession.on('command', function(event)
    if event.command == 'pause' or (event.command == 'togglePlayPause' and not audio.paused(voice)) then
        audio.pause(voice)
        show(false)
    elseif event.command == 'play' or event.command == 'togglePlayPause' then
        audio.resume(voice)
        show(true)
    elseif event.command == 'seek' then
        audio.setCursor(voice, event.position)
        show(not audio.paused(voice))
    end
end)
```

### mediaSession.clear()

Takes the app out of the now-playing controls of the system, which then send no more commands.

```lua
local mediaSession = require('media-session')

mediaSession.setNowPlaying({title = 'Menu theme', playing = true})
mediaSession.clear()
```

### mediaSession.nowPlaying()

Returns a platform call of `haylen.platform`, whose `await` gives what the controls of the system show, read back from the system, as `{title, artist, album, duration, playing, artwork}`, where `artwork` is a boolean that tells whether the controls show a picture. It gives `nil` while the controls show nothing of the app. A platform without the native part fails it with the code `noHandler`.

```lua
local async = require('async')
local mediaSession = require('media-session')

async.spawn(function()
    local shown = mediaSession.nowPlaying():await()
    if shown then
        print(string.format('The controls show "%s", %s.', shown.title, shown.playing and 'playing' or 'paused'))
    end
end)
```

### mediaSession.on(event, listener, options)

Calls `listener(payload)` every time the plugin sends the event `event`, and returns the connection of the listener, a [`Connection`](https://github.com/haylen-org/haylen/blob/main/docs/lua-api/signal.md#connection) of `haylen.signal`. The table `options` takes `owner`, such as a scene, and the listener ends with it. The plugin sends one event:

| Event | When | Payload |
| --- | --- | --- |
| `command` | A control of the system, a media key or the button of a headset or a remote asked the app to change what plays. It comes only once the app showed what plays with `mediaSession.setNowPlaying`. | `{command}`, one of the names of `commands`, with `position` in seconds for `'seek'`. |

Another event name raises `The plugin "media-session" sends the event "command" alone, not "<name>".`.

```lua
local mediaSession = require('media-session')
local scene = require('haylen.scene')

scene.push({
    enter = function(self)
        mediaSession.on('command', function(event)
            print('The controls sent ' .. event.command .. '.')
        end, {owner = self})
    end,
})
```

## What each platform answers

| Platform | Commands | Notes |
| --- | --- | --- |
| iOS, iPadOS, tvOS and visionOS | Each command that the app offers turns on its remote command of MediaPlayer, and the other ones turn off. A seek carries the position that the person picked. | The lock screen shows the controls only while the `playback` session plays. |
| macOS and Mac Catalyst | As on iOS, with the playback state of the info center, which the media keys and the menu bar follow. | |
| Android | Each command is an action of the playback state of the media session. A headset button that toggles reaches the app as `'togglePlayPause'`. | The notification opens the app when tapped. Android before 13 shows the texts and the artwork without buttons. |
| Web | Each command is an action of the Media Session API. The play and pause actions send `'togglePlayPause'` to an app that offers only the toggle, since browsers have no toggle action. | The browser shows the controls only while the page plays sound. |
| Windows | The play, pause, stop, next and previous buttons of the controls, and the seeks of their timeline for a known duration. The play and pause buttons send `'togglePlayPause'` to an app that offers only the toggle. | A system without the transport controls leaves the app out of them. |

## Platforms without controls

| Platform | Why |
| --- | --- |
| Linux | Linux desktops show the players that serve the MPRIS interface on the session bus, which the plugin does not serve. So `setNowPlaying` and `clear` change nothing there, and `nowPlaying` fails with the code `noHandler`. |
| macOS in the desktop player | The player of `haylen app run` loads the native libraries of plugins alone, and this plugin has none for macOS. The macOS app, `haylen app run --target macos`, runs the Apple part. |

## Sample

The app in `sample/` references the plugin with `"path": ".."`. It plays a loop of the sample, shows it in the controls with the artwork of the sample and logs every command, with buttons that pause it, read back the controls, leave them and show the loop again. Its UI tests in `sample/ui-tests/` check on iOS that what the sample shows reaches the info center of MediaPlayer, and on Android that the media notification shows and its pause button reaches the app.

```sh
haylen app run sample --target macos
haylen app run sample --target ios-simulator
haylen app run sample --target android
haylen app run sample --target web
haylen test --ui sample --target ios-simulator
haylen test --ui sample --target android
```

## Native API

| Method | Params | Answer |
| --- | --- | --- |
| `media-session.setNowPlaying` | `{title, artist, album, duration, position, playing, artwork, commands}`, with the artwork as a byte buffer and `commands` as an object whose keys are the names of the commands | `null` |
| `media-session.clear` | `{}` | `null` |
| `media-session.nowPlaying` | `{}` | `{title, artist, album, duration, playing, artwork}` or `null` |

| Event | Payload |
| --- | --- |
| `media-session.command` | `{command}`, with `position` for `'seek'` |

## License

MIT, like Haylen.
