-- The sample of the Microphone plugin: a button for every call of the plugin and of the permission `microphone`, the level of the microphone in two bars, a voice that plays the recording back and the answer of each call. The buttons take the mouse, touch, the keyboard, gamepads and TV remotes.
local audio = require('haylen.audio')
local haylen = require('haylen')
local json = require('json')
local microphone = require('microphone')
local scene = require('haylen.scene')
local ui = require('haylen.ui')

local Sample = {}
Sample.__index = Sample

local kMaxLines = 40

-- Each button runs one call with the Lua that it shows. Playing the recording back is a voice of `haylen.audio`, so it answers at once.
Sample.actions = {
    {id = 'state', text = 'Read the permission', code = 'microphone.permission()', run = function() return microphone.permission() end},
    {id = 'request', text = 'Ask for the microphone', code = 'microphone.requestPermission()', run = function() return microphone.requestPermission() end},
    {id = 'start', text = 'Start at 48000 Hz', code = 'microphone.start({owner = self})', run = function(self) return microphone.start({owner = self}) end},
    {id = 'speech', text = 'Start at 16000 Hz', code = 'microphone.start({sampleRate = 16000, owner = self})', run = function(self) return microphone.start({sampleRate = 16000, owner = self}) end},
    {id = 'play', text = 'Play it back', code = 'microphone.stream():play()', playback = true},
    {id = 'quiet', text = 'Stop playing it back', code = 'audio.stop(voice)', playback = true},
    {id = 'stop', text = 'Stop the microphone', code = 'microphone.stop()', run = function() return microphone.stop() end},
}

function Sample.new()
    return setmetatable({lines = {}}, Sample)
end

function Sample:log(text)
    print(text)
    table.insert(self.lines, 1, text)
    self.lines[kMaxLines + 1] = nil
    local labels = {}
    for index, line in ipairs(self.lines) do
        labels[index] = ui.label{text = line, font = 'caption', wrap = true}
    end
    self.gui:replaceChildren('lines', {ui.column{gap = 8, children = labels}})
end

-- The voice plays what the microphone records, which loops back into it without headphones.
function Sample:playBack(action)
    if action.id == 'quiet' then
        if self.voice then
            audio.stop(self.voice)
            self.voice = nil
        end
        self:log('The recording no longer plays back.')
        return
    end

    local stream = microphone.stream()
    if not stream then
        self:log('No microphone runs yet, so nothing plays back.')
        return
    end
    if self.voice then
        audio.stop(self.voice)
    end
    self.voice = stream:play({volume = 0.8})
    self:log(string.format('The recording of %d Hz plays back.', stream.sampleRate))
end

function Sample:run(action)
    if action.playback then
        self:playBack(action)
        return
    end

    local started, call = pcall(action.run, self)
    if not started then
        self:log(string.format('The call "%s" raised: %s', action.code, call))
        return
    end

    scene.spawn(self, function()
        local result, err = call:await()
        if err then
            self:log(string.format('The call "%s" failed with "%s": %s', action.code, tostring(err.code), err.message))
            return
        end
        self:log(string.format('The call "%s" answered %s.', action.code, json.encode(result)))
    end)
end

-- The bars follow the root mean square and the peak of the newest samples, which `microphone.level` reads from the stream each frame.
function Sample:update()
    local rms, peak = microphone.level()
    self.gui:set('rms', {value = math.min(rms * 4, 1), text = string.format('Level %.3f', rms)})
    self.gui:set('peak', {value = peak, text = string.format('Peak %.3f', peak)})
end

function Sample:enter()
    local buttons = {}
    for index, action in ipairs(Sample.actions) do
        buttons[index] = ui.button{id = action.id, text = action.text, variant = index == 1 and 'primary' or nil, onClick = function() self:run(action) end}
    end

    self.gui = ui.mount(ui.safeArea{ui.column{
        grow = 1,
        gap = 24,
        padding = 32,
        ui.label{text = 'Microphone on "' .. haylen.platform .. '"', font = 'title'},
        ui.label{text = 'Each button runs one call of the plugin. The bars show the level of the microphone, and every answer arrives below them.', color = 'textMuted', wrap = true},
        ui.row{grow = 1, gap = 24, align = 'stretch',
            ui.scroll{width = 520, grow = 0, align = 'stretch', ui.column{gap = 12, alignItems = 'stretch', children = buttons}},
            ui.column{grow = 1, gap = 24, align = 'stretch',
                ui.card{ui.column{gap = 16, alignItems = 'stretch',
                    ui.progress{id = 'rms', value = 0, text = 'Level 0.000'},
                    ui.progress{id = 'peak', value = 0, tone = 'warning', text = 'Peak 0.000'},
                }},
                ui.card{grow = 1, ui.scroll{grow = 1, height = 0, ui.column{id = 'lines'}}},
            },
        },
    }})

    microphone.onStopped(function(stopped)
        self:log(string.format('The microphone stopped with "%s": %s', stopped.code, stopped.message))
    end, {owner = self})

    -- Gamepads and TV remotes move the focus, so the first button starts with it.
    self.gui:command('state', 'focus')
    self:log('Press a button to run its call. The recording of a start ends with this scene, its owner.')
end

function Sample:exit()
    if self.voice then
        audio.stop(self.voice)
    end
    self.gui:unmount()
end

scene.push(Sample.new())
