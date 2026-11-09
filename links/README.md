# 🔗 Links

The Links plugin for [Haylen](https://github.com/haylen-org/haylen) apps opens a url with the app that the system picks for it: the browser for a web page, the store for a store link or the mail app for a `mailto:` link. Its Lua API is the same on every platform, and each platform answers whether an app took the url. The links that open the app itself are not part of this plugin, since the engine publishes them on every platform as the event `linkOpened`.

| Platform | Native part | How it opens a url |
| --- | --- | --- |
| iOS, iPadOS, Mac Catalyst, tvOS and visionOS | `apple/LinksPlugin.swift` | The `open` of `UIApplication`, which answers once the app that takes the url is known. |
| macOS | `apple/LinksPlugin.swift` in the macOS app, and the C++ library of `native/` in the desktop player | The `open` of `NSWorkspace`. |
| Android | The library module in `android/` | A view intent, which the activity starts. |
| Web | `web/links.js` | A new tab, which the browser opens only shortly after an input of the person. |
| Windows | The C++ library of `native/` | The `open` verb of the shell. |
| Linux | The C++ library of `native/` | The command `xdg-open` of the desktop, which a thread of the library waits for. |

## Installation

```sh
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path links --reference --app my-app
```

The command lists the plugin in the `plugins` section of the `haylen.json` of the app as a reference to its folder in the repository of the Haylen plugins:

```json
{
    "plugins": {
        "links": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "links"
        }
    }
}
```

Without `--reference`, the command copies the plugin into `plugins/links/` of the app instead. To stay on one version of the plugin, the app names a commit in `ref` instead of the branch `main`.

## Parameters

The plugin has no parameters.

## Setup

The plugin needs nothing on any platform. On the desktop player, Windows and Linux the tooling builds the C++ library of `native/` with CMake against the desktop SDK of the engine and places it next to the app, and the Lua API loads it.

## Lua API

```lua
local links = require('links')
```

### links.open(url)

Opens `url` with the app that the system picks for it. It returns a platform call of `haylen.platform`, whose `await` gives `true` once an app took the url, or `nil` and an error. A url that is not a string raises `A url is a string, not a <type>.`, and an empty url raises `Opening a url needs a url.`.

| Code of the error | When |
| --- | --- |
| `unsupported` | No app on the device opens the url, such as an unknown scheme, with the message `No app on this device opens "<url>".`. A text that is not a url, the command `xdg-open` missing on Linux and an Android app without an activity fail with this code too, each with its reason. |
| `denied` | The browser blocked the new tab, because it opens one only shortly after an input of the person, such as a click or a key. |

A refusal often comes from a button that nothing awaits, so the plugin logs each reason once as a warning, and a refusal that nothing awaits never stops the app.

```lua
local async = require('async')
local links = require('links')

async.spawn(function()
    local opened, err = links.open('https://example.com'):await()
    if not opened then
        print('The page did not open: ' .. err.message)
    end
end)
```

## What each platform answers

| Platform | Answer |
| --- | --- |
| iOS, iPadOS, Mac Catalyst, tvOS and visionOS | `true` once an app took the url, or `unsupported` when none opens it. An Apple TV opens only the urls of the apps it has, so a web page fails there. |
| macOS | `true` once the workspace handed the url to an app, or `unsupported` when none opens it. |
| Android | `true` once an activity took the intent, or `unsupported` when none takes it or Android refuses it, such as a file url that would leave the app. |
| Web | `true` once the tab opened, or `denied` when the browser blocked it. A page cannot tell whether an app takes another scheme, such as `mailto:`, so the browser answers it like a tab. |
| Windows | `true` once the shell found the app of the scheme, or `unsupported` when none is associated with it. |
| Linux | `true` once `xdg-open` ended with success, or `unsupported` when it failed or the desktop lacks it. |

## Sample

The app in `sample/` references the plugin with `"path": ".."` and has a button for each kind of url, with the answer of every call:

```sh
haylen app run sample
haylen app run sample --target ios-simulator
haylen app run sample --target android
haylen app run sample --target web
```

## Platforms without the plugin

None. The plugin runs on every platform of Haylen.

## Native API

| Method | Params | Answer |
| --- | --- | --- |
| `links.open` | `{url}` | `true` |

The C++ library of `native/` fails a call without a `url` string in its parameters with the code `invalidUrl`. The Lua API always sends one.

## License

MIT, like Haylen.
