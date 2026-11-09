-- Lua API of the Media Session plugin, which an app loads with `require('media-session')`. It shows what the app plays in the now-playing controls of the system, and the commands of those controls, of the media keys and of the buttons of headsets and remotes reach the app as the event `command`.
local haylen = require('haylen')
local native = require('haylen.native')
local platform = require('haylen.platform')

local handle = platform.plugin('media-session')
local mediaSession = {}

local kFields = {title = true, artist = true, album = true, duration = true, position = true, playing = true, artwork = true, commands = true}
local kTexts = {'title', 'artist', 'album'}
local kNumbers = {'duration', 'position'}
local kCommands = {play = true, pause = true, togglePlayPause = true, stop = true, next = true, previous = true, seek = true}
local kEvents = {command = true}

-- Apple platforms, Android and the web load their native parts before any Lua runs. A Windows app runs the C++ library of `native/`, which declares itself the native part of the plugin in its init function, once per process.
if not handle.native and haylen.platform == 'windows' then
    native.load('media-session', {init = 'media_session_haylen_init'})
end

-- The controls belong to the process, so the module of every app that starts, such as one that restarted or one that another app launched, takes what an earlier app showed out of them.
handle:send('clear')

local function checkType(info, key, expected)
    local value = info[key]
    if value ~= nil and type(value) ~= expected then
        error(string.format('The option "%s" of "setNowPlaying" is invalid: %s expected, got %s.', key, expected, type(value)), 3)
    end
end

-- The commands cross as an object of the names that the controls offer, since an empty list would cross as an empty object.
local function readCommands(commands)
    if commands == nil then
        return kCommands
    end
    if type(commands) ~= 'table' then
        error('The option "commands" must be a list of command names.', 3)
    end

    local offered = {}
    for _, name in ipairs(commands) do
        if not kCommands[name] then
            error(string.format('The option "commands" names "%s", which is not "play", "pause", "togglePlayPause", "stop", "next", "previous" or "seek".', tostring(name)), 3)
        end
        offered[name] = true
    end
    return offered
end

-- Shows what plays in the controls of the system, replacing what showed before: the texts `title`, `artist` and `album`, the `duration` and the `position` in seconds, where a duration of `0` is one that is not known, whether it is `playing`, the bytes of a PNG or JPEG `artwork` and the `commands` that the controls offer, every command by default.
function mediaSession.setNowPlaying(info)
    if type(info) ~= 'table' then
        error(string.format('The function "mediaSession.setNowPlaying" takes a table of what plays, not a %s.', type(info)), 2)
    end
    for key in pairs(info) do
        if not kFields[key] then
            error('Unknown option "' .. tostring(key) .. '".', 2)
        end
    end
    for _, key in ipairs(kTexts) do
        checkType(info, key, 'string')
    end
    for _, key in ipairs(kNumbers) do
        checkType(info, key, 'number')
    end
    checkType(info, 'playing', 'boolean')

    local duration = info.duration or 0
    local position = info.position or 0
    if not (duration >= 0) or not (position >= 0) then
        error('The duration and the position of what plays cannot be negative.', 2)
    end
    if info.artwork ~= nil and type(info.artwork) ~= 'string' then
        error('The option "artwork" must be the bytes of a PNG or JPEG image.', 2)
    end

    local params = {
        title = info.title or '',
        artist = info.artist or '',
        album = info.album or '',
        duration = duration,
        position = position,
        playing = info.playing == true,
        commands = readCommands(info.commands),
    }
    if info.artwork ~= nil then
        params.artwork = platform.bytes(info.artwork)
    end
    handle:send('setNowPlaying', params)
end

-- Takes the app out of the controls of the system, which then send no more commands.
function mediaSession.clear()
    handle:send('clear')
end

-- Returns a platform call whose `await` gives what the controls of the system show, read back from the system as `{title, artist, album, duration, playing, artwork}` with `artwork` telling whether they show a picture, or `nil` while they show nothing of the app.
function mediaSession.nowPlaying()
    return handle:call('nowPlaying', {})
end

-- Calls `listener({command, position})` for every command that the controls, a media key or the button of a headset or a remote sends, where `command` is one of the names of `commands` and `position` the seconds of a `'seek'`. Returns the connection of the listener. The table `options` takes `owner`.
function mediaSession.on(event, listener, options)
    if not kEvents[event] then
        error(string.format('The plugin "media-session" sends the event "command" alone, not "%s".', tostring(event)), 2)
    end
    return handle:on(event, listener, options)
end

return mediaSession
