-- Lua API of the Dialogs plugin, which an app loads with `require('dialogs')`. It checks every request the way the native part of each platform expects it, and the native part shows the dialog and answers its call.
local haylen = require('haylen')
local native = require('haylen.native')
local platform = require('haylen.platform')

local PickedFiles = require('dialogs.picked-files')

local handle = platform.plugin('dialogs')
local dialogs = {}

local kDesktops = {macos = true, windows = true, linux = true}
local kMessageKinds = {info = true, warning = true, error = true}
local kMessageOptions = {title = true, text = true, kind = true, buttons = true, timeout = true}
local kOpenFilesOptions = {title = true, filters = true, multiple = true, timeout = true}
local kSaveFileOptions = {title = true, name = true, data = true, filters = true, timeout = true}
local kOpenFolderOptions = {title = true, timeout = true}
local kOpenPhotosOptions = {title = true, multiple = true, timeout = true}
local kFilterFields = {name = true, extensions = true}
local kFiltersShape = 'The filters of a file dialog are a list of tables with a name and a list of extensions.'

-- Apple platforms, Android and the web load their native parts before any Lua runs. The desktop player and the Windows and Linux apps run the library of `native/`, which the tooling places next to them and which declares itself the native part of the plugin in its init function, once per process.
if not handle.native and kDesktops[haylen.platform] then
    native.load('dialogs', {init = 'dialogs_haylen_init'})
end

-- The web hands the picked files over as bytes, which the plugin writes into its folder of the storage, so the app reads them at their paths as on every other platform.
local kPicksBytes = haylen.platform == 'web'

-- The messages are whole sentences without the place of the check, since the stack of the error shows the call of the app.
local function fail(message)
    error(message, 0)
end

local function checkOptions(options, allowed, name, optional)
    if options == nil and optional then
        return {}
    end
    if type(options) ~= 'table' then
        error(string.format("bad argument #1 to '%s' (table expected, got %s)", name, type(options)), 3)
    end
    for key in pairs(options) do
        if not allowed[key] then
            fail(string.format('Unknown option "%s".', tostring(key)))
        end
    end
    return options
end

local function readString(options, key, default)
    local value = options[key]
    if value == nil then
        return default
    end
    if type(value) ~= 'string' then
        fail(string.format('The option "%s" of a dialog is a string, not a %s.', key, type(value)))
    end
    return value
end

local function readBoolean(options, key)
    local value = options[key]
    if value == nil then
        return false
    end
    if type(value) ~= 'boolean' then
        fail(string.format('The option "%s" of a dialog is a boolean, not a %s.', key, type(value)))
    end
    return value
end

local function readTimeout(options)
    local seconds = options.timeout
    if seconds == nil then
        return nil
    end
    if type(seconds) ~= 'number' or seconds ~= seconds or seconds <= 0 or seconds == math.huge then
        fail('The timeout of a dialog is a positive number of seconds.')
    end
    return seconds
end

-- Extensions reach every platform in the same form, without the dot and without the wildcards and separators of the filter syntaxes of each platform.
local function readFilters(options)
    local filters = options.filters
    if filters == nil then
        return nil
    end
    if type(filters) ~= 'table' then
        fail(kFiltersShape)
    end
    local checked = {}
    for index = 1, #filters do
        local filter = filters[index]
        if type(filter) ~= 'table' then
            fail(kFiltersShape)
        end
        for key in pairs(filter) do
            if not kFilterFields[key] then
                fail(string.format('Unknown option "%s".', tostring(key)))
            end
        end
        if type(filter.name) ~= 'string' or filter.name == '' then
            fail('Every filter of a file dialog needs a name.')
        end
        if type(filter.extensions) ~= 'table' or #filter.extensions == 0 then
            fail(string.format('The filter "%s" needs at least one extension.', filter.name))
        end
        local extensions = {}
        for position = 1, #filter.extensions do
            local extension = filter.extensions[position]
            if type(extension) ~= 'string' or extension == '' or extension:sub(1, 1) == '.' or extension:find('[%*%?/\\;, \t]') then
                fail(string.format('The extension "%s" of the filter "%s" is invalid. Extensions come without their dot, such as "png" or "tar.gz".', tostring(extension), filter.name))
            end
            extensions[position] = extension
        end
        checked[index] = {name = filter.name, extensions = extensions}
    end
    -- An empty list would cross the bridge as an empty object, and no filters means every file.
    if #checked == 0 then
        return nil
    end
    return checked
