-- Lua API of the App Tracking Transparency plugin, which an app loads with `require('app-tracking-transparency')`. The plugin owns the permission `tracking`, which the app checks and asks for with `tracking.permission()` and `tracking.requestPermission()` through the Permissions plugin, and which Android and the web answer with `granted`, since they show no prompt for it.
local permissions = require('permissions')
local platform = require('haylen.platform')

local handle = platform.plugin('app-tracking-transparency')
local tracking = {}

local permission = permissions.declare('app-tracking-transparency', {'tracking'})

-- Whether the native part runs on this platform. Without it every call fails with the code `noHandler`.
tracking.available = handle.native

-- Returns a platform call whose `await` gives the state of the permission `tracking`, without asking the person, or `nil` and an error with the code `unsupported` and `data.missing` for a requirement that the project lacks.
tracking.permission = permission.state

-- Returns a platform call whose `await` gives the state of the permission `tracking` that the person left, after the prompt of the system while the state is `prompt`, or `nil` and an error with the code `unsupported` and `data.missing` for a requirement that the project lacks.
tracking.requestPermission = permission.request

-- Returns a platform call whose `await` gives `{id}`, the advertising identifier of the device on Apple platforms. It asks for the permission `tracking` first where the person has not answered yet, and fails with the code `denied` while the person does not allow tracking. Android and the web fail it with the code `unsupported`.
function tracking.advertisingId()
    return handle:call('advertisingId')
end

return tracking
