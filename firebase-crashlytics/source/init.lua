-- Lua API of the Firebase Crashlytics plugin, which an app loads with `require('firebase-crashlytics')`. It needs the plugin `firebase`. Crashes reach Crashlytics on their own, and so does every Lua error that stops the app unless the parameter `reportLuaErrors` is false.
local platform = require('haylen.platform')

local handle = platform.plugin('firebase-crashlytics')
local crashlytics = {}

-- Whether the native part runs on this platform: iOS and Android.
crashlytics.available = handle.native

-- Adds a line to the log that the next report carries.
function crashlytics.log(message)
    if type(message) ~= 'string' then
        error('The function "crashlytics.log" takes a string.', 2)
    end
    return handle:call('log', {message = message})
end

-- Names the user of the next reports, or clears the name with `nil`.
function crashlytics.setUserId(id)
    if id ~= nil and type(id) ~= 'string' then
        error('The function "crashlytics.setUserId" takes a string or nil.', 2)
    end
    return handle:call('setUserId', {id = id})
end

-- Sets custom keys of the next reports from a table of texts, numbers and flags, such as `{level = 3, mode = 'hard'}`.
function crashlytics.setCustomKeys(keys)
    if type(keys) ~= 'table' then
        error('The function "crashlytics.setCustomKeys" takes a table of keys and values.', 2)
    end
    for key, value in pairs(keys) do
        local kind = type(value)
        if type(key) ~= 'string' or (kind ~= 'string' and kind ~= 'number' and kind ~= 'boolean') then
            error(string.format('The custom key "%s" takes a string, a number or a boolean.', tostring(key)), 2)
        end
    end
    return handle:call('setCustomKeys', keys)
end

-- Records a non-fatal error with its message and, optionally, the frames of its stack, a list of `{source, line, function}` tables from the innermost call outward.
function crashlytics.recordError(message, frames)
    if type(message) ~= 'string' then
        error('The function "crashlytics.recordError" takes the message of the error as a string.', 2)
    end
    if frames ~= nil and type(frames) ~= 'table' then
        error('The frames of the error are a list of {source, line, function} tables.', 2)
    end
    for index, frame in ipairs(frames or {}) do
        if type(frame) ~= 'table' or type(frame.source) ~= 'string' or math.type(frame.line) ~= 'integer' then
            error(string.format('The frame %d of the error needs a "source" string and a "line" integer.', index), 2)
        end
    end
    return handle:call('recordError', {message = message, frames = frames})
end

-- Turns the reports of this device on or off. Returns a platform call whose `await` gives `{enabled}`.
function crashlytics.setCollectionEnabled(enabled)
    if type(enabled) ~= 'boolean' then
        error('The function "crashlytics.setCollectionEnabled" takes a boolean.', 2)
    end
    return handle:call('setCollectionEnabled', {enabled = enabled})
end

-- Returns a platform call whose `await` gives `{crashed}`, whether the previous run of the app crashed.
function crashlytics.didCrashOnPreviousExecution()
    return handle:call('didCrashOnPreviousExecution')
end

-- Sends the reports that wait while the collection is off. Returns a platform call whose `await` gives `{sent}`.
function crashlytics.sendUnsentReports()
    return handle:call('sendUnsentReports')
end

-- Deletes the reports that wait while the collection is off. Returns a platform call whose `await` gives `{deleted}`.
function crashlytics.deleteUnsentReports()
    return handle:call('deleteUnsentReports')
end

-- Crashes the app half a second after the answer, so a project checks that its crashes reach Crashlytics.
function crashlytics.crash()
    return handle:call('crash')
end

return crashlytics