end

local function call(method, params, timeout)
    return handle:call(method, params, timeout and {timeout = timeout} or nil)
end

local function pick(method, params, timeout)
    local picker = call(method, params, timeout)
    if kPicksBytes then
        return PickedFiles.new(picker)
    end
    return picker
end

-- Shows a message with one to three buttons, whose call gives the button that the person pressed, counted from 1, or `nil` when the person dismissed the message.
function dialogs.message(options)
    checkOptions(options, kMessageOptions, 'message')
    local title = readString(options, 'title', '')
    local text = readString(options, 'text', '')
    local kind = readString(options, 'kind', 'info')
    local timeout = readTimeout(options)
    if text == '' then
        fail('A message dialog needs a text.')
    end
    if not kMessageKinds[kind] then
        fail(string.format('The kind "%s" of a message dialog is unknown. Use "info", "warning" or "error".', kind))
    end

    local buttons = options.buttons
    if type(buttons) ~= 'table' or #buttons == 0 or #buttons > 3 then
        fail(string.format('A message dialog has one to three buttons, not %d.', type(buttons) == 'table' and #buttons or 0))
    end
    local labels = {}
    for index = 1, #buttons do
        if type(buttons[index]) ~= 'string' or buttons[index] == '' then
            fail('Every button of a message dialog needs a label.')
        end
        labels[index] = buttons[index]
    end
    return call('message', {title = title, text = text, kind = kind, buttons = labels}, timeout)
end

-- Shows a picker of files to open, whose call gives a list of `{name, path}`, or `nil` when the person cancelled.
function dialogs.openFiles(options)
    options = checkOptions(options, kOpenFilesOptions, 'openFiles', true)
    local params = {title = readString(options, 'title', ''), filters = readFilters(options), multiple = readBoolean(options, 'multiple')}
    return pick('openFiles', params, readTimeout(options))
end

-- Shows a picker of the place to save a file and writes `data` there, whose call gives `{name, path}`, with no path where the platform gives none, or `nil` when the person cancelled.
function dialogs.saveFile(options)
    checkOptions(options, kSaveFileOptions, 'saveFile')
    local title = readString(options, 'title', '')
    local name = readString(options, 'name', '')
    local filters = readFilters(options)
    local timeout = readTimeout(options)
    if name == '' then
        fail('A save dialog needs the name it suggests for the file.')
    end
    if name:find('[/\\]') then
        fail(string.format('The name "%s" that a save dialog suggests is a file name, without folders.', name))
    end
    if type(options.data) ~= 'string' then
        fail('A save dialog needs the data it writes, as a string.')
    end
    return call('saveFile', {title = title, name = name, filters = filters, data = platform.bytes(options.data)}, timeout)
end

-- Shows a picker of a folder, whose call gives the path of the folder, or `nil` when the person cancelled.
function dialogs.openFolder(options)
    options = checkOptions(options, kOpenFolderOptions, 'openFolder', true)
    return call('openFolder', {title = readString(options, 'title', '')}, readTimeout(options))
end

-- Shows the photo picker of the system, which needs no permission, whose call gives a list of `{name, path}`, or `nil` when the person cancelled.
function dialogs.openPhotos(options)
    options = checkOptions(options, kOpenPhotosOptions, 'openPhotos', true)
    local params = {title = readString(options, 'title', ''), multiple = readBoolean(options, 'multiple')}
    return pick('openPhotos', params, readTimeout(options))
end

return dialogs
