# 📷 Camera

The Camera plugin for [Haylen](https://github.com/haylen-org/haylen) apps shows the cameras of the device in a video stream, whose texture the app draws like any other, and takes photos as JPEG bytes. It owns the permission `camera`, which the app checks and asks for with `camera.permission()` and `camera.requestPermission()` of the plugin, which the [Permissions plugin](../permissions) answers. Its Lua API is the same on every platform, and a platform that cannot serve a call answers why.

| Platform | Native part | Cameras |
| --- | --- | --- |
| iPhone and iPad | `apple/`, Swift | The cameras of AVFoundation: wide, ultra wide, telephoto and TrueDepth, and the USB cameras of an iPad from iPadOS 17. The picture turns with the device, and the front camera shows a mirror image. |
| Mac Catalyst and macOS app | `apple/`, Swift | The built-in camera, USB cameras and, from macOS 14, the Continuity Camera of an iPhone. |
| tvOS | `apple/`, Swift | From tvOS 17, the Continuity Camera of an iPhone or an iPad, which the person connects in the picker of the system that the plugin shows when no camera is connected. |
| visionOS | `apple/`, Swift | From visionOS 2.1, the camera of the persona of the wearer. |
| Android | The library module in `android/` | The cameras of Camera2. The picture is upright for the rotation of the screen at the start, and the front camera shows a mirror image. |
| Web | `web/camera.js` | The cameras of `getUserMedia` on secure pages. The front camera shows a mirror image. |
| macOS desktop player | The library of `native/`, Objective-C++ | The cameras of AVFoundation, asked for in the name of the app that started the player, such as the terminal. |
| Windows | The library of `native/`, C++ | The cameras of Media Foundation, with the panel of the device telling which way a built-in camera faces. |
| Linux | The library of `native/`, C++ | The cameras of Video4Linux that deliver uncompressed YUYV frames. |

## Installation

The plugin depends on the [`permissions`](../permissions) plugin, which answers its permission, so the app lists both:

```sh
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path permissions --reference --app my-app
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path camera --reference --app my-app
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
        "camera": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "camera"
        }
    }
}
```

Without `--reference`, the commands copy the plugins into `plugins/permissions/` and `plugins/camera/` of the app instead. A parameter that the entry leaves out takes its default from `plugin.json`, so the app follows the defaults of newer versions of the plugin. To stay on one version of the plugin, the app names a commit in `ref` instead of the branch `main`.

## Parameters

| Parameter | Type | Default | Meaning |
| --- | --- | --- | --- |
| `cameraUsage` | string | `"The app shows the camera."` | The `NSCameraUsageDescription` of iOS, iPadOS, Mac Catalyst, tvOS, visionOS and macOS, which the prompt of the camera shows. |
| `macEntitlement` | boolean | `true` | Whether the macOS app signs with the entitlement `com.apple.security.device.camera`, without which the hardened runtime gives it no camera. It has a value on macOS alone. |

## Setup

- **Apple platforms.** The plugin gives the `Info.plist` its `NSCameraUsageDescription` from the parameter `cameraUsage`, without which the system shows no prompt, and the permission and the calls that need it fail with the code `unsupported` and `data.missing`. The macOS app signs with the entitlement `com.apple.security.device.camera` of the hardened runtime while `macEntitlement` is `true`. It links `AVFoundation.framework`, `CoreMedia.framework` and `ImageIO.framework`.
- **Android.** The manifest of the module declares `android.permission.CAMERA`, which Android asks the person for, and the feature `android.hardware.camera.any` as not required, so devices without a camera, such as most TVs, still install the app.
- **Web.** The page needs a secure context, `https` or `localhost`, and a permissions policy that allows `camera`, which a page inside a frame gets from the `allow` attribute of its frame.
- **Windows, Linux and the desktop player.** The `nativeLibrary` contribution of `plugin.json` names the CMake project of `native/`, which the tooling builds against the installed desktop SDK of the engine and places next to the app, and the Lua API loads it. The library is C++, with Objective-C++ for AVFoundation on macOS, and reads and writes the JSON of its calls with nlohmann/json of the SDK. Windows links Media Foundation and WIC, and Linux needs nothing beyond the kernel.

## Lua API

```lua
local camera = require('camera')
```

Every function that talks to the native part returns a call of `haylen.platform`, whose `await` inside a coroutine gives the answer, or `nil` and an error with `message`, `code` and `data`. A call that needs the camera asks for the permission `camera` where the app does not hold it yet, the way `camera.requestPermission()` does, so an app that wants to explain the camera first checks `camera.permission()` and asks with `camera.requestPermission()` itself. The capture belongs to the process, like its stream, so the Lua API of every app that starts stops a capture that an earlier app left running.

### camera.cameras()

Gives the list of the cameras, each `{id, name, facing}`, where `facing` is `'front'`, `'back'` or `'external'` for a camera that faces neither way or whose way the system does not tell. It asks for the permission `camera` first on every platform, since browsers name the cameras only to a page that holds it.

```lua
local camera = require('camera')
local scene = require('haylen.scene')

scene.push({
    enter = function(self)
        scene.spawn(self, function()
            local cameras, err = camera.cameras():await()
            for _, found in ipairs(cameras or {}) do
                print(found.name .. ' faces ' .. found.facing .. '.')
            end
        end)
    end,
})
```

### camera.start(options)

Starts a camera and gives `{id, name, facing, width, height}`, with the size of the frames that the stream receives. A camera that runs stops first. The table `options` is optional:

| Option | Type | Default | Meaning |
| --- | --- | --- | --- |
| `camera` | string | none | The `id` of a camera that `camera.cameras()` listed. |
| `facing` | string | none | The first camera that faces `'front'`, `'back'` or `'external'`. Without `camera` and `facing`, the default camera of the system starts. |
| `width`, `height` | integer | `640`, `480` | The size the app asks for. The camera takes its format whose size is the closest. |
| `owner` | table or userdata | none | The owner whose end stops the camera, such as a scene. Without it the camera runs until `camera.stop()`. |

An unknown key raises `Unknown option "<key>".`, a `camera` that is not a string raises `The option "camera" of "camera.start" is the id of a camera that "camera.cameras" lists.`, both `camera` and `facing` raise `The options "camera" and "facing" of "camera.start" exclude each other.`, another `facing` raises `The option "facing" of "camera.start" is "front", "back" or "external", not "<value>".`, a size that is not a positive integer raises `The option "<key>" of "camera.start" is a positive integer of pixels.`, and an owner that is not a table or a userdata raises `An owner must be a table or a userdata, not <type>.`.

```lua
local camera = require('camera')
local graphics2d = require('haylen.graphics2d')
local scene = require('haylen.scene')

scene.push({
    enter = function(self)
        scene.spawn(self, function()
            local started, err = camera.start({facing = 'back', width = 1280, height = 720, owner = self}):await()
            print(started and started.width .. ' by ' .. started.height or err.message)
        end)
    end,
    render = function(self)
        local stream = camera.stream()
        if stream then
            graphics2d.beginScreen()
            graphics2d.draw(stream.texture, 40, 40, {width = 640, height = 640 * stream.height / math.max(stream.width, 1), pivotX = 0, pivotY = 0})
        end
    end,
})
```

### camera.stop()

Stops the camera. A camera that does not run stops nothing, and the call still answers.

### camera.stream()

Returns the video stream of `haylen.platform` that the frames of the camera reach, or `nil` until a camera started once in the process. Its `texture` shows the newest frame and resizes in place with the frames, so a sprite or a UI image that holds it keeps showing the camera. The stream outlives the app, like every stream of a plugin, so an app that restarted finds it again.

```lua
local camera = require('camera')
local ui = require('haylen.ui')

local function showCamera(gui)
    ui.setImage('@camera', camera.stream().texture)
    gui:replaceChildren('preview', {ui.image{image = '@camera', fit = 'cover'}})
end
```

### camera.takePhoto()

Takes a photo from the newest frame and gives `{jpeg, width, height}`, with the bytes of a JPEG file in `jpeg`, which `graphics.newTexture(jpeg)` turns into a texture. It fails with the code `cameraOff` while no camera runs, `noFrame` before the first frame and `cameraFailed` for a frame that does not encode. Linux has no JPEG encoder in its system API, so it fails there with `unsupported`, and an app takes a picture of the stream with `graphics.readTarget` and `image:encodePng` instead.

```lua
local async = require('async')
local camera = require('camera')
local graphics = require('haylen.graphics')

async.spawn(function()
    local photo, err = camera.takePhoto():await()
    local texture = photo and graphics.newTexture(photo.jpeg)
    print(texture and 'A photo of ' .. photo.width .. ' by ' .. photo.height .. '.' or err.message)
end)
```

### camera.onStopped(listener, options)

Calls `listener({message, code})` when the camera stops by itself while it runs, such as when the system gives it to another app or the person unplugs it, with the code `cameraFailed`, and returns the connection of the listener, whose `disconnect()` stops it. The table `options` takes `owner`.

```lua
local camera = require('camera')

camera.onStopped(function(stopped)
    print('The camera stopped: ' .. stopped.message)
end)
```

### camera.permission()

Returns a call of `haylen.platform` whose `await` gives the state of the permission `camera`, as far as the platform tells it, without asking the person: `'granted'`, `'prompt'`, `'denied'` or `'unknown'`. The [Permissions plugin](../permissions) asks the native part of the plugin for it through the method `camera.permission`. A platform without the capability fails the call with the code `unsupported` and the reason as `message`, a project that lacks a requirement adds `data.missing`, and a platform without the native part fails it with `noHandler`, as every call of the plugin. Like every platform call, a failure that nothing awaits stops the app. The name is optional, since the plugin owns one permission, and another name raises `The plugin "camera" owns no permission "<name>". It owns "camera".`. The table [What each platform answers](#what-each-platform-answers) lists the states of each platform.

```lua
local async = require('async')
local camera = require('camera')

async.spawn(function()
    local state, failure = camera.permission():await()
    if state == 'prompt' then
        print('The app explains why it wants the camera before it asks.')
    elseif not state then
        print(failure.code .. ': ' .. failure.message)
    end
end)
```

### camera.requestPermission()

Asks the person for the permission `camera` with the prompt of the system and returns a call of `haylen.platform` whose `await` gives the state that the person left. The prompt shows only while the state is `'prompt'`, so a permission that the app holds answers `'granted'` at once and one that the person refused answers `'denied'` without a prompt. A project that lacks what the prompt needs, such as the usage description of the `Info.plist` or the permission of the Android manifest, and a platform without the capability fail the call with the code `unsupported` and the reason as `message`, with `data.missing` for what the project lacks, which the log tells once with how to add it. Like every platform call, a failure that nothing awaits stops the app.

A call of the plugin that needs the camera asks for the permission the same way first. A call that the person refused fails with the code `denied` and the sentence `The person has not allowed the camera. Ask for it with "camera.requestPermission('camera')", which shows the prompt of the system while the system still asks, or the person allows it in the settings of the system.`, and a call whose request ended without the prompt of the system fails with the code `denied` and the sentence `The system did not show its prompt for the camera, so the app does not hold it yet. Ask for it again later with "camera.requestPermission('camera')".`.

```lua
local async = require('async')
local camera = require('camera')

async.spawn(function()
    local state, failure = camera.requestPermission():await()
    print(state and 'The camera is ' .. state .. '.' or failure.code .. ': ' .. failure.message)
end)
```

## Errors

| Code | Message | When |
| --- | --- | --- |
| `denied` | One of the two refusal sentences of [`camera.requestPermission()`](#camerarequestpermission). | The person refused the camera. |
| `unsupported` | The reason, such as `Apple TV gives apps a camera from tvOS 17 on.` or `This device has no camera.`, with `data.missing` for a requirement that the project lacks. | The platform or the device has no camera for the app. |
| `noCamera` | `This device has no camera with the id "<id>". The function "camera.cameras" lists the cameras.`, `This device has no camera that faces "<facing>".` or `This device has no camera.` | No camera matches the options. |
| `cameraFailed` | The reason of the system, such as `The camera "<name>" did not open: <reason>`, or `The frame of the camera did not encode as a JPEG file.` | The camera did not start, stopped while it ran, or gave a photo that did not encode. |
| `cameraOff` | `The camera is off. Call "camera.start" first.` | A photo while no camera runs. |
| `noFrame` | `The camera has no frame yet.` | A photo before the first frame. |
| `cancelled` | `The person closed the picker of the Continuity Camera without a camera.` or `The camera stopped or started again before this start ended.` | The person closed the picker of tvOS, or a `camera.stop()` or another `camera.start()` came while a start still waited for the permission or the camera, on Apple platforms, Android and the web. |

## Native API

| Method or event | Params or payload | Answer |
| --- | --- | --- |
| `camera.reset` | `{}` | `null` |
| `camera.cameras` | `{}` | `[{id, name, facing}]` |
| `camera.start` | `{camera, facing, width, height}` | `{id, name, facing, width, height}` |
| `camera.stop` | `{}` | `null` |
| `camera.takePhoto` | `{}` | `{jpeg, width, height}`, with the bytes of a JPEG file in `jpeg` |
| `camera.permission`, `camera.requestPermission` | `{name}` | The name of the state, or a failure with the code `unsupported`, the reason and `data.missing`, which the Permissions plugin answers for the permission that the native part registers on Apple platforms, Android and the web, and the library of `native/` answers on desktops |
| `camera.stopped` (event) | `{message, code}` | |

The video stream is `camera`, in BGRA on Apple platforms and Windows and in RGBA elsewhere.

## What each platform answers

| Platform | `camera.permission()` | Notes |
| --- | --- | --- |
| iPhone, iPad, Mac Catalyst, macOS app, visionOS | The authorization of AVFoundation: `prompt` before the first prompt, then `granted` or `denied`. | Before visionOS 2.1 the calls fail with `unsupported`. |
| tvOS | The authorization of AVFoundation from tvOS 17, and `unsupported` before. | The simulator of tvOS takes no Continuity Camera, so a start there fails with `unsupported`. |
| Android | `granted`, `prompt`, or `denied` once Android no longer shows the prompt. | A device without a camera fails the calls with `unsupported` before it asks. |
| Web | The state of the Permissions API, or `unknown` where the browser tells nothing before it asks. | A page that is not secure, or whose policy does not allow the camera, fails the permission and the calls with the code `unsupported` and `data.missing`. |
| macOS desktop player | The authorization of AVFoundation for the app that started the player. | |
| Windows | The setting of the privacy of the camera through `AppCapability`: `granted`, `prompt`, `denied`, or `unknown` on a Windows without that API. | |
| Linux | `granted`, since Linux gates no camera of an app outside a sandbox. | Facing is always `external`, since Video4Linux does not tell it, and a camera that sends only compressed frames fails with `cameraFailed`. |

## Platforms without the plugin

Every platform of Haylen has a native part. Apple TV before tvOS 17 and Apple Vision Pro before visionOS 2.1 give apps no camera, so the calls there fail with the code `unsupported` and that reason.

## Sample

The app in `sample/` references the plugin with `"path": ".."` and has a button for every call, with the picture of the camera, the last photo and the answer of each call:

```sh
haylen app run sample
haylen app run sample --target macos
haylen app run sample --target ios-simulator
haylen app run sample --target android
haylen app run sample --target web
```

The UI tests in `sample/ui-tests` answer the prompt or the dialog of the camera, list the cameras, start the back and the front cameras and a camera at 1280 by 720, take a photo and stop the camera. On the iOS simulator, which has no camera, they check that the list is empty and that a start fails with `noCamera`. They run on the simulators, the emulator and devices:

```sh
haylen test --ui sample --target ios-simulator
haylen test --ui sample --target android
haylen test --ui sample --target ios --device <name or UDID>
```

## License

MIT, like Haylen.
