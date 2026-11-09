# 💬 Dialogs

A Haylen plugin that shows the native dialogs of the system: messages with up to three buttons, and the pickers of files to open, of a place to save data, of a folder and of photos. They look and behave like the dialogs of every other app of the platform. Use them for desktop tools, editors and settings that import or export files, and for a photo that the person picks. Menus and messages drawn in the style of the app belong to `haylen.ui` instead. The Lua API is the same on every platform, and `docs/platform/plugins.md` of the Haylen repository explains how plugins work.

## Installation

```sh
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path dialogs --reference --app my-app
```

The command lists the plugin in the `plugins` section of the `haylen.json` of the app as a reference to its folder in the repository of the Haylen plugins, and pins the repository to its current commit in `haylen.lock`:

```json
{
    "plugins": {
        "dialogs": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "dialogs"
        }
    }
}
```

Without `--reference`, the command copies the plugin into `plugins/dialogs/` of the app instead. A parameter that the entry leaves out takes its default from `plugin.json`, so the app follows the defaults of newer versions of the plugin. To stay on one version of the plugin, the app names a commit in `ref` instead of the branch `main`.

## Platforms

| Platform | Native part | Setup |
| --- | --- | --- |
| iOS, iPadOS, Mac Catalyst, visionOS | `apple/`, Swift with UIKit and PhotosUI | None. The pickers need no permission and no usage description. |
| tvOS | `apple/`, Swift with UIKit | None. The Apple TV shows messages alone, as [what each platform answers](#what-each-platform-answers) describes. |
| macOS app | `apple/`, Swift with AppKit | None. A sandboxed app reads and writes what the person picks through the entitlement `com.apple.security.files.user-selected.read-write`, which the parameter `macFiles` adds. |
| Android | The library module in `android/`, Kotlin | None. The pickers and the photo picker need no permission. |
| Web | `web/dialogs.js` | None. |
| macOS in the desktop player | `native/`, C++ with Objective-C++ for AppKit | None. The tooling builds it with CMake against the SDK of the engine and places it next to the player, and the Lua API loads it. |
| Windows | `native/`, C++ with the task dialog and the file dialogs of the shell | The application manifest selects version 6 of the Common Controls, as the Windows template of Haylen does. |
| Linux | `native/`, C++ with GTK 3, which the library loads when it runs | The system has GTK 3, which the desktops of Linux bring. The Debian package of an app does not name it, so on a system without it every dialog fails with the code `unsupported`. |

## Parameters

| Parameter | Type | Platforms | Default | Meaning |
| --- | --- | --- | --- | --- |
| `macFiles` | boolean | macOS | `true` | Whether a sandboxed macOS app may read and write the files and folders that the person picks, which the pickers need there. |

## Lua API

```lua
local dialogs = require('dialogs')
```

A dialog never blocks the app. Every function shows its dialog at once and returns a [call](#calls). The choice of the person reaches Lua at the start of a later frame, where `call:await()` inside a coroutine returns it.

- A dialog that the person dismissed or cancelled returns `nil`.
- A dialog that failed returns `nil` and an [error](#errors).
- A platform that has no such dialog fails the call with the code `unsupported`, never with a default choice.

Options are tables whose unknown keys raise `Unknown option "<key>".`. Options of another type than a table raise the error of a bad argument of Lua, such as `bad argument #1 to 'message' (table expected, got nil)`. A string option of another type raises `The option "<key>" of a dialog is a string, not a <type>.`, and a boolean option of another type raises `The option "<key>" of a dialog is a boolean, not a <type>.`. Every function takes a `timeout` of its own.

### dialogs.message(options)

Shows a message with one to three buttons. It returns a call whose `await` gives the button that the person pressed, counted from 1 in the order of `buttons`. It gives `nil` when the person dismissed the message without a button, such as with Escape or the back button.

| Option | Type | Default | Meaning |
| --- | --- | --- | --- |
| `title` | string | `''` | The title of the message. |
| `text` | string | required | The message. |
| `kind` | string | `'info'` | `'info'`, `'warning'` or `'error'`, which picks the icon or the style where the platform has them. |
| `buttons` | table | required | One to three labels of buttons, in the language of the app. |
| `timeout` | number | none | Seconds after which the call fails with the code `timeout`, and the plugin closes the message. |

A missing text raises `A message dialog needs a text.`. An unknown kind raises `The kind "<kind>" of a message dialog is unknown. Use "info", "warning" or "error".`. A list of buttons that is missing, empty or longer than three raises `A message dialog has one to three buttons, not <count>.`, and an empty label raises `Every button of a message dialog needs a label.`.

```lua
local dialogs = require('dialogs')
local scene = require('haylen.scene')

local Editor = {}

function Editor:enter()
    scene.spawn(self, function()
        local button = dialogs.message({title = 'Unsaved map', text = 'Save the changes before leaving?', kind = 'warning', buttons = {'Save', 'Discard', 'Cancel'}}):await()
        if button == 1 then
            print('Saving.')
        elseif button == 2 then
            print('Leaving without saving.')
        end
    end)
end

scene.push(Editor)
```

### dialogs.openFiles(options)

Shows a picker of files to open. It returns a call whose `await` gives a list of the picked files, or `nil` when the person cancelled. Each file is a table with `name` and `path`. The list holds one file, unless `multiple` is `true`. The table `options` is optional.

Every file can be read at its `path` with the `fs` module of Varn. On desktops the path is the file itself. Elsewhere it is a copy that the plugin makes, as [copies of picked files](#copies-of-picked-files) describes.

| Option | Type | Default | Meaning |
| --- | --- | --- | --- |
| `title` | string | `''` | The title of the picker, where the platform shows one. |
| `filters` | table | every file | A list of file types. Each is a table with a `name` and a list of `extensions` without their dot, such as `{name = 'Maps', extensions = {'tmj', 'json'}}`. |
| `multiple` | boolean | `false` | Whether the person may pick several files. |
| `timeout` | number | none | Seconds after which the call fails with the code `timeout`, and the plugin closes the picker where the platform lets it. |

These are the errors of the filters:

- Filters that are not a table, or a filter that is not a table, raise `The filters of a file dialog are a list of tables with a name and a list of extensions.`.
- A filter without a name raises `Every filter of a file dialog needs a name.`.
- A filter without extensions raises `The filter "<name>" needs at least one extension.`.
- An extension that is not a string, is empty, or has a leading dot, a wildcard, a separator or a space raises `The extension "<extension>" of the filter "<name>" is invalid. Extensions come without their dot, such as "png" or "tar.gz".`.

```lua
local async = require('async')
local dialogs = require('dialogs')
local fs = require('fs')

async.spawn(function()
    local files, err = dialogs.openFiles({title = 'Import maps', filters = {{name = 'Tiled maps', extensions = {'tmj', 'json'}}}, multiple = true}):await()
    if err then
        print('No picker here: ' .. err)
        return
    end
    for _, file in ipairs(files or {}) do
        print(file.name .. ' has ' .. #fs.readFile(file.path):await() .. ' bytes.')
    end
end)
```

### dialogs.saveFile(options)

Shows a picker of the place to save a file, and writes `data` there. It returns a call whose `await` gives the saved file, or `nil` when the person cancelled. The saved file is a table with `name` and, where the platform gives one, `path`. Android saves a document, which has no path. The web saves a download, or a file of the file system where the browser lets the page pick one, and neither has a path, since the page never sees one.

| Option | Type | Default | Meaning |
| --- | --- | --- | --- |
| `title` | string | `''` | The title of the picker, where the platform shows one. |
| `name` | string | required | The file name that the picker suggests, without folders. |
| `data` | string | required | The bytes to write, which may be empty. |
| `filters` | table | every file | File types, as `dialogs.openFiles` takes them. |
| `timeout` | number | none | Seconds after which the call fails with the code `timeout`, and the plugin closes the picker where the platform lets it. |

A missing name raises `A save dialog needs the name it suggests for the file.`, and a name with a folder raises `The name "<name>" that a save dialog suggests is a file name, without folders.`. Data that is missing or not a string raises `A save dialog needs the data it writes, as a string.`.

```lua
local async = require('async')
local dialogs = require('dialogs')
local json = require('json')

async.spawn(function()
    local saved = dialogs.saveFile({title = 'Export the save', name = 'island-save.json', data = json.encode({gold = 120, day = 7}), filters = {{name = 'Saves', extensions = {'json'}}}}):await()
    if saved then
        print('Exported to ' .. (saved.path or saved.name) .. '.')
    end
end)
```

### dialogs.openFolder(options)

Shows a picker of a folder. It returns a call whose `await` gives the path of the folder, or `nil` when the person cancelled. The table `options` is optional.

| Option | Type | Default | Meaning |
| --- | --- | --- | --- |
| `title` | string | `''` | The title of the picker, where the platform shows one. |
| `timeout` | number | none | Seconds after which the call fails with the code `timeout`, and the plugin closes the picker. |

```lua
local async = require('async')
local dialogs = require('dialogs')

async.spawn(function()
    local folder, err = dialogs.openFolder({title = 'Export the level to'}):await()
    if err and err.code == 'unsupported' then
        print('This platform picks no folders, so the level goes to the storage of the app.')
    elseif folder then
        print('Exporting to ' .. folder .. '.')
    end
end)
```

### dialogs.openPhotos(options)

Shows the photo picker of the system, which runs outside the app and hands over only the photos that the person picks, so it needs no permission on any platform. It returns a call whose `await` gives a list of the picked photos, or `nil` when the person cancelled. Each photo is a table with `name` and `path`, like the files of `dialogs.openFiles`, and [`graphics.newTexture`](https://github.com/haylen-org/haylen/blob/main/docs/lua-api/graphics.md) loads its bytes. The list holds one photo, unless `multiple` is `true`. The table `options` is optional.

| Option | Type | Default | Meaning |
| --- | --- | --- | --- |
| `title` | string | `''` | The title of the picker, where the platform shows one. |
| `multiple` | boolean | `false` | Whether the person may pick several photos. |
| `timeout` | number | none | Seconds after which the call fails with the code `timeout`, and the plugin closes the picker where the platform lets it. |

```lua
local async = require('async')
local dialogs = require('dialogs')
local fs = require('fs')
local graphics = require('haylen.graphics')

async.spawn(function()
    local photos = dialogs.openPhotos():await()
    if photos then
        local avatar = graphics.newTexture(fs.readFile(photos[1].path):await())
        print('The avatar is ' .. avatar.width .. ' by ' .. avatar.height .. ' pixels.')
    end
end)
```

## Calls

Every function returns a call with `call:await()`, `call:cancel()` and the properties `id`, `done` and `promise`, which work like those of a `PlatformCall` of `haylen.platform`. For a dialog they work like this:

- The method `call:await()` returns the choice of the person, or `nil` and an [error](#errors).
- The method `call:cancel()` closes the dialog where the platform can, and fails the call with the code `cancelled` at the start of the next frame. It never stops the app when nothing awaits the call. It returns `true` when the dialog was still open, and `false` when it had already settled.
- The property `call.done` is whether the call has settled.
- The property `call.id` is the id of the call. It is unique in the process, so an answer that arrives after the app restarted never answers a dialog of the new app.
- The property `call.promise` is a Varn promise of the choice, for the combinators of `async`, which fails with the message of the error.

A timeout that is not a positive number raises `The timeout of a dialog is a positive number of seconds.`. A dialog that is still open when the app stops, such as for a hot reload, closes, and its call never settles.

```lua
local async = require('async')
local dialogs = require('dialogs')

local question = dialogs.message({text = 'Keep the new graphics settings?', buttons = {'Keep', 'Revert'}, timeout = 15})

async.spawn(function()
    local button, err = question:await()
    if button ~= 1 then
        print(err and err.code == 'timeout' and 'No answer, so the settings revert.' or 'The settings revert.')
    end
end)

local function leaveSettings()
    question:cancel()
end
```

## Errors

A failed dialog returns the error of a platform call: a table with `message`, `code` and `data`, which reads as its message in `tostring` and in string concatenation.

| Code | When |
| --- | --- |
| `unsupported` | The platform has no such dialog. The message says why. |
| `cancelled` | The method `call:cancel()` gave the dialog up. |
| `timeout` | The `timeout` of the dialog passed first. |
| `failed` | The platform could not show the dialog, write the file or copy the picked files, or another picker of Android still shows. The message gives the reason. |
| `denied` | The browser refused a picker, because it shows its pickers only right after an input of the person. The message says how to ask again. |
| `noHandler` | The platform runs without the native part of the plugin, such as the headless player of the tests. |

## Copies of picked files

The pickers of phones, tablets and the web hand the app documents and photos that have no path it can read, so the plugin copies each one into a folder of its own and answers with the path of the copy. Each pick copies into a numbered folder, and a second file of the same name goes into a numbered folder inside it.

| Platform | Folder of the copies | Emptied |
| --- | --- | --- |
| iOS, iPadOS, Mac Catalyst, visionOS | `dialogs` in the temporary folder of the app | When the process starts. |
| Android | `dialogs` in the cache folder of the app | When the process starts. |
| Web | `tmp/dialogs` in the storage folder of the app, which `haylen.storage.root()` returns | When the app starts. |

On the web, files that cannot be written into the storage fail the call with the code `failed` and the message `The picked files could not be written for the app: <reason>`.

## What each platform answers

| Platform | Message | Open files | Save file | Open folder | Photos |
| --- | --- | --- | --- | --- | --- |
| macOS | A sheet on the window of the app. | A sheet on the window of the app. | A sheet on the window of the app. | A sheet on the window of the app. | A sheet of image files, which opens in the Pictures folder. |
| iOS, iPadOS, Mac Catalyst and visionOS | An alert. | The document picker, which copies the files. | The document picker, which exports the data. | The document picker, which keeps access to the folder. | The photo picker of PhotosUI, which copies the photos. |
| tvOS | An alert. | `unsupported` | `unsupported` | `unsupported` | `unsupported` |
| Android | An `AlertDialog` of AppCompat. In the order of `buttons`, its buttons are the positive, the negative and the neutral button, so the first one sits on the right. | The document picker of the Storage Access Framework, which copies the files. It shows the types of the filters whose MIME types Android knows, or every file when an extension has none. | The document creator of the system. It never replaces a file, and it adds a number to a name that is taken. Its document has a name but no path. | `unsupported`, because Android folders have no paths. | The photo picker of the system, which copies the photos. |
| Web | A modal dialog over the canvas in the colors of the page. Its first button takes the focus, Tab and the arrows move between the buttons, and Escape dismisses it. | The file picker of the browser, whose files the plugin writes into the storage. | The save picker of the browser where it has one, and a download elsewhere. | `unsupported`, because browsers give pages no paths of folders. | The file picker of the browser for images, which phones fill from their photos and cameras. |
| Windows | A task dialog that the window of the app owns. | The file dialog of the shell. | The file dialog of the shell. | The folder dialog of the shell. | The file dialog of the shell for images, which opens in the Pictures folder. |
| Linux | A GTK 3 message dialog over the window of the app. | The GTK 3 file chooser, which uses the desktop portal where it runs. | The GTK 3 file chooser. | The GTK 3 file chooser. | The GTK 3 file chooser for images, which opens in the Pictures folder. |

These notes describe how each platform behaves:

- **Web.** Browsers open their file pickers only in the moments after a click, a tap or a key press of the person. So a web app asks for files, for photos and for the save picker from an input handler. A call without that activation fails with the code `denied`. A download needs no activation. The plugin closes a message that the app gives up. A picker of the browser stays open, since pages cannot close it, and its answer goes nowhere.
- **Windows.** Windows shows the dialogs one after the other, on a thread of the library. The window of the app keeps drawing but takes no input while one shows, as with every dialog of Windows.
- **Linux.** The library loads GTK 3 with the first dialog. Without GTK 3 every dialog fails with the code `unsupported` and a message that names GTK 3. GTK runs on the frame thread, where the engine dispatches the main context of GLib once per frame.
- **Android messages.** An Android app keeps running while a message shows. So a cancel or a timeout closes the message at once. A message that is still open when its activity goes away closes with it.
- **Android pickers.** The pickers of Android belong to another app, whose activity pauses the app and its frames. So a cancel or a timeout of a picker takes effect once the picker closed. The app cannot close a picker, and one shows at a time, so a second one fails with the code `failed`. Devices without a document picker or a photo picker, as Android TV devices often are, fail the pickers with the code `unsupported`. A picker that answers after its activity or its process ended, which the stable keys of the Activity Result API allow, finds no call waiting, and its answer is logged and dropped.
- **Apple queue.** macOS, iOS, iPadOS, Mac Catalyst, visionOS and tvOS show one dialog at a time, as Windows does. A dialog that the app asks for while another one shows waits until that one answers or the app gives it up, and a dialog that the app gives up while it waits never shows.
- **Apple alerts.** The alerts of iOS, iPadOS, Mac Catalyst, visionOS and tvOS close only through their buttons, so a message there never answers `nil` unless the app gives it up. The alert of macOS takes Return for its first button, and Escape for a button named Cancel.
- **Apple files.** On iOS, iPadOS, Mac Catalyst and visionOS the path of a saved file is the place that the person picked, which the app cannot read later. A picked folder stays readable until the app ends.

## Platforms without the plugin

Every platform of Haylen has the plugin. The Apple TV shows messages alone, since tvOS has no document picker and no photo picker, so its pickers fail with the code `unsupported`.

## Native API

The Lua API checks every option before it calls the native part, which answers these methods on every platform it serves.

| Method | Params | Answer |
| --- | --- | --- |
| `dialogs.message` | `{title, text, kind, buttons}` | The button counted from 1, or `null`. |
| `dialogs.openFiles` | `{title, filters, multiple}`, with `filters` left out for every file | `[{name, path}]`, or `null`. The web answers `[{name, data}]` with the bytes in `data`. |
| `dialogs.saveFile` | `{title, name, filters, data}`, with the bytes in `data` | `{name, path}`, with no `path` where the platform gives none, or `null`. |
| `dialogs.openFolder` | `{title}` | The path, or `null`. |
| `dialogs.openPhotos` | `{title, multiple}` | `[{name, path}]`, or `null`. The web answers `[{name, data}]`. |

The plugin sends no events.

## Sample

The app in `sample/` references the plugin with `"path": ".."` and shows every call with a button and its answer on screen, including a message that the app gives up and one that times out:

```sh
haylen app run sample
haylen app run sample --target ios-simulator
haylen app run sample --target android
haylen app run sample --target web
```

The UI tests in `sample/ui-tests/apple` press a button of a message, save a file and open it again in the document picker, and pick a photo in the photo picker. They run on the iOS simulator, on an iPhone and on an iPad:

```sh
haylen test --ui sample --target ios-simulator
```
