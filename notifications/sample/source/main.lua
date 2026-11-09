-- The sample of the Notifications plugin: a button for every call of the plugin and of the permission, and a log of every answer and of every tap on a notification, also the tap that launched the app. Mouse, touch, keyboard, gamepads and TV remotes drive the buttons through the focus of the UI.
local haylen = require('haylen')
local json = require('json')
local notifications = require('notifications')
local scene = require('haylen.scene')
local ui = require('haylen.ui')

local Sample = {}
Sample.__index = Sample

local kMaxLines = 40

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

-- Awaits the call that `start` returns and logs its answer or its failure under the name of the action, with the state of a permission as it is.
function Sample:try(name, start)
    scene.spawn(self, function()
        local result, err = start():await()
        if err then
            self:log(string.format('%s failed with the code "%s": %s', name, tostring(err.code), err.message))
            return
        end
        local answer = type(result) == 'string' and result or result == nil and 'nil' or json.encode(result)
        self:log(string.format('%s: %s', name, answer))
    end)
end

function Sample:enter()
    local actions = {
        {'Permission', function() self:try('Permission', notifications.permission) end},
        {'Ask', function() self:try('Ask', notifications.requestPermission) end},
        {'In 5 seconds', function()
            self:try('In 5 seconds', function()
                return notifications.schedule({id = 'soon', title = 'Five seconds passed', body = 'Tap to open the sample.', seconds = 5, data = {from = 'soon'}})
            end)
        end},
        {'In a minute, silent', function()
            self:try('In a minute', function()
                return notifications.schedule({id = 'minute', title = 'A minute passed', body = 'This one came at a date, without a sound.', date = os.time() + 60, sound = false, badge = 1, data = {from = 'minute'}})
            end)
        end},
        {'Pending', function() self:try('Pending', notifications.pending) end},
        {'Delivered', function() self:try('Delivered', notifications.delivered) end},
        {'Cancel the minute', function() self:try('Cancel', function() return notifications.cancel('minute') end) end},
        {'Cancel all', function() self:try('Cancel all', notifications.cancelAll) end},
    }
    local buttons = {}
    for index, action in ipairs(actions) do
        buttons[index] = ui.button{id = 'action' .. index, text = action[1], onClick = action[2]}
    end

    local available = notifications.available and 'The native part runs here.' or ('The plugin has no native part on "' .. haylen.platform .. '", so its calls fail with "noHandler".')
    self.gui = ui.mount(ui.safeArea{ui.column{
        gap = 24,
        padding = 32,
        ui.label{text = 'Notifications on "' .. haylen.platform .. '"', font = 'title'},
        ui.label{text = available, color = 'textMuted', wrap = true},
        ui.row{gap = 16, wrap = true, children = buttons},
        ui.card{grow = 1, ui.scroll{id = 'log', grow = 1, ui.column{id = 'lines'}}},
    }}, {owner = self})

    -- Gamepads and TV remotes move the focus, so the first button starts with it.
    self.gui:command('action1', 'focus')

    -- The tap that launched the app waited for this listener.
    notifications.onOpened(function(event)
        self:log('Opened: ' .. json.encode(event))
    end, {owner = self})
    self:log('Schedule a notification, then leave the app or stay, and tap it when it shows.')
end

function Sample:exit()
    self.gui:unmount()
end

scene.push(Sample.new())
