# 📤 Share

The Share plugin gives [Haylen](https://github.com/haylen-org/haylen) apps the share sheet of the system: the app hands it a text, a url and files, the person picks where they go, such as a message, a mail, a note or another app, and the app learns whether the person shared or closed the sheet. It uses the APIs of each platform alone and needs no permission.

| Platform | Native part | What it uses |
| --- | --- | --- |
| iOS, iPadOS, Mac Catalyst and visionOS | `apple/SharePlugin.swift` | `UIActivityViewController`, as a popover over the anchor on iPad and on the Mac. |
| The macOS app | `apple/SharePlugin.swift` | `NSSharingServicePicker`. |
| macOS in the desktop player | The C++ library of `native/`, in Objective-C++ | `NSSharingServicePicker`. |
| Android | The library module in `android/` | `ACTION_SEND` and `ACTION_SEND_MULTIPLE` in the chooser of the system, with the files behind a `FileProvider` of the plugin. |
| Windows | The C++ library of `native/` | The share UI of Windows over the window of the app, through `IDataTransferManagerInterop` and the data package of the Windows Runtime, with C++/WinRT. |
| Web | `web/share.js` | The Web Share API, `navigator.share` and `navigator.canShare`. |

## Installation

```sh
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path share --reference --app my-app
```

The command lists the plugin in the `plugins` section of the `haylen.json` of the app as a reference to its folder in the repository of the Haylen plugins, and pins the repository to its current commit in `haylen.lock`:

```json
{
    "plugins": {
        "share": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "share"
        }
    }
}
```

Without `--reference`, the command copies the plugin into `plugins/share/` of the app instead. To stay on one version of the plugin, the app names a commit in `ref` instead of the branch `main`.

## Parameters

The plugin has no parameters.

## Setup

### Apple platforms

The plugin declares `LinkPresentation.framework`, which gives the title of a share to the top of the sheet. Nothing else is needed. The files of a share go into the folder `share` of the temporary folder of the app, which the plugin empties before every share, since the app that the person picks may read them after the sheet closed.

### Android

The plugin declares the provider `com.haylen.plugins.share.ShareFileProvider` with the authority `<applicationId>.share`, which serves only the folder `share` of the cache of the app, where the plugin writes the files of a share. The app that the person picks reads them through the rights of the share alone. The chooser tells the plugin which app the person picked through a broadcast that only the app itself may send.

### Windows

The C++ library of `native/` calls the Windows Runtime through C++/WinRT, whose headers come with the Windows SDK, so the machine that builds the app needs nothing else. The share UI of Windows shows over the window of the app and asks the app for the data once it shows. The files of a share go into the folder `<executable>-share` of the temporary folder of the person, named after the executable of the app, which the plugin empties before every share. Windows refuses a share without a title, so a share without `title` takes the title of the window of the app. Windows places its share UI itself, so the `anchor` of a share changes nothing there.

### Web

The page must be a secure context, served over HTTPS or from `localhost`, in a browser with the Web Share API, such as Safari, Chrome on Android and ChromeOS, and Chrome and Edge on Windows and macOS. The browser shows its sheet only right after a press of the person, so the app shares from the press of a button, and a share that comes later fails with the code `notAllowed`. A page in a frame needs `allow="web-share"` on its frame.

## What each platform answers

| Platform | `shared` | `target` |
| --- | --- | --- |
| iOS, iPadOS, Mac Catalyst, visionOS | Whether the activity that the person picked completed. | The type of the activity, such as `com.apple.UIKit.activity.Mail`. |
| macOS | Whether the person picked a service. | The title of the service, such as `Mail`. |
| Android | Whether the person picked an app. Android tells nothing of what the app did with the share. | The package of the app. |
| Windows | Whether the person shared, which Windows tells once the target took the data. | The name of the app that the person picked, or the AppUserModelID of the target that Windows reports. |
| Web | Whether the person shared. | None. |

## Platforms without the plugin

| Platform | Reason |
| --- | --- |
| tvOS | Apple TV has no share sheet. |
| Linux | Linux desktops have no share sheet, and the portals of the desktop offer no service that shares with other apps. |

On these platforms the plugin has no native part, so `share.available` is `false` and `share.share` fails with the code `noHandler`.

## Lua API

```lua
local share = require('share')
```

### share.available

Whether the native part of the plugin runs on this platform. Without it every call fails with the code `noHandler`.

### share.share(options)

Shows the share sheet of the system, which covers the app while it shows, and returns a platform call whose `await` gives `{shared, target}` once the person shared or closed it, as [what each platform answers](#what-each-platform-answers) describes. The table `options` takes these keys, and a share needs at least a `text`, a `url` or a file:

| Key | Type | Meaning |
| --- | --- | --- |
| `text` | string | A text to share. |
| `url` | string | A url to share, such as `https://example.com`. Android adds it to the text, on its own line. |
| `title` | string | The subject that mail and messages take, which the sheet shows at its top on Apple platforms and in the browser. |
| `files` | list | Files to share, each `{name, type, bytes}`: the name of the file that the person sees, such as `'photo.png'`, its media type, such as `'image/png'`, `'application/octet-stream'` by default, and its contents as a string of bytes. |
| `anchor` | rectangle | The rectangle in design units that the sheet points at on iPad and on the Mac, such as the bounds of the button that shares, which `gui:bounds(id)` gives. The sheet shows over the middle of the window without it. |

The call fails with the code `busy` while a sheet already shows, `noWindow` before the window of the app exists, `invalidUrl` for a url that is not valid, `unsupported` on the web for content that the browser cannot share, such as files of some types, and `notAllowed` on the web for a share that did not come right after a press. Options that are not valid raise an error at once: `The function "share.share" takes a table of options.`, `Unknown option "<key>".`, `A share needs a "text", a "url" or "files".`, `The "text" of a share is a string.`, `The "url" of a share is a string.`, `The "title" of a share is a string.`, `The "files" of a share are a list of files, each {name, type, bytes}.`, `The file <n> of a share is a table {name, type, bytes}.`, `The file <n> of a share needs a "name" with at least one character and no slash, such as "photo.png".`, `The file "<name>" of a share needs its "bytes" as a string.`, `The "type" of the file "<name>" of a share is a media type such as "image/png".`, `The "anchor" of a share is a rectangle with "x", "y", "width" and "height" in design units.` and `The "<key>" of the anchor of a share is a number.`.

```lua
local assets = require('haylen.assets')
local scene = require('haylen.scene')
local share = require('share')
local ui = require('haylen.ui')

scene.push({
    enter = function(self)
        self.gui = ui.mount(ui.button{id = 'share', text = 'Share', onClick = function()
            local call = share.share({
                text = 'I reached level 3.',
                url = 'https://example.com/levels/3',
                files = {{name = 'level.png', type = 'image/png', bytes = assets.bytes('images/level.png')}},
                anchor = self.gui:bounds('share'),
            })
            scene.spawn(self, function()
                local result, err = call:await()
                print(result and (result.shared and 'Shared.' or 'Closed.') or err.message)
            end)
        end}, {owner = self})
    end,
})
```

## Native API

| Method | Params | Answer |
| --- | --- | --- |
| `share.share` | `{text, url, title, files, anchor}`, with each file `{name, type, bytes}` and the anchor `{x, y, width, height}` in fractions of the window from its top left corner | `{shared, target}` |

A file without its name or its bytes fails the call with the code `invalidParams`, which the Lua API never sends. Files that cannot be written fail it with the code `failed`, and with `exception` on Android, and a share UI that Windows does not show fails it with `failed`.

## Sample

The app in `sample/` references the plugin with `"path": ".."` and has a button for each kind of share, with the answers on screen:

```sh
haylen app run sample
haylen app run sample --target ios-simulator
haylen app run sample --target android
haylen app run sample --target web
haylen app run sample --target windows
```

The UI tests in `sample/ui-tests/apple` open the sheet, which is a popover over its button on an iPad, and check the answer of an activity that completes and of a sheet that closes. They run on the iOS simulator, on an iPhone and on an iPad:

```sh
haylen test --ui sample --target ios-simulator
```

## License

MIT, like Haylen.
