-- Lua API of the Firebase Cloud Messaging plugin, which an app loads with `require('firebase-messaging')`. It needs the plugins `firebase` and `notifications`, whose permission `notifications` the app asks for with `notifications.requestPermission()` of the plugin `notifications` before notifications show. Messages reach `onMessage` while the app runs, taps on notifications reach `onOpened`, also the tap that launched the app, and every registration of the app instance reaches `onRegistered`.
local platform = require('haylen.platform')

local handle = platform.plugin('firebase-messaging')
local messaging = {}

-- Whether the native part runs on this platform: iOS, Android and the web.
messaging.available = handle.native

local function checkTopic(name, topic)
    if type(topic) ~= 'string' or topic == '' then
        error(string.format('The function "messaging.%s" takes the name of the topic as a string with at least one character.', name), 3)
    end
end

-- Registers the app instance with Cloud Messaging and returns a platform call whose `await` gives `{installationId}`, the Firebase installation ID that the server of the app sends messages to. It fails with the code `unavailable` while Firebase cannot register, such as on a device without the services of Google, and on the web with the code `denied` until the person allows notifications.
function messaging.register()
    return handle:call('register')
end

-- Unregisters the app instance, so messages to its installation ID no longer arrive. Returns a platform call whose `await` gives `{installationId}`.
function messaging.unregister()
    return handle:call('unregister')
end

-- Subscribes the device to a topic. Returns a platform call whose `await` gives `{topic}`. The web fails it with the code `unsupported`, since its subscriptions go through the server of the app.
function messaging.subscribe(topic)
    checkTopic('subscribe', topic)
    return handle:call('subscribe', {topic = topic})
end

-- Unsubscribes the device from a topic, like `subscribe`.
function messaging.unsubscribe(topic)
    checkTopic('unsubscribe', topic)
    return handle:call('unsubscribe', {topic = topic})
end

-- Turns on or off the registration that Firebase makes on its own when the app starts. Returns a platform call whose `await` gives `{enabled}`. The web fails it with the code `unsupported`, since the web registers only when the app asks.
function messaging.setAutoInitEnabled(enabled)
    if type(enabled) ~= 'boolean' then
        error('The function "messaging.setAutoInitEnabled" takes a boolean.', 2)
    end
    return handle:call('setAutoInitEnabled', {enabled = enabled})
end

-- Calls `listener({messageId, title, body, data})` for every message that arrives while the app runs, and returns the connection.
function messaging.onMessage(listener, options)
    return handle:on('messageReceived', listener, options)
end

-- Calls `listener({messageId, title, body, data})` when the person taps a notification of a message, also the one that launched the app.
function messaging.onOpened(listener, options)
    return handle:on('messageOpened', listener, options)
end

-- Calls `listener({installationId})` whenever Cloud Messaging registers the app instance, also on its own when the app starts, and returns the connection.
function messaging.onRegistered(listener, options)
    return handle:on('registered', listener, options)
end

-- Calls `listener({message})` when Apple refuses to register the device for push, such as an app signed without the entitlement aps-environment.
function messaging.onRegistrationFailed(listener, options)
    return handle:on('registrationFailed', listener, options)
end

return messaging
