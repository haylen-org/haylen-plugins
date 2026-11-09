# 🧭 Motion

The Motion plugin for [Haylen](https://github.com/haylen-org/haylen) apps reads the motion sensors of the device: the accelerometer, the gyroscope and the attitude that the system fuses from them, and the tilt that the accelerometer measures. It owns the permission `motion`, which the app checks and asks for with `motion.permission()` and `motion.requestPermission()` of the plugin, which the [Permissions](../permissions) plugin answers. Its Lua API is the same on every platform, and a device without the sensors answers why. The motion sensors of gamepads are not part of this plugin, since the engine reads them as `input.startGamepadMotion`.

| Platform | Native part | Sensors |
| --- | --- | --- |
| iOS and iPadOS | `apple/MotionPlugin.swift` | Core Motion: the accelerometer, the gyroscope and the device motion, whose attitude has z up. |
| visionOS | `apple/MotionPlugin.swift` | Core Motion, where the device offers it. |
| Mac Catalyst, macOS and tvOS | `apple/MotionPlugin.swift`, and the C++ library of `native/` in the desktop player of macOS | None. |
| Android | The library module in `android/` | The accelerometer, the gyroscope and the game rotation vector of the sensor manager. |
| Web | `web/motion.js` | The `devicemotion` and `deviceorientation` events of the page. |
| Windows | The C++ library of `native/` | The accelerometer, the gyrometer and the relative orientation sensor of `Windows.Devices.Sensors`, on tablets and convertibles that have them, through C++/WinRT. |
| Linux | The C++ library of `native/` | None. |

## Installation

```sh
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path permissions --reference --app my-app
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path motion --reference --app my-app
```

The plugin depends on the `permissions` plugin, which owns the permission contract, so the app lists it too. The commands list both plugins in the `plugins` section of the `haylen.json` of the app as references to their folders in the repository of the Haylen plugins:

```json
{
    "plugins": {
        "permissions": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "permissions"
        },
        "motion": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "motion"
        }
    }
}
```

Without `--reference`, the command copies the plugin into `plugins/motion/` of the app instead. A parameter that the entry leaves out takes its default from `plugin.json`, so the app follows the defaults of newer versions of the plugin. To stay on one version of the plugin, the app names a commit in `ref` instead of the branch `main`.

## Parameters

| Parameter | Type | Platforms | Default | Meaning |
| --- | --- | --- | --- | --- |
| `motionUsage` | string | iOS, visionOS | `The app reads how the device moves and leans.` | The text of the prompt of the motion sensors. |

## Setup

- **iOS, iPadOS and visionOS.** From version 27.2 the system asks the person the first time the app starts the sensors, with the text of `NSMotionUsageDescription`, which the plugin fills from its parameter `motionUsage`. An `Info.plist` of the project that holds its own text keeps it. The plugin reaches Core Motion through the `import` of its Swift, so it declares no framework that the other Apple platforms lack.
- **Android.** The plugin needs no permission of the manifest. Android gives an app at most 200 readings per second without `HIGH_SAMPLING_RATE_SENSORS`, which is the highest rate that the plugin takes.
- **Web.** Browsers fire the events only in pages served over https or from localhost, and a page in a frame needs `accelerometer` and `gyroscope` in the `allow` attribute of its frame. Without them `motion.permission()` and `motion.start` fail with the code `unsupported` and `data.missing`.
- **Windows, Linux and the desktop player.** The tooling builds the C++ library of `native/` with CMake against the installed SDK of the engine, whose target `haylen::native` gives it the native API and nlohmann/json, and places it next to the app, and the Lua API loads it. On Windows it calls the Windows Runtime through C++/WinRT, whose headers come with the Windows SDK, and Windows asks the person for none of the sensors. Windows measures the acceleration in units of gravity as the pull toward the ground, so the plugin turns it into meters per second squared of the push that holds the device up, as the other platforms measure it, and the rotation from degrees into radians. The attitude comes from the relative orientation sensor, which fuses the accelerometer and the gyrometer without the compass. A desktop app is in the background while its window is minimized, and the plugin sends no readings then.

## Lua API

```lua
local motion = require('motion')
```

Every reading follows the screen as the app shows it: x points to the right, y to the top and z out of the screen toward the person, so the readings turn with the screen when the app turns to landscape. The readings are `0`, and the attitude is `0, 0, 0, 1`, which turns nothing, until the sensor delivers its first one, and again after the sensors stop.

| Sensor | Reading | Unit |
| --- | --- | --- |
| `'accelerometer'` | The acceleration with gravity, the push that holds the device up, so a device that lies still on a table reads about `9.81` on z. | Meters per second squared. |
| `'gyroscope'` | The rotation rate around each axis, counterclockwise as seen from the end of the axis. | Radians per second. |
| `'attitude'` | The unit quaternion `x, y, z, w` that turns the axes of the screen into a frame whose z points up. The direction it faces around z is the one the device faced when the sensor started. | None. |

### motion.start(options)

Starts the sensors and stops what an earlier start ran. Returns a platform call of `haylen.platform`, whose `await` gives `{sensors}` once the sensors run, or `nil` and the error of the call. The native part asks for the permission `motion` first where the platform gates it. The sensors stop while the app is in the background and start again when it comes back, and they stop with `motion.stop`, with the owner and with the app. The table `options` is optional.

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `sensors` | list | `{'accelerometer'}` | The names of the sensors to run, from `'accelerometer'`, `'gyroscope'` and `'attitude'`. |
| `rate` | number | `60` | The readings per second to ask for, from `1` to `200`. The platform keeps it within what its hardware delivers, and browsers deliver at the rate of the device. |
| `owner` | table or userdata | none | The owner, such as a scene, whose end stops the sensors. Without one they run until `motion.stop` or the end of the app. |

| Code | When |
| --- | --- |
| `'unsupported'` | The device lacks a sensor of `sensors`, such as a computer, a TV or a simulator, with the reason, or the project lacks what the sensors need, which `data.missing` lists. |
| `'denied'` | The person did not allow the motion sensors, with the sentence that says how to ask again. |
| `'failed'` | The browser did not ask the person, since Safari asks only during a tap or a click, with `The browser asks for the motion sensors only during a tap or a click, so ask from one.`, or Windows did not start a sensor, with `Windows did not start the motion sensors: <reason>`. |
| `'cancelled'` | `motion.stop`, a new start or the end of the owner came before the sensors ran. |
| `'invalidParams'` | On the desktops, a call of the native API without the parameters that the Lua API sends. |

Options that are no table raise `The options of the motion sensors must be a table.`, a `sensors` that is no table raises `The option "sensors" of the motion sensors must be a list of sensor names, such as {'accelerometer', 'gyroscope'}.`, an empty `sensors` list raises `The motion sensors need at least one sensor, such as "accelerometer".`, an unknown sensor raises `The motion sensor "compass" does not exist. Use "accelerometer", "gyroscope" or "attitude".`, a rate out of range raises `The rate of the motion sensors must be from 1 to 200 readings per second.`, and an unknown key raises `Unknown option "<key>".`.

```lua
local async = require('async')
local motion = require('motion')
local scene = require('haylen.scene')

scene.push({
    enter = function(self)
        async.spawn(function()
            local started, err = motion.start({sensors = {'accelerometer', 'gyroscope'}, rate = 60, owner = self}):await()
            print(started and 'The sensors run.' or err.code .. ': ' .. err.message)
        end)
    end,
    update = function(self, dt)
        local x = motion.tilt()
        self.speedX = (self.speedX or 0) + x * 400 * dt
    end,
})
```

### motion.stop()

Stops the sensors, and gives up a start that still waits for its answer, which then fails with `'cancelled'`.

```lua
local motion = require('motion')

motion.stop()
```

### motion.sensors()

Returns the list of the sensors that delivered readings since the sensors started, such as `{'accelerometer', 'gyroscope'}`. It is empty while no sensor runs and until the first readings arrive.

```lua
local motion = require('motion')

if #motion.sensors() == 0 then
    print('Waiting for the first readings.')
end
```

### motion.acceleration()

Returns the `x`, `y` and `z` of the acceleration of the device with gravity, in meters per second squared.

```lua
local motion = require('motion')

local x, y, z = motion.acceleration()
if math.sqrt(x * x + y * y + z * z) > 25 then
    print('The player shook the device.')
end
```

### motion.rotationRate()

Returns how fast the device turns around its `x`, `y` and `z` axes, in radians per second.

```lua
local motion = require('motion')

local x, y = motion.rotationRate()
print('Turning at ' .. x .. ', ' .. y .. ' radians per second.')
```

### motion.attitude()

Returns the `x`, `y`, `z` and `w` of the attitude of the device.

```lua
local motion = require('motion')

local x, y, z, w = motion.attitude()
local heading = math.atan(2 * (w * z + x * y), 1 - 2 * (y * y + z * z))
print('Heading in radians: ' .. heading)
```

### motion.tilt()

Returns how far the device leans from level, as the `x` and `y` of a vector up to `1` that follows design space like a stick: `x` grows as the right edge of the screen goes down, and `y` as the bottom edge goes down. A ball that rolls on the screen accelerates by the vector times gravity. A device that lies flat face up is level until `motion.calibrateTilt` takes another way of holding it. The tilt is `0, 0` while the accelerometer does not run. The action map of `haylen.input` reads it through a virtual stick:

```lua
local input = require('haylen.input')
local motion = require('motion')

input.loadActions({actions = {{name = 'roll', type = 'vector', bindings = {'stick:left', 'stick:tilt', 'virtualStick:tilt'}}}})

local function update()
    input.setVirtualStick('tilt', motion.tilt())
    local x, y = input.vector('roll')
    print(x, y)
end
```

### motion.calibrateTilt()

Takes the way the person holds the device now as level, so the tilt reads `0, 0` while they keep holding it that way. Returns `false`, and changes nothing, while the accelerometer has no reading.

```lua
local motion = require('motion')

if motion.calibrateTilt() then
    print('The current angle is level now.')
end
```

### motion.resetTilt()

Makes a device that lies flat face up level again.

```lua
local motion = require('motion')

motion.resetTilt()
```

### motion.permission()

Reads the state of the permission `motion`, as far as the platform tells it, without asking the person. It returns a call of `haylen.platform`, whose `await` gives `'granted'`, `'prompt'`, `'denied'` or `'unknown'`, or `nil` and an error with the code `unsupported` and the reason as `message`, such as `This device has no motion sensors.`, with `data.missing` for a requirement that the project lacks. A platform without the native part of the plugin fails it with the code `noHandler`, as every call of the plugin. Like every platform call, a failure that nothing awaits stops the app.

```lua
local async = require('async')
local motion = require('motion')

async.spawn(function()
    local state, failure = motion.permission():await()
    print(state and 'The permission motion is ' .. state .. '.' or failure.code .. ': ' .. failure.message)
end)
```

### motion.requestPermission()

Asks the person for the permission `motion` with the prompt of the system while the state is `'prompt'`, and returns a call of `haylen.platform`, whose `await` gives the state that the person left. Any other state answers at once, without a prompt. A platform without the sensors, or a project that lacks the `NSMotionUsageDescription` of the `Info.plist`, fails it with the code `unsupported`, the reason as `message` and, for the project, `data.missing`. A start that the person refused fails with the code `denied` and the sentence `The person has not allowed the motion sensors. Ask for it with "motion.requestPermission('motion')", which shows the prompt of the system while the system still asks, or the person allows it in the settings of the system.`.

```lua
local async = require('async')
local motion = require('motion')

async.spawn(function()
    local state, failure = motion.requestPermission():await()
    if failure then
        print(failure.code .. ': ' .. failure.message)
    elseif state == 'granted' then
        motion.start({sensors = {'accelerometer'}})
    end
end)
```

### motion.available

Whether the native part of the plugin runs on this platform, which is `false` on the headless player of the tests.

## Native API

The Lua API holds a session for each start. The native part holds its `watch` call while the sensors run, and stops them when the app gives the call up, which `motion.stop`, the end of the owner and the end of the app do.

| Method or event | Params or payload | Answer |
| --- | --- | --- |
| `motion.watch` | `{session}` | None, since the call stays pending until the app gives it up. The library of macOS and Linux fails it at once with `unsupported`. |
| `motion.start` | `{session, sensors, rate}` | `{sensors}` |
| `motion.permission`, `motion.requestPermission` | `{name}` | The name of the state, or a failure with the code `unsupported`, the reason and `data.missing`, which the Permissions plugin answers on Apple platforms, Android and the web for the permission that the native part registers, and the library of `native/` answers on desktops. |
| `motion.reading` (batched event) | `{session, sensor, x, y, z, w, turns}` in the axes of the device in its natural orientation, with `w` for the attitude alone and `turns`, the quarter turns counterclockwise of the device while the screen keeps the app upright. | |

## What each platform answers

| Platform | `motion.permission()` | `motion.start` |
| --- | --- | --- |
| iOS, iPadOS and visionOS | The authorization of Core Motion from version 27.2, `'prompt'` before the person answered, and `'granted'` on earlier versions. A failure with `unsupported` and `This device has no motion sensors.` on a simulator. | `{sensors}` once Core Motion runs them, `unsupported` for a sensor that the device lacks, such as `The device has no motion sensor "gyroscope".`, and `denied` after a refusal. |
| Mac Catalyst and macOS | A failure with `unsupported` and `A Mac gives apps no readings of motion sensors.` | `unsupported` with the same reason. |
| tvOS | A failure with `unsupported` and `An Apple TV has no motion sensors of its own. The Siri Remote and the controllers report their motion as gamepads, which "input.startGamepadMotion" of "haylen.input" reads.` | `unsupported` with the same reason. |
| Android | `'granted'`, since Android asks for none of them, and a failure with `unsupported` and `This device has no motion sensors.` on a device without any of them. | `{sensors}`, or `unsupported` for a sensor that the device lacks. |
| Web | The prompt of Safari during a tap or a click, which the page keeps until it loads again, the states of `accelerometer` and `gyroscope` in Chromium, and `'granted'` elsewhere. | `{sensors}`, `failed` when Safari did not ask outside a tap, and `unsupported` in a browser without the events. A browser whose device has no sensors fires no events, so `motion.sensors()` stays empty. |
| Windows | `'granted'` on a computer with one of the sensors, since Windows asks for none of them, and a failure with `unsupported` and `This computer has no motion sensors.` on one without them, such as most laptops and desktops. | `{sensors}`, or `unsupported` for a sensor that the computer lacks, such as `The computer has no motion sensor "gyroscope".`. |
| Linux | A failure with `unsupported` and `The Linux desktop gives apps no readings of motion sensors.` | `unsupported` with the same reason. |

## Platforms without the plugin

Every platform of Haylen runs a native part of the plugin, but some systems give apps no readings of motion sensors, so there `motion.start` and `motion.permission()` fail with the code `unsupported` and the reasons of the table above.

| Platform | Reason |
| --- | --- |
| Mac Catalyst, the macOS app and the desktop player of macOS | A Mac has no motion sensors that its system gives apps. |
| tvOS | An Apple TV has no motion sensors of its own, and the Siri Remote and the controllers report their motion as gamepads. |
| Linux | The Linux desktop has no service that gives apps the readings of motion sensors. |

## Sample

The app in `sample/` references the plugin with `"path": ".."` and has a button for every call, with the answer of each one, the newest readings and the tilt, which an action of the action map reads through a virtual stick:

```sh
haylen app run sample
haylen app run sample --target ios-simulator
haylen app run sample --target android
haylen app run sample --target web
haylen app run sample --target windows
```

The UI tests in `sample/ui-tests` answer the prompt of motion where the system shows one, start every sensor at both rates, check that a device at rest reads the gravity of the Earth, calibrate the tilt and check that a rate of 500 per second raises. The iOS simulator has no motion sensors, so there they check that the sensors answer `unsupported`. They run on the simulators, the emulator and devices:

```sh
haylen test --ui sample --target ios-simulator
haylen test --ui sample --target android
haylen test --ui sample --target ios --device <name or UDID>
```

## License

MIT, like Haylen.
