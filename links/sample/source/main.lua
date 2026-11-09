-- The sample of the Links plugin: a button for each kind of url that `links.open` takes, and the answer of each call with the frames it took. The buttons take the mouse, touch, the keyboard, gamepads and TV remotes.
local haylen = require('haylen')
local links = require('links')
local scene = require('haylen.scene')
local ui = require('haylen.ui')

local Sample = {}
Sample.__index = Sample

local kMaxLines = 40

-- Each button opens one url: a web page, a mail to write, a scheme that no app takes, and an empty url, which raises.
Sample.urls = {
    {id = 'page', text = 'Open a web page', url = 'https://example.com'},
    {id = 'mail', text = 'Write a mail', url = 'mailto:hello@example.com?subject=Links'},
    {id = 'nothing', text = 'Open an address no app takes', url = 'haylen-links-nothing://open'},
    {id = 'empty', text = 'Open an empty url', url = ''},
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

-- Opens the url in a task of the scene, which waits for the answer and ends with the scene. A url that is not one, such as an empty text, raises at once.
function Sample:open(url)
    local started, call = pcall(links.open, url)
    if not started then
        self:log(string.format('The call raised: %s', call))
        return
    end

    local frame = haylen.frameIndex()
    self:log(string.format('Opening "%s".', url))
    scene.spawn(self, function()
        local _, err = call:await()
        local count = haylen.frameIndex() - frame
        local frames = count == 1 and '1 frame' or string.format('%d frames', count)
        if err then
            self:log(string.format('It failed with "%s" after %s: %s', tostring(err.code), frames, err.message))
            return
        end
        self:log(string.format('An app took "%s" after %s.', url, frames))
    end)
end

function Sample:enter()
    local buttons = {}
    for index, entry in ipairs(Sample.urls) do
        buttons[index] = ui.button{id = entry.id, text = entry.text, variant = index == 1 and 'primary' or nil, onClick = function() self:open(entry.url) end}
    end

    self.gui = ui.mount(ui.safeArea{ui.column{
        grow = 1,
        gap = 24,
        padding = 32,
        ui.label{text = 'Links on "' .. haylen.platform .. '"', font = 'title'},
        ui.label{text = 'Each button opens a url with the app that the system picks for it, and the answer arrives below.', color = 'textMuted', wrap = true},
        ui.row{grow = 1, gap = 24, align = 'stretch',
            ui.column{width = 520, gap = 12, align = 'start', alignItems = 'stretch', children = buttons},
            ui.card{grow = 1, align = 'stretch', ui.scroll{grow = 1, height = 0, ui.column{id = 'lines'}}},
        },
    }})

    -- Gamepads and TV remotes move the focus, so the first button starts with it.
    self.gui:command('page', 'focus')
    self:log('Press a button to open its url.')
end

function Sample:exit()
    self.gui:unmount()
end

scene.push(Sample.new())
