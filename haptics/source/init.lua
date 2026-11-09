-- Lua API of the Haptics plugin, which an app loads with `require('haptics')`. It vibrates the device and plays the feedback of its haptic engine, and answers why where the device has neither.
local haylen = require('haylen')
local log = require('haylen.log')
local native = require('haylen.native')
local platform = require('haylen.platform')

local handle = platform.plugin('haptics')
local haptics = {}

local kDesktops = {macos = true, windows = true, linux = true}
local kStrengths = {light = true, medium = true, heavy = true}
local kNotifications = {success = true, warning = true, error = true}

-- The sentences of the refusals that the plugin logged, once each.
local logged = {}

-- Apple platforms, Android and the web load their native parts before any Lua runs. The desktop player and the Windows and Linux apps run the C++ library of `native/`, which declares itself the native part of the plugin in its init function, once per process.
if not handle.native and kDesktops[haylen.platform] then
    native.load('haptics', {init = 'haptics_haylen_init'})
end

local function logRefusal(message)
    if logged[message] then
        return
    end

    logged[message] = true
    log.warning(message)
end

-- Feedback often plays on its own, such as on every hit, so a refusal that nothing awaits is logged once and never stops the app.
local function play(method, params)
    local call = handle:call(method, params)
    call.promise:catch(logRefusal)
    return call
end

-- Vibrates the device for `seconds`. Returns a platform call, whose `await` gives `true` once the device vibrated, or `nil` and an error with the code `unsupported` or `denied` and the reason.
function haptics.vibrate(seconds)
    if type(seconds) ~= 'number' or seconds ~= seconds or seconds <= 0 or seconds == math.huge then
        error('A vibration lasts a positive number of seconds.', 2)
    end

    return play('vibrate', {seconds = seconds})
end

-- Plays the tap of a light, medium or heavy impact on the haptic engine, `'medium'` by default, such as when two objects collide.
function haptics.impact(strength)
    strength = strength or 'medium'

    if not kStrengths[strength] then
        error(string.format('The strength of an impact is "light", "medium" or "heavy", not "%s".', tostring(strength)), 2)
    end

    return play('impact', {strength = strength})
end

-- Plays the light tick of a selection that changes, such as the value of a picker.
function haptics.selection()
    return play('selection', {})
end

-- Plays the feedback of a task that ended with a success, a warning or an error.
function haptics.notification(kind)
    if not kNotifications[kind] then
        error(string.format('The kind of a notification is "success", "warning" or "error", not "%s".', tostring(kind)), 2)
    end

    return play('notification', {kind = kind})
end

return haptics
