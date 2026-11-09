-- The sample of the Permissions plugin: for each permission of the local plugin `permission-states`, which owns one of every state, a button that checks it, one that asks for it and one that uses it, and a log of every answer. The buttons take the mouse, touch, the keyboard, gamepads and TV remotes.
local haylen = require('haylen')
local permissions = require('permissions')
local scene = require('haylen.scene')
local states = require('permission-states')
local ui = require('haylen.ui')

local Sample = {}
Sample.__index = Sample

local kMaxLines = 40

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

-- A platform call of the Permissions plugin answers the state, or fails with the code `unsupported` and the reason on a platform without the capability.
function Sample:state(code, start)
    local started, call = pcall(start)
    if not started then
        self:log(string.format('The call "%s" raised: %s', code, call))
        return
    end

    scene.spawn(self, function()
        local state, failure = call:await()
        if state then
            self:log(string.format('The call "%s" answered "%s".', code, state))
        else
            self:log(string.format('The call "%s" failed with "%s": %s', code, tostring(failure.code), failure.message))
        end
    end)
end

-- A platform call of the local plugin answers a sentence once the plugin holds the permission, or fails with the code `denied` or `unsupported`.
function Sample:use(name)
    local code = string.format("states.use('%s')", name)
    scene.spawn(self, function()
        local used, err = states.use(name):await()
        if used then
            self:log(string.format('The call "%s" answered: %s', code, used))
        else
            self:log(string.format('The call "%s" failed with "%s": %s', code, tostring(err.code), err.message))
        end
    end)
end

function Sample:enter()
    local rows = {}
    for index, name in ipairs(states.names) do
        rows[index] = ui.row{gap = 12, wrap = true, alignItems = 'center',
            ui.button{id = name .. 'State', text = 'Check ' .. name, onClick = function()
                self:state(string.format("states.permission('%s')", name), function() return states.permission(name) end)
            end},
            ui.button{id = name .. 'Request', text = 'Ask for ' .. name, onClick = function()
                self:state(string.format("states.requestPermission('%s')", name), function() return states.requestPermission(name) end)
            end},
            ui.button{id = name .. 'Use', text = 'Use ' .. name, onClick = function() self:use(name) end},
        }
    end
    rows[#rows + 1] = ui.row{gap = 12, wrap = true,
        ui.button{id = 'byName', text = "Check permissions.state('asked')", onClick = function()
            self:state("permissions.state('asked')", function() return permissions.state('asked') end)
        end},
        ui.button{id = 'unknownName', text = "Check permissions.state('nobody')", onClick = function()
            self:state("permissions.state('nobody')", function() return permissions.state('nobody') end)
        end},
    }

    self.gui = ui.mount(ui.safeArea{ui.column{
        gap = 24,
        padding = 32,
        ui.label{text = 'Permissions on "' .. haylen.platform .. '"', font = 'title'},
        ui.label{text = 'Each row checks, asks for and uses one permission of the local plugin. The permission "asked" is the one of notifications, so asking shows the prompt of the system once.', color = 'textMuted', wrap = true},
        ui.column{gap = 12, children = rows},
        ui.card{grow = 1, ui.scroll{id = 'log', grow = 1, ui.column{id = 'lines'}}},
    }}, {owner = self})

    -- Gamepads and TV remotes move the focus, so the first button starts with it.
    self.gui:command('heldState', 'focus')
    self:log('Press a button to run its call.')
end

function Sample:exit()
    self.gui:unmount()
end

scene.push(Sample.new())
