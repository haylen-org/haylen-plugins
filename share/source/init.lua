-- Lua API of the Share plugin, which an app loads with `require('share')`. The native part of each platform shows the share sheet of the system with a text, a url and files, and answers once the person shared or closed it.
local haylen = require('haylen')
local native = require('haylen.native')
local platform = require('haylen.platform')
local viewport = require('haylen.viewport')
local window = require('haylen.window')

local handle = platform.plugin('share')
local share = {}

-- The macOS desktop player and the Windows apps run the library of `native/`, while the macOS app runs the Apple part.
if not handle.native and (haylen.platform == 'macos' or haylen.platform == 'windows') then
    native.load('share', {init = 'share_haylen_init'})
end

-- Whether the native part runs on this platform. Without it every call fails with the code `noHandler`.
share.available = handle.native

local kShareKeys = {text = true, url = true, title = true, files = true, anchor = true}
local kFileKeys = {name = true, type = true, bytes = true}
local kAnchorKeys = {'x', 'y', 'width', 'height'}

-- Raises at the caller of `share.share`, which is `level` calls above this function.
local function checkKeys(options, keys, level)
    for key in pairs(options) do
        if not keys[key] then
            error(string.format('Unknown option "%s".', tostring(key)), level)
        end
    end
end

local function checkString(options, key)
    if options[key] ~= nil and type(options[key]) ~= 'string' then
        error(string.format('The "%s" of a share is a string.', key), 4)
    end
end

-- The files cross the bridge as bytes, each with the name that the person sees and its media type.
local function fileParams(files)
    if type(files) ~= 'table' then
        error('The "files" of a share are a list of files, each {name, type, bytes}.', 4)
    end
    local params = {}
    for index, file in ipairs(files) do
        if type(file) ~= 'table' then
            error(string.format('The file %d of a share is a table {name, type, bytes}.', index), 4)
        end
        checkKeys(file, kFileKeys, 5)
        if type(file.name) ~= 'string' or file.name == '' or file.name:find('[/\\]') then
            error(string.format('The file %d of a share needs a "name" with at least one character and no slash, such as "photo.png".', index), 4)
        end
        if type(file.bytes) ~= 'string' then
            error(string.format('The file "%s" of a share needs its "bytes" as a string.', file.name), 4)
        end
        if file.type ~= nil and type(file.type) ~= 'string' then
            error(string.format('The "type" of the file "%s" of a share is a media type such as "image/png".', file.name), 4)
        end
        params[index] = {name = file.name, type = file.type or 'application/octet-stream', bytes = platform.bytes(file.bytes)}
    end
    return params
end

-- The native parts place the popover of the sheet over a rectangle in fractions of the window, which the rectangle in design units turns into here. The rectangle is a table or a `haylen.Rect`, such as the one of `gui:bounds(id)`.
local function anchorParams(anchor)
    local kind = type(anchor)
    if kind ~= 'table' and kind ~= 'userdata' then
        error('The "anchor" of a share is a rectangle with "x", "y", "width" and "height" in design units.', 4)
    end
    for _, key in ipairs(kAnchorKeys) do
        if type(anchor[key]) ~= 'number' then
            error(string.format('The "%s" of the anchor of a share is a number.', key), 4)
        end
    end
    local width, height = window.framebufferSize()
    local left, top = viewport.toFramebuffer(anchor.x, anchor.y)
    local right, bottom = viewport.toFramebuffer(anchor.x + anchor.width, anchor.y + anchor.height)
    return {x = left / width, y = top / height, width = (right - left) / width, height = (bottom - top) / height}
end

local function shareParams(options)
    if type(options) ~= 'table' then
        error('The function "share.share" takes a table of options.', 3)
    end
    checkKeys(options, kShareKeys, 4)
    checkString(options, 'text')
    checkString(options, 'url')
    checkString(options, 'title')

    local params = {text = options.text, url = options.url, title = options.title}
    if options.files ~= nil then
        params.files = fileParams(options.files)
    end
    if options.anchor ~= nil then
        params.anchor = anchorParams(options.anchor)
    end
    if params.text == nil and params.url == nil and (params.files == nil or #params.files == 0) then
        error('A share needs a "text", a "url" or "files".', 3)
    end
    return params
end

-- Shows the share sheet of the system and returns a platform call whose `await` gives `{shared, target}`: whether the person shared, and where the platform tells it, the activity or the app that they picked.
function share.share(options)
    return handle:call('share', shareParams(options))
end

return share
