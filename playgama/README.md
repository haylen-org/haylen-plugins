# 🎮 Playgama Bridge

The Playgama Bridge plugin gives [Haylen](https://github.com/haylen-org/haylen) web games the many game platforms that [Playgama Bridge](https://playgama.com) reaches with one API: the platform and the player, interstitial, rewarded and banner ads, the storage of the platform and the messages that platforms ask games to send. It needs no permission.

| Platform | Native part | What it uses |
| --- | --- | --- |
| Web | `web/playgama.js` | Playgama Bridge 2.4.1, the script of its npm release, which the plugin loads and initializes before the app starts. |

## Installation

```sh
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path playgama --reference --app my-game
```

The command lists the plugin in the `plugins` section of the `haylen.json` of the app as a reference to its folder in the repository of the Haylen plugins:

```json
{
    "plugins": {
        "playgama": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "playgama"
        }
    }
}
```

Without `--reference`, the command copies the plugin into `plugins/playgama/` of the app instead. A parameter that the entry leaves out takes its default from `plugin.json`, so the app follows the defaults of newer versions of the plugin. To stay on one version of the plugin, the app names a commit in `ref` instead of the branch `main`.

## Parameters

| Parameter | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bridgeUrl` | string | `https://cdn.jsdelivr.net/npm/@playgama/bridge@2.4.1/dist/playgama-bridge.js` | The address of the script of Playgama Bridge. |

## The version of the bridge

The plugin pins Playgama Bridge to its release 2.4.1. Playgama publishes every release as the npm package `@playgama/bridge`, whose file `dist/playgama-bridge.js` holds the bridge with the adapters of every platform, and the default of `bridgeUrl` is the address of that file of the release 2.4.1. The CDN of Playgama, such as `https://bridge.playgama.com/v2/stable/playgama-bridge.js`, serves only the channels of a major version, which change under the app with every release of the bridge, so the plugin does not use it by default.

A site may change `bridgeUrl`:

- To serve the file itself, copy `dist/playgama-bridge.js` of the npm package into the app folder outside `source/` and `content/`, such as into `web/`, name it in the `files` of `platforms.web` of `haylen.json` by its path in the site, such as `{"playgama-bridge.js": "web/playgama-bridge.js"}`, and set `bridgeUrl` to `playgama-bridge.js`. The tooling copies it into the site, next to `index.html`.
- To follow the channel of Playgama, which downloads only the adapter of the platform the game runs on, set `bridgeUrl` to `https://bridge.playgama.com/v2/stable/playgama-bridge.js`.

An app that leaves `bridgeUrl` out takes the default of the version of the plugin it uses, so a newer version of the plugin brings its release of the bridge, while an app that sets `bridgeUrl` stays on the release it names.

## Setup

1. Put `playgama-bridge-config.json` with the settings of the platforms, such as the placements of their ads, which the config editor of Playgama writes, into the app folder outside `source/` and `content/`, such as into `web/`, and name it in the `files` of `platforms.web` of `haylen.json`, such as `{"playgama-bridge-config.json": "web/playgama-bridge-config.json"}`. The tooling copies it into the site, next to `index.html`, where the bridge reads it. Without the file the bridge logs `Failed to load the bridge config file` and runs with its defaults.
2. Build the site of the app with `haylen app prepare my-game --target web --config Release`, which places the plugin in `plugins/playgama/` of the site.
3. Upload the site to the developer portal of Playgama, or of the platform you publish on.

The script of the bridge must load before the app starts. A page that cannot load it, such as one without the network, shows the error of the loading page and does not start, since the app needs the bridge for its ads and its storage.

The interstitial and rewarded ads are screens of the plugin, so the engine covers the app while they show: the game stands still and stays silent until the ad closes. Platforms also pause the game and turn its sound off on their own, which `onPauseChanged` and `onAudioChanged` report.

## What each platform answers

| Where the page runs | What the bridge does |
| --- | --- |
| A game platform of Playgama Bridge | The bridge finds the platform from the page, and its ads, storage and player are those of the platform. |
| Any other site, such as `haylen app run my-game --target web` | The bridge plays the platform `mock`. It supports no interstitial, rewarded or banner ad, so `showInterstitial` and `showRewarded` fail with the code `showFailed` and the banner goes to `'failed'`. It keeps the storage in the local storage of the page, names the player a guest with a random ID and supports no sign-in, so `authorizePlayer` fails with the code `authorizationFailed`. |

## Platforms without the plugin

| Platform | Reason |
| --- | --- |
| iOS, iPadOS, Mac Catalyst, tvOS, visionOS, macOS, Android, Windows, Linux | Playgama Bridge publishes web games on the sites of game platforms, and has no SDK for apps. |

On these platforms the plugin has no native part, so `playgama.available` is `false` and every call fails with the code `noHandler`.

## Lua API

```lua
local playgama = require('playgama')
```

### playgama.available

Whether the native part of the plugin runs on this platform, `true` on the web. Without it every call fails with the code `noHandler`.

### playgama.platform()

Returns a platform call whose `await` gives the platform the game runs on and what it supports:

| Field | Meaning |
| --- | --- |
| `id` | The ID of the platform, such as `'playgama'`, or `'mock'` on other sites. |
| `language` | The language of the player, such as `'en'`. |
| `tld` | The top level domain of the platform, or `nil`. |
| `payload` | The payload of the link that opened the game, or `nil`. |
| `audioEnabled`, `paused` | Whether the platform lets the game play sound, and whether it paused the game, before any change that the events report. |
| `deviceType` | `'desktop'`, `'mobile'`, `'tablet'` or `'tv'`. |
| `interstitialSupported`, `rewardedSupported`, `bannerSupported` | Whether the platform shows each kind of ad. |

### playgama.player(), playgama.authorizePlayer()

The `await` of `player` gives `{authorizationSupported, authorized, guest, id, name, photos}`, where `photos` lists the addresses of the pictures of the player. The call `authorizePlayer` asks the platform to sign the player in and gives the player the same way, or fails with the code `authorizationFailed` when the platform does not sign the player in.

### playgama.sendMessage(name)

Tells the platform about the game, which some platforms require. The `name` is one of `'gameReady'`, once the game can be played, `'gameplayStarted'` and `'gameplayStopped'` around play, `'levelStarted'`, `'levelCompleted'`, `'levelFailed'`, `'levelPaused'`, `'levelResumed'`, `'inGameLoadingStarted'` and `'inGameLoadingStopped'`. The call fails with the code `invalidParams` for another name, and with the code `refused` when the platform refuses the message, such as a second `'gameReady'`.

The bridge shows interstitial ads only after `'gameReady'`, so a game sends it as soon as it can be played.

```lua
local playgama = require('playgama')

playgama.sendMessage('gameReady')
playgama.sendMessage('gameplayStarted')
```

### playgama.showInterstitial(options), playgama.showRewarded(options)

Show an ad. Returns a platform call whose `await` gives `{shown, rewarded}` once the ad closes, where `rewarded` tells whether the player earned the reward of a rewarded ad. The options take `placement`, a placement that the config of the bridge names. The call fails with the code `showFailed` when the platform shows no ad, such as before `'gameReady'`, right after another interstitial or on a platform without ads, with the code `busy` while the platform shows another ad, and with `Unknown option "<key>".` for another option.

```lua
local async = require('async')
local playgama = require('playgama')

async.spawn(function()
    local result, err = playgama.showRewarded({placement = 'extra-life'}):await()
    if result and result.rewarded then
        print('One more life.')
    elseif err then
        print('No ad: ' .. err.message)
    end
end)
```

### playgama.showBanner(options), playgama.hideBanner()

Show and hide the banner of the platform, whose states reach `onBannerChanged`. The options of `showBanner` take `position`, `'bottom'` by default or `'top'`, and `placement`.

### playgama.storageGet(key), playgama.storageSet(key, value), playgama.storageDelete(key)

Read, keep and delete a text under a key, in the storage of the platform, the cloud storage of the player where the platform has one and the local storage of the page otherwise. The `await` of `storageGet` gives `{value}`, with `value` nil for a key without one. The storage keeps texts, so a table goes in as the text of `json.encode`, and an empty text deletes the key. A key that is not a string with at least one character raises `The key of the storage of Playgama is a string with at least one character.`, and a value that is not a string raises `The value of the storage of Playgama is a string, such as the text of "json.encode".`.

```lua
local async = require('async')
local json = require('json')
local playgama = require('playgama')

async.spawn(function()
    playgama.storageSet('progress', json.encode({level = 3})):await()
    local saved = playgama.storageGet('progress'):await()
    print(saved.value and json.decode(saved.value).level)
end)
```

### playgama.onPauseChanged(listener, options), playgama.onAudioChanged(listener, options), playgama.onBannerChanged(listener, options)

Call `listener({paused})` when the platform pauses or resumes the game, `listener({enabled})` when it turns the sound of the game off or on, and `listener({state})` when the banner changes to `'loading'`, `'shown'`, `'hidden'` or `'failed'`. Each returns the connection of the listener, and the options take `owner`, whose end disconnects it.

```lua
local audio = require('haylen.audio')
local playgama = require('playgama')

playgama.onAudioChanged(function(state)
    audio.setBusMuted('master', not state.enabled)
end)
```

## Native API

| Method or event | Params or payload | Answer |
| --- | --- | --- |
| `playgama.platform` | | `{id, language, tld, payload, audioEnabled, paused, deviceType, interstitialSupported, rewardedSupported, bannerSupported}` |
| `playgama.player` | | `{authorizationSupported, authorized, guest, id, name, photos}` |
| `playgama.authorizePlayer` | | The player |
| `playgama.sendMessage` | `{name}` | `null` |
| `playgama.showBanner` | `{position, placement}` | `null` |
| `playgama.hideBanner` | | `null` |
| `playgama.storageGet` | `{key}` | `{value}` |
| `playgama.storageSet` | `{key, value}` | `null` |
| `playgama.storageDelete` | `{key}` | `null` |
| The screens `playgama.interstitial` and `playgama.rewarded` | `{placement}` | `{shown, rewarded}` |
| `playgama.pauseChanged` (event) | `{paused}` | |
| `playgama.audioChanged` (event) | `{enabled}` | |
| `playgama.bannerChanged` (event) | `{state}` | |

## Sample

The app in `sample/` references the plugin with `"path": ".."` and has a button for each call, with the answers and the events on screen:

```sh
haylen app run sample --target web
```

## License

MIT, like Haylen. Playgama Bridge, which the page loads, comes under the GNU Lesser General Public License 3.0 of Playgama.
