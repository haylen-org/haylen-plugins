# 📦 Play Asset Delivery

The Play Asset Delivery plugin delivers the named packs of the content of a [Haylen](https://github.com/haylen-org/haylen) app, such as the chapters, the levels or the music of a game, as asset packs of Google Play, which Play downloads right after the install or when the app loads one of their assets. The app loads the assets of its packs the way it loads any other asset, so its code never knows that Play delivered them. It needs no permission.

| Platform | Native part | What it uses |
| --- | --- | --- |
| Android | The library module in `android/` | Play Asset Delivery 2.3.0 of Google Play, `com.google.android.play:asset-delivery`. |

## Installation

Name the packs in the `content` section of `haylen.json`, and list in `fastFollowPacks` the ones that Google Play downloads right after the install.

```sh
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path play-asset-delivery --reference --app my-game
```

The command lists the plugin in the `plugins` section of the `haylen.json` of the app as a reference to its folder in the repository of the Haylen plugins, and the app adds `fastFollowPacks` to its entry:

```json
{
    "content": {
        "delivery": [
            {"match": "chapters/two/**", "pack": "chapter-2"},
            {"match": "music/**", "pack": "intro.music"}
        ]
    },
    "plugins": {
        "play-asset-delivery": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "play-asset-delivery",
            "parameters": {
                "fastFollowPacks": ["intro.music"]
            }
        }
    }
}
```

Without `--reference`, the command copies the plugin into `plugins/play-asset-delivery/` of the app instead. A parameter that the entry leaves out takes its default from `plugin.json`, so the app follows the defaults of newer versions of the plugin. To stay on one version of the plugin, the app names a commit in `ref` instead of the branch `main`.

## Parameters

| Parameter | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fastFollowPacks` | array | `[]` | The named packs that Google Play downloads right after the install, while the others download when the app loads one of their assets. |

## Setup

The plugin declares `assetPacks` in the `android` section of its `plugin.json`, so the Android release build of Haylen turns every named pack into an asset pack of Google Play in `haylen/asset-packs/` of the project, without any change to the project:

| Pack of `haylen.json` | Asset pack of Google Play | Delivery |
| --- | --- | --- |
| `chapter-2` | `chapter_2` | `on-demand`, when the app loads one of its assets. |
| `intro.music` | `intro_music` | `fast-follow`, right after the install. |

Play names packs with letters, digits and underscores, so every dash and dot of a pack name becomes an underscore, and a name that starts with a digit takes `pack_` in front. The release build stops on a pack larger than an asset pack of Play holds, on two packs with the same name in Play and on more asset packs than Play takes, as the distribution guide of Haylen describes.

Upload the bundle that `haylen app run my-game --target android --config Release` builds, `app-release.aab` in the build folder of the app, to Google Play. The same command installs the bundle on the device in the local testing mode of Play, so the plugin fetches the packs from the device exactly as Play would deliver them, and a Debug build reads every pack from the folder of the app.

The module depends on `com.google.android.play:asset-delivery` 2.3.0, its latest release, and on `androidx.work:work-runtime` 2.12.0, since the library of Play brings an older WorkManager, whose database the shrinking of a release build removes.

Add the source of packs once, such as in `source/main.lua`:

```lua
require('play-asset-delivery').addSource()
```

## What each platform answers

| Where the app comes from | `addSource` | `state` |
| --- | --- | --- |
| Google Play, or the local testing mode of `haylen app run <app> --target android --config Release` | Fetches the asset pack from Play and answers with the folder where Play placed it. | The status of the pack in Play. |
| Another source, such as an APK that `adb` installed | Play does not deliver to the app, so every pack passes on to the next source or to the content server. | `'unknown'`, or the status that Play reports. |

## Platforms without the plugin

| Platform | Reason |
| --- | --- |
| iOS, iPadOS, Mac Catalyst, tvOS, visionOS, macOS | Google Play does not deliver to them. iOS and tvOS take their packs from the plugin `background-assets`. |
| The web, Windows and Linux | Google Play does not deliver to them, so the content server of the app or the depots of a store deliver their packs. |

On these platforms the plugin has no native part, so `delivery.available` is `false`, the source of packs answers nothing, and `state` fails with the code `noHandler`.

## Lua API

```lua
local delivery = require('play-asset-delivery')
```

### delivery.available

Whether the native part runs on this platform: `true` on Android.

### delivery.addSource(options)

Adds a source of packs with `content.addPackSource` and returns its connection. When the app loads an asset of a pack that the device lacks, with `assets.loadAsync`, a preload or `content.prefetch`, the source fetches the pack from Google Play, reports its progress to the load, and answers with the folder where Play placed it. A pack that Play does not deliver, such as in an app that Play did not install, passes on to the next source or to the content server. The options take `owner`, whose end removes the source, and `confirm`, `true` by default, and another option raises `Unknown option "<key>".`. While Play waits for Wi-Fi or for the person to accept a large download over mobile data, the source shows the confirmation of Google Play and goes on once the person accepts, and without `confirm` it fails instead.

A load that the source cannot serve fails as every failed source of packs does, with the code `storeAssetUnavailable` of [`haylen.content`](https://github.com/haylen-org/haylen/blob/main/docs/lua-api/content.md), and its message names the reason: the person declined the download, the device is offline, the device has no room for the pack, or Play failed with the error code it names.

```lua
local assets = require('haylen.assets')
local async = require('async')
local delivery = require('play-asset-delivery')

delivery.addSource()

async.spawn(function()
    local story, err = assets.loadAsync('chapters/two/story.json'):await()
    print(story and story.title or err)
end)
```

### delivery.state(pack)

Returns a platform call whose `await` gives the state of a named pack on the device, `{pack, status, receivedBytes, totalBytes}`, where `pack` is the name of the asset pack of Play and `status` is `'notInstalled'`, `'pending'`, `'downloading'`, `'transferring'`, `'completed'`, `'failed'`, `'cancelled'`, `'waitingForWifi'`, `'requiresUserConfirmation'` or `'unknown'`. A name that is not a string with at least one character raises `The name of a pack is a string with at least one character, such as "chapter-2".`.

```lua
local async = require('async')
local delivery = require('play-asset-delivery')

async.spawn(function()
    local state = delivery.state('intro.music'):await()
    print(state and state.status)
end)
```

### delivery.packName(pack)

Returns the name of the asset pack of Google Play that holds a named pack, such as `'chapter_2'` for `'chapter-2'`.

## Native API

| Method, screen or event | Params or payload | Answer |
| --- | --- | --- |
| `play-asset-delivery.fetch` | `{pack}`, the name in Play | `{folder}`, with no `folder` when Play does not deliver the pack, `{confirm = true}` while Play waits for the person, or the failures `networkError`, `insufficientStorage`, `cancelled` and `fetchFailed` with `data.errorCode` |
| `play-asset-delivery.state` | `{pack}` | `{pack, status, receivedBytes, totalBytes}` |
| `play-asset-delivery.cancel` | `{pack}` | `null` |
| The screen `play-asset-delivery.confirm` | | `{confirmed}`, or the failure `notRequired` when no pack waits |
| `play-asset-delivery.progress` (event) | `{pack, status, receivedBytes, totalBytes}` | |

## License

MIT, like Haylen.
