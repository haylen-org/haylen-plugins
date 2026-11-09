-- Lua API of the local plugin of the sample, which an app loads with `require('permission-states')`. It owns a permission of every state, which its native part on Apple platforms, Android and the web registers through the Permissions plugin: `held` is granted, `asked` is the permission of notifications, which shows the prompt of the system, `refused` is denied, `untold` is unknown and `absent` is unsupported.
local permissions = require('permissions')
local platform = require('haylen.platform')

local handle = platform.plugin('permission-states')
local states = {}

local permission = permissions.declare('permission-states', {'held', 'asked', 'refused', 'untold', 'absent'})

states.names = {'held', 'asked', 'refused', 'untold', 'absent'}

-- Returns the platform call whose `await` gives the state of the permission `name`, without asking, or `nil` and an error with the code `unsupported`.
states.permission = permission.state

-- Returns the platform call whose `await` gives the state of the permission `name` that the person left, after the prompt of the system while the state is `prompt`.
states.requestPermission = permission.request

-- Uses the permission `name`, which the native part asks for first. Returns a platform call whose `await` gives a sentence, or `nil` and an error with the code `denied` or `unsupported`.
function states.use(name)
    return handle:call('use', {name = name})
end

return states
