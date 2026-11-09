-- The notifications of Linux. The notification server of the desktop, which owns `org.freedesktop.Notifications` on the session bus, shows a notification at once and keeps none that waits. So this module answers the methods of the plugin in Lua: it waits for each notification with the event loop of the app, while the app runs, and hands it to the C++ library of `native/`, which shows it through the server and reports the taps and the closes of the person.
local async = require('async')
local datetime = require('datetime')
local haylen = require('haylen')
local log = require('haylen.log')
local platform = require('haylen.platform')

local linux = {}

local function now()
    return datetime.now():millis() / 1000
end

local function describe(notification)
    return {id = notification.id, title = notification.title, body = notification.body, date = notification.date, data = notification.data}
end

local function byDate(entries)
    local list = {}
    for _, entry in pairs(entries) do
        list[#list + 1] = describe(entry.notification)
    end
    table.sort(list, function(a, b) return a.date < b.date end)
    return list
end

-- Answers the methods of the plugin with Lua handlers, which go before the native handlers, and turns the events of the C++ library into the `opened` event of the plugin.
function linux.install(handle)
    local waiting = {}
    local shown = {}
    local idsOfServer = {}

    -- The C++ library reads the texts of a notification from the byte buffers of the call in their order. The identifier of the app names its desktop entry, which the Linux project installs.
    local function show(notification)
        local method = notification.sound and 'show' or 'showSilent'
        local texts = {platform.bytes(notification.title), platform.bytes(notification.body), platform.bytes(haylen.config.name), platform.bytes(haylen.config.identifier)}
        local answer, err = handle:call(method, texts):await()
        if not answer then
            log.warning(string.format('The notification "%s" did not show: %s', notification.id, err.message))
            return
        end
        notification.date = now()
        shown[notification.id] = {notification = notification, serverId = answer.serverId}
        idsOfServer[answer.serverId] = notification.id
    end

    local function forget(id)
        local entry = waiting[id]
        if entry then
            entry.task.cancel()
            waiting[id] = nil
        end

        local showing = shown[id]
        if showing then
            idsOfServer[showing.serverId] = nil
            shown[id] = nil
            handle:send('close', {showing.serverId})
        end
    end

    platform.registerHandler('notifications.schedule', function(params)
        forget(params.id)
        local date = params.date or now() + params.seconds
        local notification = {id = params.id, title = params.title, body = params.body, date = date, sound = params.sound, data = params.data}
        local task = async.spawn(function()
            async.sleep(math.max(0, date - now()) * 1000):await()
            waiting[notification.id] = nil
            show(notification)
        end)
        waiting[notification.id] = {notification = notification, task = task}
        return {id = notification.id, date = date}
    end)

    platform.registerHandler('notifications.cancel', function(params)
        forget(params.id)
        return {}
    end)

    platform.registerHandler('notifications.cancelAll', function()
        local ids = {}
        for id in pairs(waiting) do
            ids[#ids + 1] = id
        end
        for id in pairs(shown) do
            ids[#ids + 1] = id
        end
        for _, id in ipairs(ids) do
            forget(id)
        end
        return {}
    end)

    platform.registerHandler('notifications.pending', function()
        return byDate(waiting)
    end)

    platform.registerHandler('notifications.delivered', function()
        return byDate(shown)
    end)

    handle:on('activated', function(event)
        local id = idsOfServer[event.serverId]
        if id then
            platform.emit('notifications.opened', {id = id, data = shown[id].notification.data}, {retain = true})
        end
    end)

    handle:on('closed', function(event)
        local id = idsOfServer[event.serverId]
        if id then
            idsOfServer[event.serverId] = nil
            shown[id] = nil
        end
    end)
end

return linux
