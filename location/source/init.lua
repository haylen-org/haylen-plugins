-- Lua API of the Location plugin, which an app loads with `require('location')`. The native part of each platform reads the location of the device and answers the permissions `location`, `preciseLocation` and `backgroundLocation`, which the plugin declares to the Permissions plugin.
local async = require('async')
local haylen = require('haylen')
local native = require('haylen.native')
local permissions = require('permissions')
local platform = require('haylen.platform')
local scene = require('haylen.scene')

local handle = platform.plugin('location')
local location = {}

local permission = permissions.declare('location', {'location', 'preciseLocation', 'backgroundLocation'})

local kDesktops = {macos = true, windows = true, linux = true}
local kDefaultTimeout = 30

-- GeoClue of Linux asks the person in the name of the desktop entry of the app, which the Linux project names after the identifier of the app.
local kDesktopId = haylen.platform == 'linux' and haylen.config.identifier or nil

-- Apple platforms, Android and the web load their native parts before any Lua runs. The desktop player and the Windows and Linux apps run the library of `native/`, which the tooling places next to them and which declares itself the native part of the plugin in its init function, once per process.
if not handle.native and kDesktops[haylen.platform] then
    native.load('location', {init = 'location_haylen_init'})
end

-- The updates belong to the process, so the module of every app that starts, such as one that restarted, stops what an earlier app left running.
handle:send('reset')

-- Resolves the wait of the task that ties the running updates to their owner.
local releaseOwner = nil

local function release()
    local resolve = releaseOwner
    releaseOwner = nil

    if resolve then
        resolve()
    end
end

-- Runs a task that the owner holds, whose end stops the updates: the owner ends the task, which closes its guard, while a stop or another watch resolves its wait first.
local function tie(owner)
    release()
    if owner == nil then
        return
    end

    local released, resolve = async.deferred()
    releaseOwner = resolve
    scene.spawn(owner, function()
        local guard <close> = setmetatable({}, {__close = function()
            if releaseOwner == resolve then
                releaseOwner = nil
                handle:send('stop')
            end
        end})
        released:await()
    end)
end

local function checkOptions(options, allowed, name)
    if type(options) ~= 'table' then
        error('The options of "' .. name .. '" are a table.', 3)
    end

    for key in pairs(options) do
        if not allowed[key] then
            error('Unknown option "' .. tostring(key) .. '".', 3)
        end
    end

    if options.precise ~= nil and type(options.precise) ~= 'boolean' then
        error('The option "precise" of "' .. name .. '" is a boolean.', 3)
    end
end

-- Asks for one fix of the location, precise when `options.precise` is true, which fails with the code `timeout` once `options.timeout` seconds pass without one, 30 by default. Returns a platform call whose `await` gives a place, `{latitude, longitude, accuracy, altitude, speed, heading, timestamp}`.
function location.current(options)
    options = options or {}
    checkOptions(options, {precise = true, timeout = true}, 'location.current')

    local timeout = options.timeout or kDefaultTimeout
    if type(timeout) ~= 'number' or timeout <= 0 then
        error('The option "timeout" of "location.current" is a positive number of seconds.', 2)
    end

    return handle:call('current', {precise = options.precise == true, timeout = timeout, desktopId = kDesktopId})
end

-- Starts the updates of the location, which reach the listeners of `location.onChanged` once the device moved `options.distance` meters, 0 by default, precise when `options.precise` is true and also while the app is in the background when `options.background` is true. The table `options` takes `owner`, whose end stops the updates. Returns a platform call that resolves once the updates run.
function location.watch(options)
    options = options or {}
    checkOptions(options, {distance = true, precise = true, background = true, owner = true}, 'location.watch')

    local distance = options.distance or 0
    if type(distance) ~= 'number' or distance < 0 then
        error('The option "distance" of "location.watch" is a number of meters, 0 or more.', 2)
    end

    if options.background ~= nil and type(options.background) ~= 'boolean' then
        error('The option "background" of "location.watch" is a boolean.', 2)
    end

    if options.owner ~= nil and type(options.owner) ~= 'table' and type(options.owner) ~= 'userdata' then
        error('An owner must be a table or a userdata, not ' .. type(options.owner) .. '.', 2)
    end

    local call = handle:call('watch', {distance = distance, precise = options.precise == true, background = options.background == true, desktopId = kDesktopId})
    tie(options.owner)
    return call
end

-- Stops the updates of the location. Returns a platform call.
function location.stop()
    release()
    return handle:call('stop', {})
end

-- Returns the platform call of the plugin whose `await` gives the state of the permission `name`, `location`, `preciseLocation` or `backgroundLocation`, without asking the person, or `nil` and an error with the code `unsupported` and `data.missing`.
location.permission = permission.state

-- Returns the platform call of the plugin whose `await` gives the state of the permission `name`, `location`, `preciseLocation` or `backgroundLocation`, that the person left after the prompt of the system, or `nil` and an error with the code `unsupported` and `data.missing`.
location.requestPermission = permission.request

-- Calls `listener(places)` once per frame with the list of the places that arrived since the frame before, oldest first, and returns the connection of the listener. The table `options` takes `owner`.
function location.onChanged(listener, options)
    return handle:on('changed', listener, options)
end

-- Calls `listener({message, code})` when the updates stop by themselves, such as when the person takes the permission back or turns the location off, and returns the connection of the listener. The table `options` takes `owner`.
function location.onStopped(listener, options)
    return handle:on('stopped', listener, options)
end

return location
