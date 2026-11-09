-- Lua API of the Firebase Analytics plugin, which an app loads with `require('firebase-analytics')`. It needs the plugin `firebase`, which configures the Firebase app it logs into.
local platform = require('haylen.platform')

local handle = platform.plugin('firebase-analytics')
local analytics = {}

local kConsentKeys = {analyticsStorage = true, adStorage = true, adUserData = true, adPersonalization = true}

-- Whether the native part runs on this platform: iOS, Android and the web.
analytics.available = handle.native

-- Logs an event with an optional table of parameters, whose values are texts, numbers, flags or lists of item tables, such as `analytics.logEvent('level_up', {level = 3})`. Returns a platform call.
function analytics.logEvent(name, params)
    if type(name) ~= 'string' or name == '' then
        error('The function "analytics.logEvent" takes the name of the event as a string with at least one character.', 2)
    end
    if params ~= nil and type(params) ~= 'table' then
        error('The parameters of the event "' .. name .. '" are a table.', 2)
    end
    return handle:call('logEvent', {name = name, params = params})
end

-- Names the user of the events that follow, or clears the name with `nil`.
function analytics.setUserId(id)
    if id ~= nil and type(id) ~= 'string' then
        error('The function "analytics.setUserId" takes a string or nil.', 2)
    end
    return handle:call('setUserId', {id = id})
end

-- Sets a user property to a text, or clears it with `nil`.
function analytics.setUserProperty(name, value)
    if type(name) ~= 'string' or name == '' then
        error('The function "analytics.setUserProperty" takes the name of the property as a string with at least one character.', 2)
    end
    if value ~= nil and type(value) ~= 'string' then
        error('The value of the user property "' .. name .. '" is a string or nil.', 2)
    end
    return handle:call('setUserProperty', {name = name, value = value})
end

-- Sets the consent of the person, a table whose keys `analyticsStorage`, `adStorage`, `adUserData` and `adPersonalization` take `'granted'` or `'denied'`.
function analytics.setConsent(consent)
    if type(consent) ~= 'table' then
        error('The function "analytics.setConsent" takes a table of consents.', 2)
    end
    for key, value in pairs(consent) do
        if not kConsentKeys[key] then
            error(string.format('Unknown option "%s".', tostring(key)), 2)
        end
        if value ~= 'granted' and value ~= 'denied' then
            error(string.format('The consent "%s" takes "granted" or "denied".', key), 2)
        end
    end
    return handle:call('setConsent', consent)
end

-- Turns the collection of Analytics on or off for this device. Returns a platform call whose `await` gives `{enabled}`.
function analytics.setCollectionEnabled(enabled)
    if type(enabled) ~= 'boolean' then
        error('The function "analytics.setCollectionEnabled" takes a boolean.', 2)
    end
    return handle:call('setCollectionEnabled', {enabled = enabled})
end

-- Returns a platform call whose `await` gives `{id}`, the app instance ID of Analytics, or the client ID of Google Analytics on the web.
function analytics.appInstanceId()
    return handle:call('appInstanceId')
end

-- Clears the data that Analytics keeps on the device and starts a new app instance. Returns a platform call whose `await` gives `{reset}`. The web fails it with the code `unsupported`.
function analytics.resetAnalyticsData()
    return handle:call('resetAnalyticsData')
end

return analytics
