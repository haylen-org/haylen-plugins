-- Lua API of the Local Network plugin, which an app loads with `require('local-network')`. The native part of each platform answers the permission `localNetwork`, which the plugin declares to the Permissions plugin, shows the picker of the services of the local network and advertises a service of the app.
local async = require('async')
local haylen = require('haylen')
local permissions = require('permissions')
local platform = require('haylen.platform')
local scene = require('haylen.scene')

local handle = platform.plugin('local-network')
local localNetwork = {}

local permission = permissions.declare('local-network', {'localNetwork'})

local kApple = {ios = true, tvos = true, macos = true}

-- The advertisement belongs to the process, so the module of every app that starts, such as one that restarted, stops what an earlier app left advertised.
handle:send('reset')

-- Resolves the wait of the task that ties the advertisement to its owner.
local releaseOwner = nil

local function release()
    local resolve = releaseOwner
    releaseOwner = nil

    if resolve then
        resolve()
    end
end

-- Runs a task that the owner holds, whose end stops the advertisement: the owner ends the task, which closes its guard, while a stop or another advertisement resolves its wait first.
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
                handle:send('stopAdvertising')
            end
        end})
        released:await()
    end)
end

-- A service type of DNS-SD is two labels, the name of the service and its transport, such as `_my-game._tcp`.
local function checkType(serviceType, name)
    if type(serviceType) ~= 'string' then
        error(string.format('The function "%s" takes a service type, such as "_my-game._tcp", not a %s.', name, type(serviceType)), 3)
    end

    local service, transport = serviceType:match('^_([%w%-]+)%._(%a+)$')
    if service == nil or #service > 15 or (transport ~= 'tcp' and transport ~= 'udp') then
        error(string.format('The service type "%s" is not a type of DNS-SD. A type is "_" and a name of at most 15 letters, digits and dashes, then "._tcp" or "._udp", such as "_my-game._tcp".', serviceType), 3)
    end
end

-- Returns the platform call of the plugin whose `await` gives the state of the permission `localNetwork`, without asking the person, or `nil` and an error with the code `unsupported` and `data.missing`.
localNetwork.permission = permission.state

-- Returns the platform call of the plugin whose `await` gives the state of the permission `localNetwork` that the person left, after the prompt of the system while the state is `prompt`, or `nil` and an error with the code `unsupported` and `data.missing`.
localNetwork.requestPermission = permission.request

-- Shows the picker of the services of the type `serviceType` on the local network, such as `_my-game._tcp`, and returns a platform call whose `await` gives the service that the person picks, `{name, type, host, port, addresses}`. It fails with the code `cancelled` when the person closes the picker. On Android the picker of the system hands the app the service without the permission `localNetwork`, and on Apple platforms the plugin shows its own list of the services that it finds.
function localNetwork.pickService(serviceType)
    checkType(serviceType, 'localNetwork.pickService')

    if kApple[haylen.platform] then
        return handle:openScreen('servicePicker', {type = serviceType}, {opaque = false})
    end
    return handle:call('pickService', {type = serviceType})
end

-- Advertises a service of the app on the local network, the type `type`, the name `name` that people see and the `port` where the app listens, such as the port of a listener of the module `socket`, until `localNetwork.stopAdvertising` or the end of `options.owner`. A new advertisement replaces the one before. Returns a platform call whose `await` gives `{name, type, port}`, where the name is the one the network took, which differs from `name` when another service of the network holds it.
function localNetwork.advertise(options)
    if type(options) ~= 'table' then
        error('The function "localNetwork.advertise" takes a table with "type", "name" and "port".', 2)
    end
    for key in pairs(options) do
        if key ~= 'type' and key ~= 'name' and key ~= 'port' and key ~= 'owner' then
            error('Unknown option "' .. tostring(key) .. '".', 2)
        end
    end

    checkType(options.type, 'localNetwork.advertise')
    if type(options.name) ~= 'string' or options.name == '' or #options.name > 63 then
        error('The option "name" of "localNetwork.advertise" is the name that people see, a text of 1 to 63 bytes.', 2)
    end
    if math.type(options.port) ~= 'integer' or options.port < 1 or options.port > 65535 then
        error('The option "port" of "localNetwork.advertise" is a port number from 1 to 65535.', 2)
    end
    if options.owner ~= nil and type(options.owner) ~= 'table' and type(options.owner) ~= 'userdata' then
        error('An owner must be a table or a userdata, not ' .. type(options.owner) .. '.', 2)
    end

    local call = handle:call('advertise', {type = options.type, name = options.name, port = options.port})
    tie(options.owner)
    return call
end

-- Stops the advertisement of the app. Returns a platform call.
function localNetwork.stopAdvertising()
    release()
    return handle:call('stopAdvertising', {})
end

return localNetwork
