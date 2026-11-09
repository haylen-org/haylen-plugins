-- The sample of the Google Analytics plugin: a button for every call, and a log of every answer. Mouse, touch, keyboard, gamepads and TV remotes drive the buttons through the focus of the UI.
local analytics = require('google-analytics')
local haylen = require('haylen')
local json = require('json')
local scene = require('haylen.scene')
local ui = require('haylen.ui')

local Sample = {}
Sample.__index = Sample

local kMaxLines = 40

function Sample.new()
    return setmetatable({lines = {}, level = 0}, Sample)
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

-- Runs a call of the plugin and logs its answer.
function Sample:run(name, start)
    local call = start()
    scene.spawn(self, function()
        local result, err = call:await()
        if err then
            self:log(string.format('%s failed with the code "%s": %s', name, tostring(err.code), err.message))
            return
        end
        self:log(string.format('%s: %s', name, result == nil and 'sent' or json.encode(result)))
    end)
end

function Sample:levelUp()
    self.level = self.level + 1
    return analytics.logEvent('level_up', {level = self.level})
end

function Sample:enter()
    local actions = {
        {'Level up', function() return self:levelUp() end},
        {'Select content', function() return analytics.logEvent('select_content', {content_type = 'chapter', content_id = 'two'}) end},
        {'Sign in', function() return analytics.setUserId('player-1') end},
        {'Sign out', function() return analytics.setUserId(nil) end},
        {'Free plan', function() return analytics.setUserProperties({plan = 'free'}) end},
        {'Allow all', function() return analytics.setConsent({analyticsStorage = 'granted', adStorage = 'granted', adUserData = 'granted', adPersonalization = 'granted'}) end},
        {'Deny ads', function() return analytics.setConsent({adStorage = 'denied', adUserData = 'denied', adPersonalization = 'denied'}) end},
        {'Client ID', analytics.clientId},
    }
    local buttons = {}
    for index, action in ipairs(actions) do
        buttons[index] = ui.button{id = 'action' .. index, text = action[1], onClick = function() self:run(action[1], action[2]) end}
    end

    local available = analytics.available and 'Google Analytics runs here.' or ('The plugin has no native part on "' .. haylen.platform .. '", so its calls fail with "noHandler".')
    self.gui = ui.mount(ui.safeArea{ui.column{
        gap = 24,
        padding = 32,
        ui.label{text = 'Google Analytics on "' .. haylen.platform .. '"', font = 'title'},
        ui.label{text = available, color = 'textMuted', wrap = true},
        ui.row{gap = 16, wrap = true, children = buttons},
        ui.card{grow = 1, ui.scroll{id = 'log', grow = 1, ui.column{id = 'lines'}}},
    }}, {owner = self})

    -- Gamepads and TV remotes move the focus, so the first button starts with it.
    self.gui:command('action1', 'focus')
    self:log('Press a button to send it to the measurement ID of "haylen.json", whose requests the network panel of the browser shows.')
end

function Sample:exit()
    self.gui:unmount()
end

scene.push(Sample.new())
