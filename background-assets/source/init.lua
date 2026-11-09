-- Lua API of the Background Assets plugin, which an app loads with `require('background-assets')`. Its source of packs hands every pack that the app needs to the system, which downloads the asset pack that the App Store hosts for it, so the app loads the assets of its packs the way it loads any other asset.
local content = require('haylen.content')
local platform = require('haylen.platform')

local handle = platform.plugin('background-assets')
local backgroundAssets = {}

-- Whether the native part runs on this platform: iOS, tvOS and visionOS.
backgroundAssets.available = handle.native

-- Fetches a pack from the App Store and returns the folder of the pack, or nil when the App Store does not host it, reporting the progress of the download to the load.
local function fetch(pack, progress, owner)
    local progressing = handle:on('progress', function(state)
        if state.pack == pack then
            progress({receivedBytes = state.receivedBytes, totalBytes = state.totalBytes})
        end
    end, {owner = owner})
    local result, err = handle:call('fetch', {pack = pack}):await()
    progressing:disconnect()
    if not result then
        error(err.message, 0)
    end
    return result.folder
end

-- Adds the source of packs, which fetches each pack from the App Store and returns a connection that removes it. The options take `owner`, whose end removes the source.
function backgroundAssets.addSource(options)
    options = options or {}
    for key in pairs(options) do
        if key ~= 'owner' then
            error('Unknown option "' .. tostring(key) .. '".', 2)
        end
    end
    return content.addPackSource(function(pack, progress)
        if not handle.native then
            return nil
        end
        return fetch(pack, progress, options.owner)
    end, {owner = options.owner})
end

-- Returns a platform call whose `await` gives `{pack, status}` for a named pack, where `status` is `'available'` once the pack is on the device, `'notDownloaded'` before, and `'unavailable'` on systems before 26.4, which do not tell it.
function backgroundAssets.state(pack)
    if type(pack) ~= 'string' or pack == '' then
        error('The name of a pack is a string with at least one character, such as "chapter-2".', 2)
    end
    return handle:call('state', {pack = pack})
end

return backgroundAssets
