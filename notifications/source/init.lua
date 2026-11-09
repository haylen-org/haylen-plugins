-- Lua API of the Notifications plugin, which an app loads with `require('notifications')`. The native part of each platform schedules, lists and cancels the notifications of the app, and sends the tap on one of them as the event `opened`. The plugin owns the permission `notifications`, which the app checks and asks for with `notifications.permission()` and `notifications.requestPermission()` through the Permissions plugin.
local haylen = require('haylen')
local native = require('haylen.native')
local permissions = require('permissions')
local platform = require('haylen.platform')

local handle = platform.plugin('notifications')
local notifications = {}

local permission = permissions.declare('notifications', {'notifications'})

-- Linux keeps no notification that waits, so the C++ library of `native/` only shows them, and `notifications.linux` waits for them with the event loop of the app. The library and its handlers belong to the process, while the Lua handlers of `notifications.linux` end with the app, so every app that the process runs installs them again.
if haylen.platform == 'linux' then
    if not handle.native then
        native.load('notifications', {init = 'notifications_haylen_init'})
    end
    require('notifications.linux').install(handle)
end

-- Windows keeps the toasts that wait, so the C++ library of `native/` answers every method, and shows the toasts under the identifier of the app, which the shortcut of its installer carries.
if not handle.native and haylen.platform == 'windows' then
    native.load('notifications', {init = 'notifications_haylen_init'})
    handle:send('configure', {identifier = haylen.config.identifier})
end

-- Whether the native part runs on this platform. Without it every call fails with the code `noHandler`.
notifications.available = handle.native

-- Returns a platform call whose `await` gives the state of the permission `notifications`, without asking the person, or `nil` and an error with the code `unsupported` and `data.missing` for a requirement that the project lacks.
notifications.permission = permission.state

-- Returns a platform call whose `await` gives the state of the permission `notifications` that the person left, after the prompt of the system while the state is `prompt`, or `nil` and an error with the code `unsupported` and `data.missing` for a requirement that the project lacks.
notifications.requestPermission = permission.request

local kScheduleKeys = {id = true, title = true, body = true, seconds = true, date = true, sound = true, badge = true, data = true}

local function scheduleParams(options)
    if type(options) ~= 'table' then
        error('The function "notifications.schedule" takes a table of options.', 3)
    end
    for key in pairs(options) do
        if not kScheduleKeys[key] then
            error(string.format('Unknown option "%s".', tostring(key)), 3)
        end
    end

    if type(options.id) ~= 'string' or options.id == '' then
        error('A notification needs an "id" that is a string with at least one character.', 3)
    end
    if type(options.title) ~= 'string' then
        error(string.format('The notification "%s" needs a "title" that is a string.', options.id), 3)
    end
    if options.body ~= nil and type(options.body) ~= 'string' then
        error(string.format('The "body" of the notification "%s" is a string.', options.id), 3)
    end
    if options.sound ~= nil and type(options.sound) ~= 'boolean' then
        error(string.format('The "sound" of the notification "%s" is a boolean.', options.id), 3)
    end
    if options.badge ~= nil and (math.type(options.badge) ~= 'integer' or options.badge < 0) then
        error(string.format('The "badge" of the notification "%s" is an integer of 0 or more.', options.id), 3)
    end

    -- The notification comes after a number of seconds or at a moment, given as a Unix time in seconds such as the one of `os.time()`.
    if (options.seconds == nil) == (options.date == nil) then
        error(string.format('The notification "%s" needs either "seconds" or "date".', options.id), 3)
    end
    if options.seconds ~= nil and (type(options.seconds) ~= 'number' or options.seconds <= 0) then
        error(string.format('The "seconds" of the notification "%s" are a number above 0.', options.id), 3)
    end
    if options.date ~= nil and (type(options.date) ~= 'number' or options.date <= os.time()) then
        error(string.format('The "date" of the notification "%s" is a Unix time in seconds that has not passed yet.', options.id), 3)
    end

    return {id = options.id, title = options.title, body = options.body or '', seconds = options.seconds, date = options.date, sound = options.sound ~= false, badge = options.badge, data = options.data}
end

local function checkId(id, name)
    if type(id) ~= 'string' or id == '' then
        error(string.format('The function "notifications.%s" takes the id of a notification, a string with at least one character.', name), 3)
    end
end

-- Schedules a notification, which replaces a notification of the app with the same id. Returns a platform call whose `await` gives `{id, date}`, with the Unix time in seconds when the notification shows.
function notifications.schedule(options)
    return handle:call('schedule', scheduleParams(options))
end

-- Cancels the notification `id`, whether it still waits or the system already shows it. Returns a platform call whose `await` gives `{}`.
function notifications.cancel(id)
    checkId(id, 'cancel')
    return handle:call('cancel', {id = id})
end

-- Cancels every notification of the app, those that wait and those the system shows. Returns a platform call whose `await` gives `{}`.
function notifications.cancelAll()
    return handle:call('cancelAll', {})
end

-- Returns a platform call whose `await` gives the list of the notifications that wait, each `{id, title, body, date, data}`, in the order of their dates.
function notifications.pending()
    return handle:call('pending', {})
end

-- Returns a platform call whose `await` gives the list of the notifications that the system shows, each `{id, title, body, date, data}` with the date when it showed, in the order of their dates.
function notifications.delivered()
    return handle:call('delivered', {})
end

-- Calls `listener({id, data})` when the person taps a notification of the app, and returns the connection that stops it. The event is retained, so the tap that launched the app reaches the first listener. The table `options` takes the `owner` of the listener.
function notifications.onOpened(listener, options)
    return handle:on('opened', listener, options)
end

return notifications
