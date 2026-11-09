-- Lua API of the Permissions plugin, which an app loads with `require('permissions')`. The Lua module of each plugin that owns a permission declares it here when it loads, and a check or a request is the platform call `<id>.permission` or `<id>.requestPermission` of that plugin with the parameters `{name}`.
local platform = require('haylen.platform')

local permissions = {}

-- The plugin that owns each permission, `{id, handle, names}`, by the name of the permission.
local owners = {}

local function describeNames(names)
    local quoted = {}
    for index, name in ipairs(names) do
        quoted[index] = '"' .. name .. '"'
    end
    if #quoted == 1 then
        return quoted[1]
    end
    return table.concat(quoted, ', ', 1, #quoted - 1) .. ' and ' .. quoted[#quoted]
end

-- Calls the native part of the owner, whose answer is the state, or a failure with the code `unsupported`, the reason and `data.missing`.
local function ask(name, method, level)
    local owner = owners[name]
    if owner == nil then
        error(string.format('The permission "%s" belongs to no plugin that the app loaded. Each plugin declares the permissions it owns in its "plugin.json", and its Lua module declares them when the app requires it.', tostring(name)), level + 1)
    end

    return owner.handle:call(method, {name = name})
end

-- A plugin with one permission takes it without a name, and a plugin with several takes the name of one of them.
local function pick(owner, name, method)
    if name == nil and #owner.names == 1 then
        return owner.names[1]
    end
    for _, owned in ipairs(owner.names) do
        if owned == name then
            return name
        end
    end
    if name == nil then
        error(string.format('The plugin "%s" owns the permissions %s, so "%s.%s" takes the name of one of them.', owner.id, describeNames(owner.names), owner.id, method), 3)
    end
    error(string.format('The plugin "%s" owns no permission "%s". It owns %s.', owner.id, tostring(name), describeNames(owner.names)), 3)
end

-- Declares the permissions `names` that the plugin `id` owns, which its Lua module does when it loads, and returns the table that the plugin offers to the app, whose `state(name)` and `request(name)` take the name of one of its permissions, or nothing for a plugin with one. A module that loads again, such as after a reload, declares them again.
function permissions.declare(id, names)
    if type(id) ~= 'string' or id == '' then
        error('The function "permissions.declare" takes the id of a plugin.', 2)
    end
    if type(names) ~= 'table' or #names == 0 then
        error(string.format('The plugin "%s" declares its permissions as a list of their names.', id), 2)
    end

    local owner = {id = id, handle = platform.plugin(id), names = {}}
    for index, name in ipairs(names) do
        if type(name) ~= 'string' or name == '' then
            error(string.format('The plugin "%s" declares its permissions as a list of their names.', id), 2)
        end
        local other = owners[name]
        if other ~= nil and other.id ~= id then
            error(string.format('The permission "%s" belongs to the plugin "%s", so the plugin "%s" cannot declare it too. One plugin of an app owns each permission.', name, other.id, id), 2)
        end
        owner.names[index] = name
    end
    for _, name in ipairs(owner.names) do
        owners[name] = owner
    end

    return {
        state = function(name) return ask(pick(owner, name, 'permission'), 'permission', 2) end,
        request = function(name) return ask(pick(owner, name, 'requestPermission'), 'requestPermission', 2) end,
    }
end

-- Returns the platform call whose `await` gives the state of the permission `name`, as far as the platform tells it, without asking the person: `'granted'`, `'prompt'`, `'denied'` or `'unknown'`. A platform without the capability fails it with the code `unsupported` and the reason.
function permissions.state(name)
    return ask(name, 'permission', 2)
end

-- Returns the platform call whose `await` gives the state that the person left, after the prompt of the system where the state is `'prompt'`. A platform without the capability, or a project that lacks what the prompt needs, fails it with the code `unsupported`, the reason and, for the project, `data.missing`.
function permissions.request(name)
    return ask(name, 'requestPermission', 2)
end

return permissions
