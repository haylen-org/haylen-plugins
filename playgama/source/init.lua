-- Lua API of the Playgama Bridge plugin, which an app loads with `require('playgama')`. The bridge serves web games only, and on other platforms the calls fail with the code `noHandler`, which `available` tells ahead. Run on any other site, such as a local server, the bridge plays the platform `mock`, which shows no ads and keeps the storage in the page.
local platform = require('haylen.platform')

local handle = platform.plugin('playgama')
local playgama = {}

-- Whether the native part runs on this platform: the web.
playgama.available = handle.native

-- Raises `Unknown option "<key>".` for a key of `options` that `known` lacks.
local function checkOptions(options, known)
    for key in pairs(options) do
        if not known[key] then
            error('Unknown option "' .. tostring(key) .. '".', 3)
        end
    end
end

local function checkKey(key)
    if type(key) ~= 'string' or key == '' then
        error('The key of the storage of Playgama is a string with at least one character.', 3)
    end
end

-- Returns a platform call whose `await` gives `{id, language, tld, payload, audioEnabled, paused, deviceType, interstitialSupported, rewardedSupported, bannerSupported}`, the platform the game runs on and what it supports.
function playgama.platform()
    return handle:call('platform')
end

-- Returns a platform call whose `await` gives `{authorizationSupported, authorized, guest, id, name, photos}`.
function playgama.player()
    return handle:call('player')
end

-- Asks the platform to sign the player in, and returns a platform call whose `await` gives the player as `playgama.player` does.
function playgama.authorizePlayer()
    return handle:call('authorizePlayer')
end

-- Tells the platform about the game, with one of the names of the README, such as `'gameReady'` once the game can be played.
function playgama.sendMessage(name)
    return handle:call('sendMessage', {name = name})
end

-- Shows an interstitial ad. Returns a platform call whose `await` gives `{shown, rewarded}` once it closes. The options take `placement`, a placement of the config of the bridge.
function playgama.showInterstitial(options)
    options = options or {}
    checkOptions(options, {placement = true})
    return handle:openScreen('interstitial', {placement = options.placement})
end

-- Shows a rewarded ad. Returns a platform call whose `await` gives `{shown, rewarded}` once it closes, where `rewarded` tells whether the player earned the reward. The options take `placement`.
function playgama.showRewarded(options)
    options = options or {}
    checkOptions(options, {placement = true})
    return handle:openScreen('rewarded', {placement = options.placement})
end

-- Shows the banner of the platform, whose states reach `onBannerChanged`. The options take `position`, `'bottom'` by default or `'top'`, and `placement`.
function playgama.showBanner(options)
    options = options or {}
    checkOptions(options, {position = true, placement = true})
    return handle:call('showBanner', {position = options.position or 'bottom', placement = options.placement})
end

function playgama.hideBanner()
    return handle:call('hideBanner')
end

-- Reads the text that the storage of the platform keeps under `key`, the cloud storage of the player where the platform has one. Returns a platform call whose `await` gives `{value}`, with `value` nil for a key without one.
function playgama.storageGet(key)
    checkKey(key)
    return handle:call('storageGet', {key = key})
end

-- Keeps a text under `key`, where an empty text deletes the key.
function playgama.storageSet(key, value)
    checkKey(key)
    if type(value) ~= 'string' then
        error('The value of the storage of Playgama is a string, such as the text of "json.encode".', 2)
    end
    return handle:call('storageSet', {key = key, value = value})
end

function playgama.storageDelete(key)
    checkKey(key)
    return handle:call('storageDelete', {key = key})
end

-- Calls `listener({paused})` when the platform pauses or resumes the game.
function playgama.onPauseChanged(listener, options)
    return handle:on('pauseChanged', listener, options)
end

-- Calls `listener({enabled})` when the platform turns the sound of the game off or on.
function playgama.onAudioChanged(listener, options)
    return handle:on('audioChanged', listener, options)
end

-- Calls `listener({state})` when the banner changes to `'loading'`, `'shown'`, `'hidden'` or `'failed'`.
function playgama.onBannerChanged(listener, options)
    return handle:on('bannerChanged', listener, options)
end

return playgama
