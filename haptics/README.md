# 📳 Haptics

The Haptics plugin for [Haylen](https://github.com/haylen-org/haylen) apps vibrates the device and plays the feedback of its haptic engine: the tap of an impact, the tick of a selection and the feedback of a task that ended. Its Lua API is the same on every platform, and a device that cannot play a call answers why. The rumble of gamepads is not part of this plugin, since the engine offers it as `input.rumble`.

| Platform | Native part | Vibration | Feedback |
| --- | --- | --- | --- |
| iPhone | `apple/HapticsPlugin.swift` | A continuous event of Core Haptics for the seconds given. | The impact, selection and notification feedback generators of UIKit. |
| iPad, Mac Catalyst, tvOS and visionOS | `apple/HapticsPlugin.swift` | None, since the device has no motor. | None, since the device has no haptic engine that apps reach. |
| macOS | `apple/HapticsPlugin.swift` in the macOS app, and the C++ library of `native/` in the desktop player | None, since a Mac has no motor. | The feedback of the Force Touch trackpad through `NSHapticFeedbackManager`. |
| Android | The library module in `android/` | The vibrator of the device for the time given. | The haptic feedback constants of the system, played on the view of the activity. |
| Web | `web/haptics.js` | The Vibration API, where the browser has it. | None, since browsers offer pages no haptic engine. |
| Windows and Linux | The C++ library of `native/` | None. | None. |

## Installation

```sh
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path haptics --reference --app my-app
```

The command lists the plugin in the `plugins` section of the `haylen.json` of the app as a reference to its folder in the repository of the Haylen plugins:

```json
{
    "plugins": {
        "haptics": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "haptics"
        }
    }
}
```

Without `--reference`, the command copies the plugin into `plugins/haptics/` of the app instead. To stay on one version of the plugin, the app names a commit in `ref` instead of the branch `main`.

## Parameters

The plugin has no parameters.

## Setup

- **Android.** The manifest of the module declares the permission `android.permission.VIBRATE`, which Android grants at install and which the vibrator needs. The haptic feedback needs no permission. An app whose manifest removes the permission makes `haptics.vibrate` fail with the code `unsupported` and `data.missing`, which the log tells once.
- **Apple platforms.** The plugin links `CoreHaptics.framework`, and needs no key of the `Info.plist`.
- **Windows, Linux and the desktop player.** The tooling builds the C++ library of `native/` with CMake against the desktop SDK of the engine and places it next to the app, and the Lua API loads it.

## Lua API

```lua
local haptics = require('haptics')
```

Every function returns a platform call of `haylen.platform`, whose `await` gives `true` once the device played the call, or `nil` and an error whose code is `unsupported` or `denied` and whose message says why. Feedback often plays on its own, such as on every hit, so the plugin logs each reason of a refusal once as a warning, and a refusal that nothing awaits never stops the app.

### haptics.vibrate(seconds)

Vibrates the device for `seconds`. A value that is not a positive finite number raises `A vibration lasts a positive number of seconds.`. A platform may cut a long vibration short, as browsers do.

```lua
local haptics = require('haptics')

local function onHit()
    haptics.vibrate(0.08)
end

onHit()
```

### haptics.impact(strength)

Plays the tap of an impact, such as two objects that collide. The `strength` is `'light'`, `'medium'` or `'heavy'`, `'medium'` by default. Another value raises `The strength of an impact is "light", "medium" or "heavy", not "<value>".`.

```lua
local haptics = require('haptics')

haptics.impact('heavy')
```

### haptics.selection()

Plays the light tick of a selection that changes, such as the value of a picker that the person turns.

```lua
local haptics = require('haptics')

haptics.selection()
```

### haptics.notification(kind)

Plays the feedback of a task that ended. The `kind` is `'success'`, `'warning'` or `'error'`. Another value raises `The kind of a notification is "success", "warning" or "error", not "<value>".`.

```lua
local async = require('async')
local haptics = require('haptics')

async.spawn(function()
    local played, err = haptics.notification('success'):await()
    if not played then
        print('No feedback: ' .. err.message)
    end
end)
```

## What each platform answers

| Platform | `vibrate` | `impact`, `selection` | `notification` |
| --- | --- | --- | --- |
| iPhone | `true` once Core Haptics plays it, or `unsupported`, `The haptic engine could not vibrate.` and the reason of the system. | `true` once the generator played it. | `true` once the generator played it. |
| iPad and the simulators of iPhone | `unsupported`, `This device has no haptic engine.` | `unsupported`, `This device has no haptic engine.` | `unsupported`, `This device has no haptic engine.` |
| Mac Catalyst | `unsupported`, `A Mac has no vibration motor.` | `unsupported`, `UIKit plays no haptic feedback on a Mac.` | `unsupported`, `UIKit plays no haptic feedback on a Mac.` |
| macOS | `unsupported`, `A Mac has no vibration motor.` | `true` once the trackpad took the feedback. A Mac plays one generic feedback for every strength and an alignment for a selection, and feels them only while a finger rests on a Force Touch trackpad, which the system does not tell an app. | `unsupported`, `The trackpad of a Mac has no feedback of a notification.` |
| tvOS | `unsupported`, `An Apple TV has no vibration motor.` | `unsupported`, `An Apple TV has no haptic engine.` | `unsupported`, `An Apple TV has no haptic engine.` |
| visionOS | `unsupported`, `Apple Vision Pro has no vibration motor.` | `unsupported`, `Apple Vision Pro has no haptic engine.` | `unsupported`, `Apple Vision Pro has no haptic engine.` |
| Android | `true` once the vibrator took it, `unsupported`, `This device has no vibration motor.` on a device without one, and `unsupported` with `data.missing` without the permission. | `true` once the system played it, or `unsupported`, `Android played no haptic feedback, as it does on a device without a vibration motor or with touch feedback turned off.`, and `unsupported`, `The haptic feedback plays only while the app has an activity.` while the app has none. The light, medium and heavy impacts are the constants `KEYBOARD_TAP`, `VIRTUAL_KEY` and `LONG_PRESS`, and a selection is `CLOCK_TICK`. | `true` for a success, `CONFIRM`, and an error, `REJECT`, from Android 11, with the answers of a feedback that did not play, and `unsupported`, `Android plays the haptic feedback of a success or an error from Android 11.` before. A warning is `unsupported`, `Android has no haptic feedback of a warning.`. |
| Web | `true` once the browser vibrates, `denied`, `The browser vibrates only after an input of the person, such as a tap.` before the first input of the person, and `unsupported` without the Vibration API, with `data.missing`. A desktop browser with the API answers `true` though nothing vibrates. | `unsupported`, `Browsers offer pages no haptic engine, only the vibration of "haptics.vibrate".` | `unsupported`, `Browsers offer pages no haptic engine, only the vibration of "haptics.vibrate".` |
| Windows | `unsupported`, `Windows gives apps no vibration motor.` | `unsupported`, `Windows gives apps no haptic engine.` | `unsupported`, `Windows gives apps no haptic engine.` |
| Linux | `unsupported`, `Linux gives apps no vibration motor.` | `unsupported`, `Linux gives apps no haptic engine.` | `unsupported`, `Linux gives apps no haptic engine.` |

## Sample

The app in `sample/` references the plugin with `"path": ".."` and has a button for every call, with the answer of each one:

```sh
haylen app run sample
haylen app run sample --target ios-simulator
haylen app run sample --target android
haylen app run sample --target web
```

## Native API

| Method | Params | Answer |
| --- | --- | --- |
| `haptics.vibrate` | `{seconds}` | `true` |
| `haptics.impact` | `{strength}` | `true` |
| `haptics.selection` | `{}` | `true` |
| `haptics.notification` | `{kind}` | `true` |

The UI tests in `sample/ui-tests` press every button of the sample and check what each call answers, all that a haptic engine tells an app: a phone plays each feedback, the simulator of the iPhone answers `unsupported`, Android has no feedback of a warning and plays the success and the error from Android 11, and a vibration of 0 seconds raises. They run on the simulators, the emulator and devices:

```sh
haylen test --ui sample --target ios-simulator
haylen test --ui sample --target android
haylen test --ui sample --target ios --device <name or UDID>
```

## License

MIT, like Haylen.
