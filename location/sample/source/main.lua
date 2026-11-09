-- The sample of the Location plugin: a button for every call of the plugin and of its permissions `location`, `preciseLocation` and `backgroundLocation`, the last place it read and the answer of each call. The buttons take the mouse, touch, the keyboard, gamepads and TV remotes.
local haylen = require('haylen')
local json = require('json')
local location = require('location')
local scene = require('haylen.scene')
local ui = require('haylen.ui')

local Sample = {}
Sample.__index = Sample

local kMaxLines = 40

-- Each button runs one call with the Lua that it shows, and a place that it answers shows on the card of the place.
Sample.actions = {
    {id = 'state', text = 'Read the permissions', code = "location.permission('location')", permissions = true},
    {id = 'request', text = 'Ask for the location', code = "location.requestPermission('location')", run = function() return location.requestPermission('location') end},
    {id = 'precise', text = 'Ask for the precise location', code = "location.requestPermission('preciseLocation')", run = function() return location.requestPermission('preciseLocation') end},
    {id = 'background', text = 'Ask for the location in the background', code = "location.requestPermission('backgroundLocation')", run = function() return location.requestPermission('backgroundLocation') end},
    {id = 'current', text = 'Read the location', code = 'location.current()', run = function() return location.current() end, place = true},
    {id = 'currentPrecise', text = 'Read the precise location', code = 'location.current({precise = true, timeout = 15})', run = function() return location.current({precise = true, timeout = 15}) end, place = true},
    {id = 'watch', text = 'Watch every 10 meters', code = 'location.watch({distance = 10, owner = self})', run = function(self) return location.watch({distance = 10, owner = self}) end},
    {id = 'watchBackground', text = 'Watch in the background too', code = 'location.watch({background = true, owner = self})', run = function(self) return location.watch({background = true, owner = self}) end},
    {id = 'stop', text = 'Stop watching', code = 'location.stop()', run = function() return location.stop() end},
}

function Sample.new()
    return setmetatable({lines = {}, updates = 0}, Sample)
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

-- A place leaves out what the device does not know, such as the altitude of a fix of the network.
local function describe(place)
    local parts = {string.format('Latitude %.6f, longitude %.6f, within %.0f m', place.latitude, place.longitude, place.accuracy)}
    if place.altitude then
        parts[#parts + 1] = string.format('Altitude %.1f m', place.altitude)
    end
    if place.speed then
        parts[#parts + 1] = string.format('Speed %.1f m/s', place.speed)
    end
    if place.heading then
        parts[#parts + 1] = string.format('Heading %.0f degrees', place.heading)
    end
    parts[#parts + 1] = 'At ' .. os.date('%H:%M:%S', math.floor(place.timestamp))
    return table.concat(parts, '\n')
end

function Sample:showPlace(place, source)
    self.gui:set('place', {text = describe(place)})
    self.gui:set('source', {text = source})
end

-- A platform call fails with a table that holds the message and the code.
local function describeFailure(err)
    return string.format('failed with "%s": %s', tostring(err.code), err.message)
end

-- Reads the three permissions one after another, so each state shows next to its name.
function Sample:readPermissions()
    scene.spawn(self, function()
        for _, name in ipairs({'location', 'preciseLocation', 'backgroundLocation'}) do
            local state, err = location.permission(name):await()
            if state then
                self:log(string.format('The permission "%s" is "%s".', name, state))
            else
                self:log(string.format('The permission "%s" %s', name, describeFailure(err)))
            end
        end
    end)
end

function Sample:run(action)
    if action.permissions then
        self:readPermissions()
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
            self:log(string.format('The call "%s" %s', action.code, describeFailure(err)))
            return
        end
        self:log(string.format('The call "%s" answered %s.', action.code, json.encode(result)))
        if action.place then
            self:showPlace(result, 'One fix of "location.current".')
        end
    end)
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
        ui.label{text = 'Location on "' .. haylen.platform .. '"', font = 'title'},
        ui.label{text = 'Each button runs one call of the plugin. The last place shows on the card, and every answer arrives below it.', color = 'textMuted', wrap = true},
        ui.row{grow = 1, gap = 24, align = 'stretch',
            ui.scroll{width = 560, grow = 0, align = 'stretch', ui.column{gap = 12, alignItems = 'stretch', children = buttons}},
            ui.column{grow = 1, gap = 24, align = 'stretch',
                ui.card{ui.column{gap = 12,
                    ui.label{id = 'place', text = 'No place yet.', font = 'heading', wrap = true},
                    ui.label{id = 'source', text = 'Read the location or watch it.', color = 'textMuted', wrap = true},
                }},
                ui.card{grow = 1, ui.scroll{grow = 1, height = 0, ui.column{id = 'lines'}}},
            },
        },
    }})

    -- The updates of a frame arrive as one list, oldest first, so the newest place is the last one.
    location.onChanged(function(places)
        self.updates = self.updates + #places
        self:showPlace(places[#places], string.format('Update %d of "location.watch".', self.updates))
    end, {owner = self})

    location.onStopped(function(stopped)
        self:log(string.format('The updates stopped with "%s": %s', stopped.code, stopped.message))
    end, {owner = self})

    -- Gamepads and TV remotes move the focus, so the first button starts with it.
    self.gui:command('state', 'focus')
    self:log('Press a button to run its call. The updates of a watch end with this scene, their owner.')
end

function Sample:exit()
    self.gui:unmount()
end

scene.push(Sample.new())
