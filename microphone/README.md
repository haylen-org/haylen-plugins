# 🎙️ Microphone

The Microphone plugin for [Haylen](https://github.com/haylen-org/haylen) apps records the microphone of the device as mono samples into an audio stream, which plays as a voice of `haylen.audio` and gives its newest samples to Lua, such as for a level meter or speech recognition. It owns the permission `microphone`, which the app checks and asks for with `microphone.permission()` and `microphone.requestPermission()` of the plugin, which the [Permissions plugin](../permissions) answers. Its Lua API is the same on every platform, and a platform that cannot serve a call answers why.

| Platform | Native part | Input |
| --- | --- | --- |
| iPhone, iPad, Mac Catalyst, visionOS and macOS app | `apple/`, Swift | The input of AVAudioEngine, converted with AVAudioConverter. On iPhones, iPads and visionOS the audio session records while the microphone runs and mixes with the sound of the app. |
| tvOS | `apple/`, Swift | From tvOS 17, the microphone of an iPhone or an iPad that the person connects in the picker of the Continuity Camera, which the plugin shows while the Apple TV has no input. |
| Android | The library module in `android/` | `AudioRecord` with floats at the rate the app asks for. |
| Web | `web/microphone.js` and `web/microphone-worklet.js` | `getUserMedia` through an audio worklet, on secure pages. The browser converts the input to the rate of its audio context. |
| macOS desktop player | The library of `native/`, Objective-C++ | The input of AVAudioEngine, asked for in the name of the app that started the player, such as the terminal. |
| Windows | The library of `native/`, C++ | WASAPI in shared mode, which converts the default input to the rate the app asks for. |
| Linux | The library of `native/`, C++ | The `default` capture device of ALSA, whose plug layer converts the input. |

## Installation

The plugin depends on the [`permissions`](../permissions) plugin, which answers its permission, so the app lists both:

```sh
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path permissions --reference --app my-app
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path microphone --reference --app my-app
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
        "microphone": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "microphone"
        }
    }
}
```

Without `--reference`, the commands copy the plugins into `plugins/permissions/` and `plugins/microphone/` of the app instead. A parameter that the entry leaves out takes its default from `plugin.json`, so the app follows the defaults of newer versions of the plugin. To stay on one version of the plugin, the app names a commit in `ref` instead of the branch `main`.

## Parameters

| Parameter | Type | Default | Meaning |
| --- | --- | --- | --- |
| `microphoneUsage` | string | `"The app listens to the microphone."` | The `NSMicrophoneUsageDescription` of iOS, iPadOS, Mac Catalyst, tvOS, visionOS and macOS, which the prompt of the microphone shows. |
| `macEntitlement` | boolean | `true` | Whether the macOS app signs with the entitlement `com.apple.security.device.audio-input`, without which the hardened runtime gives it no microphone. It has a value on macOS alone. |

## Setup

- **Apple platforms.** The plugin gives the `Info.plist` its `NSMicrophoneUsageDescription` from the parameter `microphoneUsage`, without which the system shows no prompt, and the permission and the calls that need it fail with the code `unsupported` and `data.missing`. The macOS app signs with the entitlement `com.apple.security.device.audio-input` of the hardened runtime while `macEntitlement` is `true`. It links `AVFoundation.framework`.
- **Android.** The manifest of the module declares `android.permission.RECORD_AUDIO`, which Android asks the person for, and the feature `android.hardware.microphone` as not required, so devices without a microphone still install the app.
- **Web.** The page needs a secure context, `https` or `localhost`, a permissions policy that allows `microphone` and the API `AudioWorkletNode`. A browser starts an audio context only after a gesture of the person, such as the tap that started the recording, and keeps it silent until then.
- **Windows, Linux and the desktop player.** The tooling builds the C++ library of `native/` with CMake against the installed SDK of the engine, whose target `haylen::native` gives it the native API and nlohmann/json, and places it next to the app, and the Lua API loads it. Linux needs the library of ALSA, `libasound`, which every desktop distribution ships, and its headers to build, such as the package `libasound2-dev` of Debian and Ubuntu.

## Lua API

```lua
local microphone = require('microphone')
```

Every function that talks to the native part returns a call of `haylen.platform`, whose `await` inside a coroutine gives the answer, or `nil` and an error with `message`, `code` and `data`. A start asks for the permission `microphone` where the app does not hold it yet, the way `microphone.requestPermission()` does. The recording belongs to the process, like its stream, so the Lua API of every app that starts stops a recording that an earlier app left running.

### microphone.start(options)

Starts the microphone and gives `{sampleRate, channels, stream}`, with one channel and the name of the audio stream. A recording that runs stops first. The table `options` is optional:

| Option | Type | Default | Meaning |
| --- | --- | --- | --- |
| `sampleRate` | integer | `48000` | The rate of the samples in hertz, from 8000 to 192000, such as 16000 for speech. The plugin converts the input of the device to it. |
| `owner` | table or userdata | none | The owner whose end stops the microphone, such as a scene. Without it the microphone runs until `microphone.stop()`. |

An unknown key raises `Unknown option "<key>".`, another rate raises `The option "sampleRate" of "microphone.start" is an integer of hertz from 8000 to 192000.`, and an owner that is not a table or a userdata raises `An owner must be a table or a userdata, not <type>.`.

```lua
local microphone = require('microphone')
local scene = require('haylen.scene')

scene.push({
    enter = function(self)
        scene.spawn(self, function()
            local started, err = microphone.start({sampleRate = 16000, owner = self}):await()
            print(started and 'Recording at ' .. started.sampleRate .. ' Hz.' or err.message)
        end)
    end,
})
```

### microphone.stop()

Stops the microphone. A microphone that does not run stops nothing, and the call still answers.

### microphone.stream()

Returns the audio stream of `haylen.platform` of the last start, or `nil` until the native part opened it. A stream keeps the rate it opened with and outlives the app, so each rate has a stream of its own, named after it, such as `microphone-48000`. The method `stream:play(options)` plays it as a voice, and `stream:read(buffer)` copies its newest samples into a float buffer of `haylen.collections`.

```lua
local microphone = require('microphone')

local function playBack()
    local stream = microphone.stream()
    return stream and stream:play({bus = 'sfx', volume = 0.8})
end
```

### microphone.level()

Returns the level of the newest samples, up to 1024 of them, as two numbers from 0 to 1: the root mean square and the peak. Both are 0 while no stream exists or nothing arrived. It reads the stream into a buffer that the module keeps, so it allocates nothing and suits a meter that draws every frame.

```lua
local microphone = require('microphone')
local scene = require('haylen.scene')

scene.push({
    update = function(self)
        local rms, peak = microphone.level()
        self.loud = rms > 0.1 or peak > 0.8
    end,
})
```

### microphone.onStopped(listener, options)

Calls `listener({message, code})` when the recording stops by itself while it runs, such as when a headset is plugged in or out or the person unplugs the microphone, with the code `microphoneFailed`, and returns the connection of the listener, whose `disconnect()` stops it. The table `options` takes `owner`.

```lua
local microphone = require('microphone')

microphone.onStopped(function(stopped)
    print('The microphone stopped: ' .. stopped.message)
end)
```

### microphone.permission()

Returns a call of `haylen.platform` whose `await` gives the state of the permission `microphone`, as far as the platform tells it, without asking the person: `'granted'`, `'prompt'`, `'denied'` or `'unknown'`. The [Permissions plugin](../permissions) asks the native part of the plugin for it through the method `microphone.permission`. A platform without the capability fails the call with the code `unsupported` and the reason as `message`, a project that lacks a requirement adds `data.missing`, and a platform without the native part fails it with `noHandler`, as every call of the plugin. Like every platform call, a failure that nothing awaits stops the app. The name is optional, since the plugin owns one permission, and another name raises `The plugin "microphone" owns no permission "<name>". It owns "microphone".`. The table [What each platform answers](#what-each-platform-answers) lists the states of each platform.

```lua
local async = require('async')
local microphone = require('microphone')

async.spawn(function()
    local state, failure = microphone.permission():await()
    if state == 'prompt' then
        print('The app explains why it wants the microphone before it asks.')
    elseif not state then
        print(failure.code .. ': ' .. failure.message)
    end
end)
```

### microphone.requestPermission()

Asks the person for the permission `microphone` with the prompt of the system and returns a call of `haylen.platform` whose `await` gives the state that the person left. The prompt shows only while the state is `'prompt'`, so a permission that the app holds answers `'granted'` at once and one that the person refused answers `'denied'` without a prompt. A project that lacks what the prompt needs, such as the usage description of the `Info.plist` or the permission of the Android manifest, and a platform without the capability fail the call with the code `unsupported` and the reason as `message`, with `data.missing` for what the project lacks, which the log tells once with how to add it. Like every platform call, a failure that nothing awaits stops the app.

A call of the plugin that needs the microphone asks for the permission the same way first. A call that the person refused fails with the code `denied` and the sentence `The person has not allowed the microphone. Ask for it with "microphone.requestPermission('microphone')", which shows the prompt of the system while the system still asks, or the person allows it in the settings of the system.`, and a call whose request ended without the prompt of the system fails with the code `denied` and the sentence `The system did not show its prompt for the microphone, so the app does not hold it yet. Ask for it again later with "microphone.requestPermission('microphone')".`.

```lua
local async = require('async')
local microphone = require('microphone')

async.spawn(function()
    local state, failure = microphone.requestPermission():await()
    print(state and 'The microphone is ' .. state .. '.' or failure.code .. ': ' .. failure.message)
end)
```

## Errors

| Code | Message | When |
| --- | --- | --- |
| `denied` | One of the two refusal sentences of [`microphone.requestPermission()`](#microphonerequestpermission). | The person refused the microphone. |
| `unsupported` | The reason, such as `Apple TV gives apps a microphone from tvOS 17 on.` or `This device has no microphone.`, with `data.missing` for a requirement that the project lacks. | The platform or the device has no microphone for the app. |
| `microphoneFailed` | The reason of the system, such as `The microphone cannot record mono samples at <rate> Hz.` | The microphone did not start, or stopped while it ran. |
| `cancelled` | `The person closed the picker of the Continuity Camera without a device.` | The person closed the picker of tvOS. |

## Native API

| Method or event | Params or payload | Answer |
| --- | --- | --- |
| `microphone.reset` | `{}` | `null` |
| `microphone.start` | `{sampleRate}` | `{sampleRate, channels, stream}` |
| `microphone.stop` | `{}` | `null` |
| `microphone.permission`, `microphone.requestPermission` | `{name}` | The name of the state, or a failure with the code `unsupported`, the reason and `data.missing`, which the Permissions plugin answers for the permission that the native part registers on Apple platforms, Android and the web, and the library of `native/` answers on desktops |
| `microphone.stopped` (event) | `{message, code}` | |

The audio stream is `microphone-<sampleRate>`, with one channel of 32-bit floats and room for one second.

## What each platform answers

| Platform | `microphone.permission()` | Notes |
| --- | --- | --- |
| iPhone, iPad, Mac Catalyst, macOS app, visionOS | The authorization of AVFoundation: `prompt` before the first prompt, then `granted` or `denied`. | |
| tvOS | The authorization of AVFoundation from tvOS 17, and `unsupported` before. | The simulator of tvOS records the input of the Mac that runs it. It takes no Continuity Camera, so a start there without an input of the Mac fails with `unsupported`. |
| Android | `granted`, `prompt`, or `denied` once Android no longer shows the prompt. | A device without a microphone fails a start with `unsupported` before it asks, and a rate that the device does not record fails with `microphoneFailed`. |
| Web | The state of the Permissions API, or `unknown` where the browser tells nothing before it asks. | A page that is not secure, or whose policy does not allow the microphone, fails the permission and the calls with the code `unsupported` and `data.missing`. |
| macOS desktop player | The authorization of AVFoundation for the app that started the player. | |
| Windows | The setting of the privacy of the microphone through `AppCapability`: `granted`, `prompt`, `denied`, or `unknown` on a Windows without that API. | |
| Linux | `granted`, since Linux gates no microphone of an app outside a sandbox. | A system without a capture device fails a start with `unsupported`. |

## Platforms without the plugin

Every platform of Haylen has a native part. Apple TV before tvOS 17 gives apps no microphone, so a start there fails with the code `unsupported` and that reason.

## Sample

The app in `sample/` references the plugin with `"path": ".."` and has a button for every call, with the level of the microphone in two bars, a voice that plays the recording back and the answer of each call:

```sh
haylen app run sample
haylen app run sample --target macos
haylen app run sample --target ios-simulator
haylen app run sample --target android
haylen app run sample --target web
```

The UI tests in `sample/ui-tests` answer the prompt or the dialog of the microphone, record at 16000 and 48000 Hz, check on a device that the level of the room rises above zero, play the recording back and stop. The iOS simulator records through the microphone of the Mac, which the Mac guards with a prompt of its own, so the iOS test runs on a device. They run on the emulator and devices:

```sh
haylen test --ui sample --target ios-simulator
haylen test --ui sample --target android
haylen test --ui sample --target ios --device <name or UDID>
```

## License

MIT, like Haylen.
