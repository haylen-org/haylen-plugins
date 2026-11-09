-- Lua API of the Firebase plugin, which an app loads with `require('firebase')`. The native part of iOS, Android and the web configures the default Firebase app before any Lua runs, and the plugins `firebase-analytics`, `firebase-messaging` and `firebase-crashlytics` use it.
local platform = require('haylen.platform')

local handle = platform.plugin('firebase')
local firebase = {}

-- Whether the native part runs on this platform: iOS, Android and the web.
firebase.available = handle.native

-- Returns a platform call whose `await` gives the default Firebase app as `{name, projectId, appId, senderId, dataCollection}`, or fails with the code `notConfigured` when the configuration of the platform is missing or invalid.
function firebase.app()
    return handle:call('app')
end

-- Turns the automatic data collection of every Firebase library on or off, which the app keeps off until the person agrees to it where the law asks for consent. Returns a platform call whose `await` gives `{enabled}`.
function firebase.setDataCollection(enabled)
    if type(enabled) ~= 'boolean' then
        error('The function "firebase.setDataCollection" takes a boolean.', 2)
    end
    return handle:call('setDataCollection', {enabled = enabled})
end

return firebase
