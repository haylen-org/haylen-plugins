-- Lua API of the Links plugin, which an app loads with `require('links')`. It opens a url with the app that the system picks for it, on every platform.
local haylen = require('haylen')
local log = require('haylen.log')
local native = require('haylen.native')
local platform = require('haylen.platform')

local handle = platform.plugin('links')
local links = {}

local kDesktops = {macos = true, windows = true, linux = true}

-- The sentences of the refusals that the plugin logged, once each.
local logged = {}

-- Apple platforms, Android and the web load their native parts before any Lua runs. The desktop player and the Windows and Linux apps run the C++ library of `native/`, which declares itself the native part of the plugin in its init function, once per process.
if not handle.native and kDesktops[haylen.platform] then
    native.load('links', {init = 'links_haylen_init'})
end

local function logRefusal(message)
    if logged[message] then
        return
    end
    logged[message] = true
    log.warning(message)
end

-- Opens `url` with the app that the system picks for it, such as the browser for a web page or the mail app for a `mailto:` link. Returns a platform call, whose `await` gives `true` once an app took the url, or `nil` and an error with the code `unsupported` when no app opens it or `denied` when the browser blocked the new tab. A refusal that nothing awaits is logged once and never stops the app.
function links.open(url)
    if type(url) ~= 'string' then
        error(string.format('A url is a string, not a %s.', type(url)), 2)
    end
    if url == '' then
        error('Opening a url needs a url.', 2)
    end

    local call = handle:call('open', {url = url})
    call.promise:catch(logRefusal)
    return call
end

return links
