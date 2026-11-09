-- Lua API of the Play Asset Delivery plugin, which an app loads with `require('play-asset-delivery')`. Its source of packs hands every pack that the app needs to Google Play, so the app loads the assets of its packs the way it loads any other asset.
local content = require('haylen.content')
local platform = require('haylen.platform')

local handle = platform.plugin('play-asset-delivery')
local delivery = {}

-- Whether the native part runs on this platform: Android.
delivery.available = handle.native

-- Returns the name of the asset pack of Google Play that holds a named pack of the content, the pack name with every dash and dot as an underscore, and with `pack_` in front of a name that starts with a digit, as the Android release build names it.
function delivery.packName(pack)
    local name = pack:gsub('[-.]', '_')
    return name:match('^%d') and 'pack_' .. name or name
end

-- Fetches a pack from Google Play and returns the folder where Play placed it, or nil when Play does not deliver it. While Play waits for Wi-Fi or for the person to accept a large download, the confirmation of Play shows when `confirm` allows it, and the fetch goes on once the person accepts.
local function fetch(name, confirm)
    while true do
        local result, err = handle:call('fetch', {pack = name}):await()
        if not result then
            error(err.message, 0)
        end
        if not result.confirm then
            return result.folder
        end
        if not confirm then
            error('Google Play waits for the person to accept the download of the asset pack "' .. name .. '".', 0)
        end
        local answer, failure = handle:openScreen('confirm', {}):await()
        if not answer then
            error(failure.message, 0)
        end
        if not answer.confirmed then
            handle:call('cancel', {pack = name}):await()
            error('The person declined the download of the asset pack "' .. name .. '".', 0)
        end
    end
end

-- Fetches a pack with `fetch`, reporting the progress of its download to the load.
local function fetchWithProgress(pack, progress, options)
    local name = delivery.packName(pack)
    local progressing = handle:on('progress', function(state)
        if state.pack == name then
            progress({receivedBytes = state.receivedBytes, totalBytes = state.totalBytes})
        end
    end, {owner = options.owner})
    local ok, folder = pcall(fetch, name, options.confirm ~= false)
    progressing:disconnect()
    if not ok then
        error(folder, 0)
    end
    return folder
end

-- Adds the source of packs, which fetches each pack from Google Play and returns a connection that removes it. The options take `owner`, whose end removes the source, and `confirm`, `true` by default, which shows the confirmation of Google Play when a pack waits for Wi-Fi or for the person to accept a large download.
function delivery.addSource(options)
    options = options or {}
    for key in pairs(options) do
        if key ~= 'owner' and key ~= 'confirm' then
            error('Unknown option "' .. tostring(key) .. '".', 2)
        end
    end
    return content.addPackSource(function(pack, progress)
        if not handle.native then
            return nil
        end
        return fetchWithProgress(pack, progress, options)
    end, {owner = options.owner})
end

-- Returns a platform call whose `await` gives the state of a named pack on the device, `{pack, status, receivedBytes, totalBytes}`, where `status` is `'notInstalled'`, `'pending'`, `'downloading'`, `'transferring'`, `'completed'`, `'failed'`, `'cancelled'`, `'waitingForWifi'`, `'requiresUserConfirmation'` or `'unknown'`.
function delivery.state(pack)
    if type(pack) ~= 'string' or pack == '' then
        error('The name of a pack is a string with at least one character, such as "chapter-2".', 2)
    end
    return handle:call('state', {pack = delivery.packName(pack)})
end

return delivery
