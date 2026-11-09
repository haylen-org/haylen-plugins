-- Lua API of the Microphone plugin, which an app loads with `require('microphone')`. The native part of each platform records the microphone into an audio stream and answers the permission `microphone`, which the app checks and asks for with `microphone.permission()` and `microphone.requestPermission()` through the Permissions plugin.
local async = require('async')
local collections = require('haylen.collections')
local haylen = require('haylen')
local native = require('haylen.native')
local permissions = require('permissions')
local platform = require('haylen.platform')
local scene = require('haylen.scene')

local handle = platform.plugin('microphone')
local microphone = {}

local permission = permissions.declare('microphone', {'microphone'})

local kDesktops = {macos = true, windows = true, linux = true}
local kDefaultRate = 48000
local kLevelFrames = 1024

-- Apple platforms, Android and the web load their native parts before any Lua runs. The desktop player and the Windows and Linux apps run the library of `native/`, which the tooling places next to them and which declares itself the native part of the plugin in its init function, once per process.
if not handle.native and kDesktops[haylen.platform] then
    native.load('microphone', {init = 'microphone_haylen_init'})
end

-- The recording belongs to the process, so the module of every app that starts, such as one that restarted, stops what an earlier app left running.
handle:send('reset')

-- A stream keeps the rate it opened with, so the native part opens one stream for each rate, named after it.
local streamName = nil
local levelSamples = collections.newFloatBuffer(kLevelFrames)

-- Resolves the wait of the task that ties the running recording to its owner.
local releaseOwner = nil

local function release()
    local resolve = releaseOwner
    releaseOwner = nil
    if resolve then
        resolve()
    end
end

-- Returns the guard that the task of an owner closes as it ends, which stops the recording while `resolve` still ties it to that owner.
local function guardRecording(resolve)
    return setmetatable({}, {__close = function()
        if releaseOwner == resolve then
            releaseOwner = nil
            handle:send('stop')
        end
    end})
end

-- Runs a task that the owner holds, whose end stops the recording: the owner ends the task, which closes its guard, while a stop or another start resolves its wait first.
local function tie(owner)
    release()
    if owner == nil then
        return
    end

    local released, resolve = async.deferred()
    releaseOwner = resolve
    scene.spawn(owner, function()
        local guard <close> = guardRecording(resolve)
        released:await()
    end)
end

-- Starts the microphone, whose mono samples at `options.sampleRate`, 48000 by default, reach the audio stream of `microphone.stream()`, and `options.owner` ends the recording together with itself. Returns a platform call whose `await` gives `{sampleRate, channels, stream}`.
function microphone.start(options)
    options = options or {}
    for key in pairs(options) do
        if key ~= 'sampleRate' and key ~= 'owner' then
            error('Unknown option "' .. tostring(key) .. '".', 2)
        end
    end
    local sampleRate = options.sampleRate or kDefaultRate
    if math.type(sampleRate) ~= 'integer' or sampleRate < 8000 or sampleRate > 192000 then
        error('The option "sampleRate" of "microphone.start" is an integer of hertz from 8000 to 192000.', 2)
    end
    if options.owner ~= nil and type(options.owner) ~= 'table' and type(options.owner) ~= 'userdata' then
        error('An owner must be a table or a userdata, not ' .. type(options.owner) .. '.', 2)
    end

    streamName = 'microphone-' .. sampleRate
    local call = handle:call('start', {sampleRate = sampleRate})
    tie(options.owner)
    return call
end

-- Stops the microphone. Returns a platform call.
function microphone.stop()
    release()
    return handle:call('stop', {})
end

-- Returns the audio stream of the last start, which plays as a voice with `stream:play()` and copies its newest samples with `stream:read(buffer)`, or `nil` until the native part opened it.
function microphone.stream()
    return streamName and handle:audioStream(streamName)
end

-- Returns the level of the newest samples of the microphone, the root mean square and the peak of up to 1024 samples from 0 to 1, or 0 and 0 while nothing arrived.
function microphone.level()
    local stream = microphone.stream()
    if not stream then
        return 0, 0
    end
    local count = stream:read(levelSamples)
    if count == 0 then
        return 0, 0
    end

    local squares = 0
    local peak = 0
    for index = 1, count do
        local sample = levelSamples[index]
        squares = squares + sample * sample
        peak = math.max(peak, math.abs(sample))
    end
    -- A converter that changes the rate may overshoot full scale a little, which the level shows as full scale.
    return math.min(math.sqrt(squares / count), 1), math.min(peak, 1)
end

-- Calls `listener({message, code})` when the recording stops by itself, such as when the input of the device changes, and returns the connection of the listener. The table `options` takes `owner`.
function microphone.onStopped(listener, options)
    return handle:on('stopped', listener, options)
end

-- Returns a platform call whose `await` gives the state of the permission `microphone`, without asking the person, or `nil` and an error with the code `unsupported` and `data.missing`. The name is optional, since the plugin owns one permission.
microphone.permission = permission.state

-- Returns a platform call whose `await` gives the state of the permission `microphone` that the person left, after the prompt of the system while the state is `prompt`, or `nil` and an error with the code `unsupported` and `data.missing`. The name is optional, since the plugin owns one permission.
microphone.requestPermission = permission.request

return microphone
