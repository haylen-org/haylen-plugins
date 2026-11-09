-- Lua API of the Google Analytics plugin, which an app loads with `require('google-analytics')`. It sends the events of a web app to Google Analytics 4. Apps on iOS and Android send theirs through the plugin `firebase-analytics`, which reports to the same Analytics property when the Firebase project links it.
local platform = require('haylen.platform')

local handle = platform.plugin('google-analytics')
local analytics = {}

-- Whether the native part runs on this platform: the web.
analytics.available = handle.native

-- Sends an event with an optional table of parameters, such as `analytics.logEvent('level_up', {level = 3})`.
function analytics.logEvent(name, params)
    if type(name) ~= 'string' or name == '' then
        error('The name of an event of Google Analytics is a string with at least one character, such as "level_up".', 2)
    end
    if params ~= nil and type(params) ~= 'table' then
        error('The parameters of an event of Google Analytics are a table, such as {level = 3}.', 2)
    end
    return handle:call('logEvent', {name = name, params = params})
end

-- Names the user of the events that follow, or clears the name with `nil`.
function analytics.setUserId(id)
    if id ~= nil and type(id) ~= 'string' then
        error('The user ID of Google Analytics is a string, or nil to clear it.', 2)
    end
    return handle:call('setUserId', {id = id})
end

-- Sets user properties from a table of texts and numbers.
function analytics.setUserProperties(properties)
    if type(properties) ~= 'table' then
        error('The user properties of Google Analytics are a table of texts and numbers, such as {plan = "free"}.', 2)
    end
    return handle:call('setUserProperties', properties)
end

-- Updates the consent of the person, a table whose keys `analyticsStorage`, `adStorage`, `adUserData` and `adPersonalization` take `'granted'` or `'denied'`.
function analytics.setConsent(consent)
    if type(consent) ~= 'table' then
        error('The consent of Google Analytics is a table, such as {analyticsStorage = "granted"}.', 2)
    end
    return handle:call('setConsent', consent)
end

-- Returns a platform call whose `await` gives `{id}`, the client ID that Google Analytics gave the browser.
function analytics.clientId()
    return handle:call('clientId')
end

return analytics
