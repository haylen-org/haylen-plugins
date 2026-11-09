-- Lua API of the Camera plugin, which an app loads with `require('camera')`. The native part of each platform captures the camera into the video stream `camera` and answers the permission `camera`, which the app checks and asks for with `camera.permission()` and `camera.requestPermission()` through the Permissions plugin.
local async = require('async')
local haylen = require('haylen')
local native = require('haylen.native')
local permissions = require('permissions')
local platform = require('haylen.platform')
local scene = require('haylen.scene')

local handle = platform.plugin('camera')
local camera = {}

local permission = permissions.declare('camera', {'camera'})

local kDesktops = {macos = true, windows = true, linux = true}
local kFacings = {front = true, back = true, external = true}
local kDefaultWidth = 640
local kDefaultHeight = 480

-- Apple platforms, Android and the web load their native parts before any Lua runs. The desktop player and the Windows and Linux apps run the library of `native/`, which the tooling places next to them and which declares itself the native part of the plugin in its init function, once per process.
if not handle.native and kDesktops[haylen.platform] then
    native.load('camera', {init = 'camera_haylen_init'})
end

-- The capture belongs to the process, so the module of every app that starts, such as one that restarted, stops what an earlier app left running.
handle:send('reset')

-- Resolves the wait of the task that ties the running capture to its owner.
local releaseOwner = nil

local function release()
    local resolve = releaseOwner
    releaseOwner = nil
    if resolve then
        resolve()
    end
end

-- Returns the guard that the task of an owner closes as it ends, which stops the capture while `resolve` still ties it to that owner.
local function guardCapture(resolve)
    return setmetatable({}, {__close = function()
        if releaseOwner == resolve then
            releaseOwner = nil
            handle:send('stop')
        end
    end})
end

-- Runs a task that the owner holds, whose end stops the capture: the owner ends the task, which closes its guard, while a stop or another start resolves its wait first.
local function tie(owner)
    release()
    if owner == nil then
        return
    end

    local released, resolve = async.deferred()
    releaseOwner = resolve
    scene.spawn(owner, function()
        local guard <close> = guardCapture(resolve)
        released:await()
    end)
end

local function readSize(options, key, default)
    local value = options[key]
    if value == nil then
        return default
    end
    if math.type(value) ~= 'integer' or value <= 0 then
        error('The option "' .. key .. '" of "camera.start" is a positive integer of pixels.', 3)
    end
    return value
end

-- Returns a platform call whose `await` gives the list of the cameras, each `{id, name, facing}`, after it asked for the permission `camera` where the app does not hold it yet.
function camera.cameras()
    return handle:call('cameras', {})
end

-- Starts the camera that `options.camera` names by its id, the first one that faces `options.facing`, or the default camera of the system, at the size of its format closest to `options.width` by `options.height`. The frames reach the video stream of `camera.stream()`, and `options.owner` ends the capture together with itself. Returns a platform call whose `await` gives `{id, name, facing, width, height}`.
function camera.start(options)
    options = options or {}
    for key in pairs(options) do
        if key ~= 'camera' and key ~= 'facing' and key ~= 'width' and key ~= 'height' and key ~= 'owner' then
            error('Unknown option "' .. tostring(key) .. '".', 2)
        end
    end
    if options.camera ~= nil and type(options.camera) ~= 'string' then
        error('The option "camera" of "camera.start" is the id of a camera that "camera.cameras" lists.', 2)
    end
    if options.facing ~= nil and not kFacings[options.facing] then
        error('The option "facing" of "camera.start" is "front", "back" or "external", not "' .. tostring(options.facing) .. '".', 2)
    end
    if options.camera ~= nil and options.facing ~= nil then
        error('The options "camera" and "facing" of "camera.start" exclude each other.', 2)
    end
    if options.owner ~= nil and type(options.owner) ~= 'table' and type(options.owner) ~= 'userdata' then
        error('An owner must be a table or a userdata, not ' .. type(options.owner) .. '.', 2)
    end

    local params = {camera = options.camera, facing = options.facing, width = readSize(options, 'width', kDefaultWidth), height = readSize(options, 'height', kDefaultHeight)}
    local call = handle:call('start', params)
    tie(options.owner)
    return call
end

-- Stops the camera. Returns a platform call.
function camera.stop()
    release()
    return handle:call('stop', {})
end

-- Returns the video stream of the camera, whose `texture` draws the newest frame, or `nil` until a camera started once in the process.
function camera.stream()
    return handle:videoStream('camera')
end

-- Takes a photo from the newest frame of the camera. Returns a platform call whose `await` gives `{jpeg, width, height}`, with the bytes of a JPEG file in `jpeg`.
function camera.takePhoto()
    return handle:call('takePhoto', {})
end

-- Calls `listener({message, code})` when the camera stops by itself, such as when the system takes it away, and returns the connection of the listener. The table `options` takes `owner`.
function camera.onStopped(listener, options)
    return handle:on('stopped', listener, options)
end

-- Returns a platform call whose `await` gives the state of the permission `camera`, without asking the person, or `nil` and an error with the code `unsupported` and `data.missing`. The name is optional, since the plugin owns one permission.
camera.permission = permission.state

-- Returns a platform call whose `await` gives the state of the permission `camera` that the person left, after the prompt of the system while the state is `prompt`, or `nil` and an error with the code `unsupported` and `data.missing`. The name is optional, since the plugin owns one permission.
camera.requestPermission = permission.request

return camera
