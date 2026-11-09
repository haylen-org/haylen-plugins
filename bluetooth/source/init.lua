-- Lua API of the Bluetooth plugin, which an app loads with `require('bluetooth')`. The app is a central of Bluetooth Low Energy: it scans for devices, connects to them, finds their services and characteristics, reads and writes their values as bytes and hears the values that they notify. The app checks and asks for the permission `bluetooth` with `bluetooth.permission()` and `bluetooth.requestPermission()`, which the Permissions plugin answers.
local haylen = require('haylen')
local native = require('haylen.native')
local permissions = require('permissions')
local platform = require('haylen.platform')
local scene = require('haylen.scene')

local handle = platform.plugin('bluetooth')
local bluetooth = {}

local kDesktops = {windows = true, linux = true}

-- Apple platforms, Android and the web load their native parts before any Lua runs. The Windows and Linux apps run the library of `native/`, which the tooling places next to them and which declares itself the native part of the plugin in its init function, once per process.
if not handle.native and kDesktops[haylen.platform] then
    native.load('bluetooth', {init = 'bluetooth_haylen_init'})
end

-- Whether the native part runs on this platform. Without it every call fails with the code `noHandler`.
bluetooth.available = handle.native

local permission = permissions.declare('bluetooth', {'bluetooth'})

-- Returns a platform call whose `await` gives the state of the permission `bluetooth`, without asking the person, or `nil` and an error with the code `unsupported`, the reason and `data.missing` for a requirement that the project lacks.
bluetooth.permission = permission.state

-- Returns a platform call whose `await` gives the state of the permission `bluetooth` that the person left, after the prompt of the system while the state is `prompt`, or `nil` and an error with the code `unsupported`, the reason and `data.missing` for a requirement that the project lacks.
bluetooth.requestPermission = permission.request

-- The base of the UUIDs that the Bluetooth SIG assigns, which a short UUID of 4 or 8 hexadecimal digits fills in.
local kBase = '-0000-1000-8000-00805f9b34fb'

-- Every UUID crosses the bridge in its full form in lowercase, which every platform answers with too.
local function uuid(value, what, level)
    if type(value) ~= 'string' then
        error(string.format('The %s is a UUID string, such as "180d" or "0000180d-0000-1000-8000-00805f9b34fb".', what), level)
    end

    local lower = value:lower()
    if lower:match('^%x%x%x%x$') then
        return '0000' .. lower .. kBase
    end
    if lower:match('^%x%x%x%x%x%x%x%x$') then
        return lower .. kBase
    end
    if lower:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$') then
        return lower
    end

    error(string.format('The %s "%s" is not a UUID. Give 4 or 8 hexadecimal digits, or the full form such as "0000180d-0000-1000-8000-00805f9b34fb".', what, value), level)
end

local function deviceId(id, name, level)
    if type(id) ~= 'string' or id == '' then
        error(string.format('The function "bluetooth.%s" takes the id of a device, a string that "onFound" gives.', name), level)
    end

    return id
end

local function checkKeys(options, keys, name)
    if options == nil then
        return {}
    end

    if type(options) ~= 'table' then
        error(string.format('The options of "bluetooth.%s" are a table.', name), 3)
    end

    for key in pairs(options) do
        if not keys[key] then
            error(string.format('Unknown option "%s".', tostring(key)), 3)
        end
    end

    return options
end

local function target(id, service, characteristic, name)
    return {id = deviceId(id, name, 4), service = uuid(service, 'service', 4), characteristic = uuid(characteristic, 'characteristic', 4)}
end

local kScanKeys = {services = true, seconds = true, owner = true}

-- Scans for devices that advertise, and returns a platform call whose `await` gives `{}` once the scan ends: after `seconds`, 10 by default, after `bluetooth.stopScan()`, or when its `owner` ends. The devices reach the listeners of `onFound`. On the web the browser shows its chooser instead, as the README describes.
function bluetooth.scan(options)
    options = checkKeys(options, kScanKeys, 'scan')

    if options.services ~= nil and type(options.services) ~= 'table' then
        error('The "services" of a scan are a list of UUIDs.', 2)
    end
    local services = {}
    for index, service in ipairs(options.services or {}) do
        services[index] = uuid(service, 'service', 3)
    end

    local seconds = options.seconds or 10
    if type(seconds) ~= 'number' or seconds ~= seconds or seconds <= 0 then
        error('The "seconds" of a scan are a number above 0.', 2)
    end

    local call = handle:call('scan', {services = services, seconds = seconds})

    -- The task of the owner ends with it, and its to-be-closed variable then cancels the call, which stops the scan.
    if options.owner ~= nil then
        scene.spawn(options.owner, function()
            local scanning <close> = setmetatable({}, {__close = function() call:cancel() end})
            call:await()
        end)
    end

    return call
