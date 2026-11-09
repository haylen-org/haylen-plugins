-- The sample of the Motion plugin: a button for every call of the plugin, the answer of each one, which says why where the device cannot run the sensors, and the newest readings and the tilt, which the action map also reads through a virtual stick. The buttons take the mouse, touch, the keyboard, gamepads and TV remotes.
local haylen = require('haylen')
local input = require('haylen.input')
local motion = require('motion')
local scene = require('haylen.scene')
local ui = require('haylen.ui')

local Sample = {}
Sample.__index = Sample

local kMaxLines = 40
local kAllSensors = {'accelerometer', 'gyroscope', 'attitude'}

-- Each button runs one call with the Lua that it calls. A start answers once the sensors run, and the last one passes a rate that raises.
Sample.actions = {
    {id = 'accelerometer', text = 'Start the accelerometer', code = "motion.start({sensors = {'accelerometer'}, owner = self})", run = function(self) return motion.start({sensors = {'accelerometer'}, owner = self}) end},
    {id = 'all', text = 'Start every sensor', code = "motion.start({sensors = {'accelerometer', 'gyroscope', 'attitude'}, rate = 100, owner = self})", run = function(self) return motion.start({sensors = kAllSensors, rate = 100, owner = self}) end},
    {id = 'slow', text = 'Start every sensor at 10 per second', code = "motion.start({sensors = {'accelerometer', 'gyroscope', 'attitude'}, rate = 10, owner = self})", run = function(self) return motion.start({sensors = kAllSensors, rate = 10, owner = self}) end},
    {id = 'stop', text = 'Stop the sensors', code = 'motion.stop()', run = function() motion.stop() end},
    {id = 'state', text = 'Check the permission', code = 'motion.permission()', run = function() return motion.permission() end},
    {id = 'ask', text = 'Ask for the permission', code = 'motion.requestPermission()', run = function() return motion.requestPermission() end},
    {id = 'calibrate', text = 'Take this angle as level', code = 'motion.calibrateTilt()', run = function() return motion.calibrateTilt() end},
    {id = 'reset', text = 'Level is face up', code = 'motion.resetTilt()', run = function() motion.resetTilt() end},
    {id = 'invalid', text = 'Start at 500 per second', code = 'motion.start({rate = 500})', run = function() return motion.start({rate = 500}) end},
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

-- Logs what a call answered: a platform call answers in a task of the scene, which ends with the scene, and any other value at once. A platform call fails with an error that holds its code, and invalid arguments raise at once.
function Sample:run(action)
    local ran, result = pcall(action.run, self)
    if not ran then
        self:log(string.format('The call "%s" raised: %s', action.code, result))
        return
    end

    if type(result) ~= 'userdata' and type(result) ~= 'table' then
        self:log(string.format('The call "%s" answered %s.', action.code, tostring(result)))
        return
    end

    scene.spawn(self, function()
        local value, err = result:await()
        if err then
            self:log(string.format('The call "%s" failed with "%s": %s', action.code, tostring(err.code), err.message))
            return
        end
        if type(value) == 'table' then
            self:log(string.format('The call "%s" runs %s.', action.code, table.concat(value.sensors, ', ')))
            return
        end
        self:log(string.format('The call "%s" answered "%s".', action.code, tostring(value)))
    end)
end

function Sample:enter()
    local buttons = {}
    for index, action in ipairs(Sample.actions) do
        buttons[index] = ui.button{id = action.id, text = action.text, variant = index == 1 and 'primary' or nil, onClick = function() self:run(action) end}
    end

    -- The tilt of the device drives a virtual stick, which the action map reads next to the arrows and the left stick.
    input.loadActions({actions = {
        {name = 'roll', type = 'vector', left = {'key:left'}, right = {'key:right'}, up = {'key:up'}, down = {'key:down'}, bindings = {'stick:left', 'virtualStick:tilt'}},
    }})

    self.gui = ui.mount(ui.safeArea{ui.column{
        grow = 1,
        gap = 24,
        padding = 32,
        ui.label{text = 'Motion on "' .. haylen.platform .. '"', font = 'title'},
        ui.label{text = 'Each button runs a call of the plugin, and the answer arrives below. Move the device to see the readings change.', color = 'textMuted', wrap = true},
        ui.row{grow = 1, gap = 24, align = 'stretch',
            ui.scroll{width = 520, grow = 0, align = 'stretch', ui.column{gap = 12, alignItems = 'stretch', children = buttons}},
            ui.column{grow = 1, gap = 24, align = 'stretch',
                ui.card{ui.column{gap = 8,
                    ui.label{id = 'sensors', text = 'No sensor delivered readings.'},
                    ui.label{id = 'acceleration', text = 'Acceleration'},
                    ui.label{id = 'rotation', text = 'Rotation rate'},
                    ui.label{id = 'attitude', text = 'Attitude'},
                    ui.label{id = 'tilt', text = 'Tilt'},
                }},
                ui.card{grow = 1, ui.scroll{grow = 1, height = 0, ui.column{id = 'lines'}}},
            },
        },
    }})

    -- Gamepads and TV remotes move the focus, so the first button starts with it.
    self.gui:command('accelerometer', 'focus')
    self:log(motion.available and 'Press a button to start the sensors.' or 'The plugin has no native part on this platform, so its calls fail.')
end

function Sample:update()
    local tiltX, tiltY = motion.tilt()
    input.setVirtualStick('tilt', tiltX, tiltY)

    local sensors = motion.sensors()
    local ax, ay, az = motion.acceleration()
    local rx, ry, rz = motion.rotationRate()
    local qx, qy, qz, qw = motion.attitude()
    local rollX, rollY = input.vector('roll')

    self.gui:set('sensors', {text = #sensors > 0 and 'Readings from ' .. table.concat(sensors, ', ') .. '.' or 'No sensor delivered readings.'})
    self.gui:set('acceleration', {text = string.format('Acceleration %.2f, %.2f, %.2f meters per second squared', ax, ay, az)})
    self.gui:set('rotation', {text = string.format('Rotation rate %.2f, %.2f, %.2f radians per second', rx, ry, rz)})
    self.gui:set('attitude', {text = string.format('Attitude %.2f, %.2f, %.2f, %.2f', qx, qy, qz, qw)})
    self.gui:set('tilt', {text = string.format('Tilt %.2f, %.2f, and the action "roll" reads %.2f, %.2f', tiltX, tiltY, rollX, rollY)})
end

function Sample:exit()
    self.gui:unmount()
end

scene.push(Sample.new())
