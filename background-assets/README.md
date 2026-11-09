# 📦 Background Assets

The Background Assets plugin delivers the named packs of the content of a [Haylen](https://github.com/haylen-org/haylen) app, such as the chapters, the levels or the music of a game, as asset packs that the App Store hosts, which the system downloads with the install or when the app loads one of their assets. The app loads the assets of its packs the way it loads any other asset, so its code never knows that the App Store delivered them. It needs no permission.

| Platform | Native part | What it uses |
| --- | --- | --- |
| iOS, iPadOS, tvOS and visionOS 26 and later | `apple/BackgroundAssetsPlugin.swift` and the downloader extension of `apple-extension/` | Background Assets of the system, with the asset packs that Apple hosts. |

On iOS, tvOS and visionOS before 26 the source of packs answers nothing, so the content server of the app or the next source delivers the packs.

## Installation

Name the packs in the `content` section of `haylen.json`, and list in `prefetchPacks` the ones that the system downloads with the install and every update.

```sh
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path background-assets --reference --app my-game
```

The command lists the plugin in the `plugins` section of the `haylen.json` of the app as a reference to its folder in the repository of the Haylen plugins, and the app adds `prefetchPacks` to its entry:

```json
{
    "content": {
        "delivery": [
            {"match": "chapters/two/**", "pack": "chapter-2"},
            {"match": "music/**", "pack": "intro.music"}
        ]
    },
    "plugins": {
        "background-assets": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "background-assets",
            "parameters": {
                "prefetchPacks": ["intro.music"]
            }
        }
    }
}
```

Without `--reference`, the command copies the plugin into `plugins/background-assets/` of the app instead. A parameter that the entry leaves out takes its default from `plugin.json`, so the app follows the defaults of newer versions of the plugin. To stay on one version of the plugin, the app names a commit in `ref` instead of the branch `main`.

## Parameters

| Parameter | Type | Default | Meaning |
| --- | --- | --- | --- |
| `prefetchPacks` | array | `[]` | The named packs that the system downloads with the install and every update, while the others download when the app loads one of their assets. |

## Setup

The plugin brings everything that Background Assets needs into the Apple project that the tooling generates for the app, which builds Lua and C++ apps alike:

- The downloader extension `Downloads`, an ExtensionKit extension for iOS, tvOS and visionOS 26 that the app embeds, with the bundle identifier of the app followed by `.downloads`.
- The App Group `group.<bundle identifier>` in the entitlements of the app and of the extension.
- The keys `BAAppGroupID`, `BAHasManagedAssetPacks` and `BAUsesAppleHosting` in the `Info.plist` of the app.

Register the App Group for the app in the developer account, and give the extension the same team as the app.

The Release build of `haylen app run my-game --target ios --config Release` or `haylen app prepare my-game --target ios --config Release`, and the same with `tvos` or `visionos`, packs every named pack into an asset pack of Background Assets with `xcrun ba-package`, in `build/apps/<app>-<hash>/release/apple.asset-packs/<pack>.aar`:

| Pack of `haylen.json` | Download policy |
| --- | --- |
| `chapter-2` | `onDemand`, when the app loads one of its assets. |
| `intro.music` | `prefetch`, with the install and every update. |

Upload the archives to App Store Connect with the build of the app, such as with Transporter. A Debug build reads every pack from the folder of the app.

Add the source of packs once, such as in `source/main.lua`:

```lua
require('background-assets').addSource()
```

## Testing with the mock server

The mock server of Xcode serves the archives to a simulator as the App Store would:

1. Make a TLS identity for the address of the server, such as `127.0.0.1`, with the address in its subject alternative name, and keep it in a keychain of the Mac that does not lock itself, since the server cannot ask for its password. The simulator trusts its certificate once `xcrun simctl keychain <device> add-root-cert cert.pem` adds it.
2. Serve the archives, with a version above the one the device holds:

```sh
xcrun ba-serve serve build/apps/<app>-<hash>/release/apple.asset-packs/*.aar --asset-pack-versions 1 1 --host 127.0.0.1 --port 63985 --choose-identity-automatically
```

3. Point the simulator at the server. It reads the override from the defaults domain `com.apple.backgroundassets.managed`, so run `xcrun ba-serve url-override https://127.0.0.1:63985` on the Mac, copy its `MBAURLOverride` value into the simulator with `xcrun simctl spawn <device> defaults write com.apple.backgroundassets.managed MBAURLOverride -data <hex>`, and clear it on the Mac again with `xcrun ba-serve url-override --clear`.
4. Run the Release build of the app on the simulator, which downloads its packs from the server. An app with two named packs, one in `prefetchPacks` and one on demand, which adds the source of packs and loads an asset of each, checks both policies, and `state` then answers `'available'` for both:

```sh
haylen app run my-game --target ios-simulator --config Release
haylen app run my-game --target tvos-simulator --config Release
haylen app run my-game --target visionos-simulator --config Release
```

The Release build of `haylen app run my-game --target visionos-simulator --config Release` stops today at the link of the architecture x86_64, since the Release configuration of the Apple project builds every architecture of the visionOS simulator while the simulator slice of `Haylen.xcframework` holds arm64 alone. The delivery of both packs was checked on the visionOS simulator with an arm64 build of the same generated project, until Haylen builds the visionOS simulator for arm64 alone.

The system keeps a downloaded pack by its version, so serve every new build of the packs with a higher version. A Release build whose release changed packs other archives, so restart the server with the archives of the build that runs.

## What each platform answers

| Platform | `addSource` | `state` |
| --- | --- | --- |
| iOS, iPadOS, tvOS and visionOS 26.4 and later | Makes the latest version of the asset pack available, so a pack of an earlier build of the app never stays. | `'available'` or `'notDownloaded'`. |
| iOS, iPadOS, tvOS and visionOS 26 to 26.3 | Makes the asset pack available in the version that the device holds or the App Store gives. | `'unavailable'`, since these systems do not tell it. |
| iOS, tvOS and visionOS before 26 | Passes every pack on to the next source. | `'unavailable'`. |

## Platforms without the plugin

| Platform | Reason |
| --- | --- |
| macOS | Background Assets offers the same asset packs on macOS 26, but the plugin does not declare it yet: the downloader extension and the App Group of a Mac app need a signing identity with a provisioning profile of the team, and a check of the mock server would register the extension with the system of the Mac, so the macOS app is not verified. |
| Mac Catalyst | The Apple project of Haylen leaves app extensions out of Mac Catalyst apps, so the downloader extension that Background Assets runs is missing there. |
| Android, the web, Windows and Linux | The App Store does not deliver to them. Android takes its packs from the plugin `play-asset-delivery`, and the other platforms from the content server of the app. |

On these platforms the plugin has no native part, so `backgroundAssets.available` is `false`, the source of packs answers nothing, and `state` fails with the code `noHandler`.

## Lua API

```lua
local backgroundAssets = require('background-assets')
```

### backgroundAssets.available

Whether the native part runs on this platform: `true` on iOS, tvOS and visionOS.

### backgroundAssets.addSource(options)

Adds a source of packs with `content.addPackSource` and returns its connection. When the app loads an asset of a pack that the device lacks, with `assets.loadAsync`, a preload or `content.prefetch`, the source makes the asset pack of the App Store available on the device, reports its progress to the load, and answers with the folder of the pack. A pack that the App Store does not give the app, such as one it does not host or one of an app installed another way, a pack it cannot reach while the device is offline, and every pack on systems before 26, passes on to the next source or to the content server. A download that fails fails the load, as every failed source of packs does, with the code `storeAssetUnavailable` of [`haylen.content`](https://github.com/haylen-org/haylen/blob/main/docs/lua-api/content.md) and a message with the reason of the system. The options take `owner`, whose end removes the source, and another option raises `Unknown option "<key>".`.

```lua
local assets = require('haylen.assets')
local async = require('async')
local backgroundAssets = require('background-assets')

backgroundAssets.addSource()

async.spawn(function()
    local story, err = assets.loadAsync('chapters/two/story.json'):await()
    print(story and story.title or err)
end)
```

### backgroundAssets.state(pack)

Returns a platform call whose `await` gives `{pack, status}` for a named pack, as [what each platform answers](#what-each-platform-answers) lists. A name that is not a string with at least one character raises `The name of a pack is a string with at least one character, such as "chapter-2".`.

```lua
local async = require('async')
local backgroundAssets = require('background-assets')

async.spawn(function()
    local state = backgroundAssets.state('intro.music'):await()
    print(state and state.status)
end)
```

## Native API

| Method or event | Params or payload | Answer |
| --- | --- | --- |
| `background-assets.fetch` | `{pack}` | `{folder}`, with no `folder` when the App Store does not host the pack, or the failure `downloadFailed` |
| `background-assets.state` | `{pack}` | `{pack, status}` |
| `background-assets.progress` (event) | `{pack, receivedBytes, totalBytes}` | |

## License

MIT, like Haylen.
