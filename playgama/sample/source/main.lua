-- The sample of the Playgama Bridge plugin: a button for every call, and a log of every answer and event. Mouse, touch, keyboard, gamepads and TV remotes drive the buttons through the focus of the UI.
local haylen = require('haylen')
local json = require('json')
local playgama = require('playgama')
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

-- Runs a call of the plugin and logs its answer.
function Sample:run(name, start)
    local call = start()
    scene.spawn(self, function()
        local result, err = call:await()
        if err then
            self:log(string.format('%s failed with the code "%s": %s', name, tostring(err.code), err.message))
            return
        end
        self:log(string.format('%s: %s', name, result == nil and 'done' or json.encode(result)))
    end)
end

function Sample:enter()
    local actions = {
        {'Platform', playgama.platform},
        {'Player', playgama.player},
        {'Sign in', playgama.authorizePlayer},
        {'Game ready', function() return playgama.sendMessage('gameReady') end},
        {'Level started', function() return playgama.sendMessage('levelStarted') end},
        {'Interstitial', playgama.showInterstitial},
        {'Rewarded', playgama.showRewarded},
        {'Show banner', playgama.showBanner},
        {'Hide banner', playgama.hideBanner},
        {'Save level', function() return playgama.storageSet('level', json.encode({number = 3, stars = 2})) end},
        {'Read level', function() return playgama.storageGet('level') end},
        {'Delete level', function() return playgama.storageDelete('level') end},
    }
    local buttons = {}
    for index, action in ipairs(actions) do
        buttons[index] = ui.button{id = 'action' .. index, text = action[1], onClick = function() self:run(action[1], action[2]) end}
    end

    local available = playgama.available and 'The bridge runs here.' or ('The plugin has no native part on "' .. haylen.platform .. '", so its calls fail with "noHandler".')
    self.gui = ui.mount(ui.safeArea{ui.column{
        gap = 24,
        padding = 32,
        ui.label{text = 'Playgama Bridge on "' .. haylen.platform .. '"', font = 'title'},
        ui.label{text = available, color = 'textMuted', wrap = true},
        ui.row{gap = 16, wrap = true, children = buttons},
        ui.card{grow = 1, ui.scroll{id = 'log', grow = 1, ui.column{id = 'lines'}}},
    }}, {owner = self})

    playgama.onPauseChanged(function(state) self:log('The platform paused the game: ' .. tostring(state.paused) .. '.') end, {owner = self})
    playgama.onAudioChanged(function(state) self:log('The platform turned the sound on: ' .. tostring(state.enabled) .. '.') end, {owner = self})
    playgama.onBannerChanged(function(state) self:log('The banner is "' .. state.state .. '".') end, {owner = self})

    -- Gamepads and TV remotes move the focus, so the first button starts with it.
    self.gui:command('action1', 'focus')
    self:log('Press "Game ready" first, since the platforms show ads only to a game that is ready.')
end

function Sample:exit()
    self.gui:unmount()
end

scene.push(Sample.new())