end

-- Stops the scan that runs, whose call then gives `{}`. Returns a platform call whose `await` gives `{}`.
function bluetooth.stopScan()
    return handle:call('stopScan', {})
end

local kConnectKeys = {timeout = true}

-- Connects to the device `id` and returns a platform call whose `await` gives `{id, name}`. The option `timeout` gives up after its seconds, which also stops the attempt.
function bluetooth.connect(id, options)
    options = checkKeys(options, kConnectKeys, 'connect')
    return handle:call('connect', {id = deviceId(id, 'connect', 3)}, {timeout = options.timeout})
end

-- Disconnects from the device `id`. Returns a platform call whose `await` gives `{}`.
function bluetooth.disconnect(id)
    return handle:call('disconnect', {id = deviceId(id, 'disconnect', 3)})
end

-- Returns a platform call whose `await` gives the list of the UUIDs of the services of the connected device `id`.
function bluetooth.services(id)
    return handle:call('services', {id = deviceId(id, 'services', 3)})
end

-- Returns a platform call whose `await` gives the list of the characteristics of a service of the connected device `id`, each `{uuid, properties}`, where `properties` lists `'read'`, `'write'`, `'writeWithoutResponse'`, `'notify'` and `'indicate'`.
function bluetooth.characteristics(id, service)
    return handle:call('characteristics', {id = deviceId(id, 'characteristics', 3), service = uuid(service, 'service', 3)})
end

-- Reads a characteristic and returns a platform call whose `await` gives `{value}`, with the value as a string of bytes.
function bluetooth.read(id, service, characteristic)
    return handle:call('read', target(id, service, characteristic, 'read'))
end

local kWriteKeys = {response = true}

-- Writes the string of bytes `bytes` into a characteristic. The option `response`, `true` by default, waits for the device to confirm the write, and `false` writes without a response. Returns a platform call whose `await` gives `{}`.
function bluetooth.write(id, service, characteristic, bytes, options)
    options = checkKeys(options, kWriteKeys, 'write')

    if type(bytes) ~= 'string' then
        error('The function "bluetooth.write" takes the value as a string of bytes.', 2)
    end
    if options.response ~= nil and type(options.response) ~= 'boolean' then
        error('The option "response" of "bluetooth.write" is a boolean.', 2)
    end

    local params = target(id, service, characteristic, 'write')
    params.value = platform.bytes(bytes)
    params.response = options.response ~= false

    return handle:call('write', params)
end

-- Turns on the notifications or indications of a characteristic, whose values reach the listeners of `onChanged`. Returns a platform call whose `await` gives `{}`.
function bluetooth.subscribe(id, service, characteristic)
    return handle:call('subscribe', target(id, service, characteristic, 'subscribe'))
end

-- Turns the notifications of a characteristic off. Returns a platform call whose `await` gives `{}`.
function bluetooth.unsubscribe(id, service, characteristic)
    return handle:call('unsubscribe', target(id, service, characteristic, 'unsubscribe'))
end

-- Calls `listener(devices)` once per frame with the list of the devices that the scan found since the frame before, each `{id, name, rssi, services, manufacturerData}`, and returns the connection that stops it.
function bluetooth.onFound(listener, options)
    return handle:on('found', listener, options)
end

-- Calls `listener(changes)` once per frame with the list of the values that subscribed characteristics notified since the frame before, each `{id, service, characteristic, value}`, and returns the connection that stops it.
function bluetooth.onChanged(listener, options)
    return handle:on('changed', listener, options)
end

-- Calls `listener({id, reason})` when a connected device disconnects, whether the app, the device or the radio ended the connection, and returns the connection that stops it.
function bluetooth.onDisconnected(listener, options)
    return handle:on('disconnected', listener, options)
end

return bluetooth
