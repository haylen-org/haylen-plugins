-- The sample of the Haptics plugin: a button for every call of the plugin, and the answer of each one, which says why where the device cannot play it. The buttons take the mouse, touch, the keyboard, gamepads and TV remotes.
local haylen = require('haylen')
local haptics = require('haptics')
local scene = require('haylen.scene')
local ui = require('haylen.ui')

local Sample = {}
Sample.__index = Sample

local kMaxLines = 40

-- Each button plays one feedback with the Lua that calls it, and the last one passes a vibration that raises.
Sample.actions = {
    {id = 'short', text = 'Vibrate for 80 ms', code = 'haptics.vibrate(0.08)', play = function() return haptics.vibrate(0.08) end},
    {id = 'long', text = 'Vibrate for 1 second', code = 'haptics.vibrate(1)', play = function() return haptics.vibrate(1) end},
    {id = 'light', text = 'Light impact', code = "haptics.impact('light')", play = function() return haptics.impact('light') end},
    {id = 'medium', text = 'Medium impact', code = "haptics.impact('medium')", play = function() return haptics.impact('medium') end},
    {id = 'heavy', text = 'Heavy impact', code = "haptics.impact('heavy')", play = function() return haptics.impact('heavy') end},
    {id = 'selection', text = 'Selection tick', code = 'haptics.selection()', play = function() return haptics.selection() end},
    {id = 'success', text = 'Success', code = "haptics.notification('success')", play = function() return haptics.notification('success') end},
    {id = 'warning', text = 'Warning', code = "haptics.notification('warning')", play = function() return haptics.notification('warning') end},
    {id = 'error', text = 'Error', code = "haptics.notification('error')", play = function() return haptics.notification('error') end},
    {id = 'invalid', text = 'Vibrate for 0 seconds', code = 'haptics.vibrate(0)', play = function() return haptics.vibrate(0) end},
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

-- Plays the feedback in a task of the scene, which waits for the answer and ends with the scene. Invalid arguments raise at once.
function Sample:play(action)
    local started, call = pcall(action.play)
    if not started then
        self:log(string.format('The call "%s" raised: %s', action.code, call))
        return
    end

    scene.spawn(self, function()
        local _, err = call:await()
        if err then
            self:log(string.format('The call "%s" failed with "%s": %s', action.code, tostring(err.code), err.message))
            return
        end
        self:log(string.format('The call "%s" played.', action.code))
    end)
end

function Sample:enter()
    local buttons = {}
    for index, action in ipairs(Sample.actions) do
        buttons[index] = ui.button{id = action.id, text = action.text, variant = index == 1 and 'primary' or nil, onClick = function() self:play(action) end}
    end

    self.gui = ui.mount(ui.safeArea{ui.column{
        grow = 1,
        gap = 24,
        padding = 32,
        ui.label{text = 'Haptics on "' .. haylen.platform .. '"', font = 'title'},
        ui.label{text = 'Each button plays a vibration or a feedback of the haptic engine, and the answer arrives below.', color = 'textMuted', wrap = true},
        ui.row{grow = 1, gap = 24, align = 'stretch',
            ui.scroll{width = 520, grow = 0, align = 'stretch', ui.column{gap = 12, alignItems = 'stretch', children = buttons}},
            ui.card{grow = 1, align = 'stretch', ui.scroll{grow = 1, height = 0, ui.column{id = 'lines'}}},
        },
    }})

    -- Gamepads and TV remotes move the focus, so the first button starts with it.
    self.gui:command('short', 'focus')
    self:log('Press a button to play its feedback.')
end

function Sample:exit()
    self.gui:unmount()
end

scene.push(Sample.new())
