-- The sample of the Media Session plugin: a loop of the sample plays and shows in the now-playing controls of the system with the artwork of the sample, and every command of those controls, of the media keys and of the buttons of headsets and remotes moves the loop and shows in the log. Mouse, touch, keyboard, gamepads and TV remotes drive the buttons through the focus of the UI.
local assets = require('haylen.assets')
local audio = require('haylen.audio')
local haylen = require('haylen')
local mediaSession = require('media-session')
local scene = require('haylen.scene')
local ui = require('haylen.ui')

local Sample = {}
Sample.__index = Sample

local kMaxLines = 40
local kTrack = {title = 'Harbor at dawn', artist = 'The island band', album = 'Tides'}

function Sample.new()
    return setmetatable({lines = {}}, Sample)
end

-- Writes a line at the end of the log, which keeps its last lines.
function Sample:log(text)
    print(text)
    table.insert(self.lines, text)
    if #self.lines > kMaxLines then
        table.remove(self.lines, 1)
    end
    local labels = {}
    for index, line in ipairs(self.lines) do
        labels[index] = ui.label{text = line, font = 'caption', wrap = true}
    end
    self.gui:replaceChildren('lines', {ui.column{gap = 6, children = labels}})
    self.gui:command('log', 'scrollTo', {offset = 1e9, animated = false})
end

-- Shows the loop in the controls with where it plays and whether it plays, which the controls move on by themselves while it plays.
function Sample:show()
    mediaSession.setNowPlaying({
        title = kTrack.title,
        artist = kTrack.artist,
        album = kTrack.album,
        duration = self.sound.duration,
        position = audio.cursor(self.voice),
        playing = not audio.paused(self.voice),
        artwork = self.artwork,
        commands = {'play', 'pause', 'togglePlayPause', 'stop', 'next', 'previous', 'seek'},
    })
end

function Sample:setPlaying(playing)
    if playing then
        audio.resume(self.voice)
    else
        audio.pause(self.voice)
    end
    self:show()
end

-- Each command moves the loop: the play and pause commands play or pause it, a seek moves it, the next and the previous track start it again, and a stop pauses it at its start.
function Sample:receive(event)
    local position = event.position and string.format(' at %.1f seconds', event.position) or ''
    self:log(string.format('Command: %s%s.', event.command, position))

    if event.command == 'play' then
        self:setPlaying(true)
    elseif event.command == 'pause' then
        self:setPlaying(false)
    elseif event.command == 'togglePlayPause' then
        self:setPlaying(audio.paused(self.voice))
    elseif event.command == 'seek' then
        audio.setCursor(self.voice, event.position)
        self:show()
    elseif event.command == 'next' or event.command == 'previous' then
        audio.setCursor(self.voice, 0)
        self:show()
    elseif event.command == 'stop' then
        audio.setCursor(self.voice, 0)
        self:setPlaying(false)
    end
end

-- Reads back what the controls of the system show and writes it as one line, which the UI tests read.
function Sample:readControls()
    scene.spawn(self, function()
        local shown, err = mediaSession.nowPlaying():await()
        if err then
            self:log(string.format('Controls failed with the code "%s": %s', tostring(err.code), err.message))
            return
        end
        if shown == nil then
            self:log('Controls: nothing.')
            return
        end
        self:log(string.format('Controls: "%s" by "%s" from "%s", %.0f seconds, %s, %s.', shown.title, shown.artist, shown.album, shown.duration, shown.playing and 'playing' or 'paused', shown.artwork and 'with artwork' or 'without artwork'))
    end)
end

function Sample:enter()
    self.sound = assets.load('audio/harbor-loop.ogg')
    self.artwork = assets.bytes('logo.png')
    self.voice = audio.play(self.sound, {bus = 'music', loop = true})

    local actions = {
        {'Play or pause', function() self:setPlaying(audio.paused(self.voice)) end},
        {'Read the controls', function() self:readControls() end},
        {'Leave the controls', function()
            mediaSession.clear()
            self:log('The app left the controls.')
        end},
        {'Show again', function()
            self:show()
            self:log('The app shows the loop again.')
        end},
    }
    local buttons = {}
    for index, action in ipairs(actions) do
        buttons[index] = ui.button{id = 'action' .. index, text = action[1], onClick = action[2]}
    end

    self.gui = ui.mount(ui.safeArea{ui.column{
        gap = 24,
        padding = 32,
        ui.label{text = 'Media Session on "' .. haylen.platform .. '"', font = 'title'},
        ui.label{text = 'The loop shows in the now-playing controls of the system. Use them, the media keys or the buttons of a headset, and each command shows here.', color = 'textMuted', wrap = true},
        ui.row{gap = 16, wrap = true, children = buttons},
        ui.card{grow = 1, ui.scroll{id = 'log', grow = 1, ui.column{id = 'lines'}}},
    }}, {owner = self})

    -- Gamepads and TV remotes move the focus, so the first button starts with it.
    self.gui:command('action1', 'focus')

    mediaSession.on('command', function(event)
        self:receive(event)
    end, {owner = self})
    self:show()
    self:log('The loop plays and shows in the controls of the system.')
end

function Sample:exit()
    mediaSession.clear()
    audio.stop(self.voice)
    self.gui:unmount()
end

scene.push(Sample.new())
