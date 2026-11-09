-- The sample of the Share plugin: a button for every kind of share, with the sheet over the button that opened it, and a log of every answer. Mouse, touch, keyboard, gamepads and TV remotes drive the buttons through the focus of the UI.
local assets = require('haylen.assets')
local haylen = require('haylen')
local json = require('json')
local scene = require('haylen.scene')
local share = require('share')
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

-- Shares from the button `id`, whose rectangle anchors the sheet on iPad and on the Mac, and logs the answer.
function Sample:share(id, name, options)
    options.anchor = self.gui:bounds(id)
    local call = share.share(options)
    scene.spawn(self, function()
        local result, err = call:await()
        if err then
            self:log(string.format('%s failed with the code "%s": %s', name, tostring(err.code), err.message))
        else
            self:log(string.format('%s: %s', name, json.encode(result)))
        end
    end)
end

function Sample:enter()
    local actions = {
        {'Text', {text = 'Shared from the sample of the Share plugin.', title = 'A text'}},
        {'Link', {url = 'https://github.com/haylen-org/haylen', title = 'Haylen'}},
        {'Text and link', {text = 'Made with Haylen.', url = 'https://github.com/haylen-org/haylen'}},
        {'Image', {files = {{name = 'logo.png', type = 'image/png', bytes = assets.bytes('logo.png')}}, title = 'The logo'}},
        {'Two files', {files = {{name = 'logo.png', type = 'image/png', bytes = assets.bytes('logo.png')}, {name = 'notes.txt', type = 'text/plain', bytes = 'Notes of the sample.\n'}}}},
    }
    local buttons = {}
    for index, action in ipairs(actions) do
        local id = 'action' .. index
        buttons[index] = ui.button{id = id, text = action[1], onClick = function() self:share(id, action[1], action[2]) end}
    end

    local available = share.available and 'The native part runs here.' or ('The plugin has no native part on "' .. haylen.platform .. '", so its calls fail with "noHandler".')
    self.gui = ui.mount(ui.safeArea{ui.column{
        gap = 24,
        padding = 32,
        ui.label{text = 'Share on "' .. haylen.platform .. '"', font = 'title'},
        ui.label{text = available, color = 'textMuted', wrap = true},
        ui.row{gap = 16, wrap = true, children = buttons},
        ui.card{grow = 1, ui.scroll{id = 'log', grow = 1, ui.column{id = 'lines'}}},
    }}, {owner = self})

    -- Gamepads and TV remotes move the focus, so the first button starts with it.
    self.gui:command('action1', 'focus')
    self:log('Press a button to open the share sheet of the system.')
end

function Sample:exit()
    self.gui:unmount()
end

scene.push(Sample.new())
