-- The sample of the Camera plugin: a button for every call of the plugin and of the permission `camera`, the picture of the camera that runs, the last photo and the answer of each call. The buttons take the mouse, touch, the keyboard, gamepads and TV remotes.
local camera = require('camera')
local graphics = require('haylen.graphics')
local haylen = require('haylen')
local json = require('json')
local scene = require('haylen.scene')
local ui = require('haylen.ui')

local Sample = {}
Sample.__index = Sample

local kMaxLines = 40

-- Each button runs one call with the Lua that it shows, and what the answer changes on the screen.
Sample.actions = {
    {id = 'state', text = 'Read the permission', code = 'camera.permission()', run = function() return camera.permission() end},
    {id = 'request', text = 'Ask for the camera', code = 'camera.requestPermission()', run = function() return camera.requestPermission() end},
    {id = 'cameras', text = 'List the cameras', code = 'camera.cameras()', run = function() return camera.cameras() end},
    {id = 'default', text = 'Start the default camera', code = 'camera.start({owner = self})', run = function(self) return camera.start({owner = self}) end, started = true},
    {id = 'front', text = 'Start the front camera', code = "camera.start({facing = 'front', owner = self})", run = function(self) return camera.start({facing = 'front', owner = self}) end, started = true},
    {id = 'back', text = 'Start the back camera', code = "camera.start({facing = 'back', owner = self})", run = function(self) return camera.start({facing = 'back', owner = self}) end, started = true},
    {id = 'large', text = 'Start at 1280 by 720', code = 'camera.start({width = 1280, height = 720, owner = self})', run = function(self) return camera.start({width = 1280, height = 720, owner = self}) end, started = true},
    {id = 'photo', text = 'Take a photo', code = 'camera.takePhoto()', run = function() return camera.takePhoto() end, photo = true},
    {id = 'stop', text = 'Stop the camera', code = 'camera.stop()', run = function() return camera.stop() end},
}

function Sample.new()
    return setmetatable({lines = {}, photos = 0}, Sample)
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

-- The video stream of the plugin opens with the first camera of the process, and its texture shows the newest frame from then on, in place, whatever size the frames have.
function Sample:showPicture()
    local stream = camera.stream()
    if not stream or self.showing then
        return
    end
    self.showing = true
    ui.setImage('@camera', stream.texture)
    self.gui:replaceChildren('cameraView', {ui.image{image = '@camera', fit = 'contain', grow = 1, align = 'stretch'}})
end

-- The bytes of the JPEG file become a texture, which the card of the photo shows under a name of its own for every photo.
function Sample:showPhoto(photo)
    self.photos = self.photos + 1
    local name = '@photo' .. self.photos
    ui.setImage(name, graphics.newTexture(photo.jpeg))
    self.gui:replaceChildren('photoView', {ui.image{image = name, fit = 'contain', grow = 1, align = 'stretch'}})
end

function Sample:run(action)
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
        local answer = action.photo and string.format('a photo of %d by %d', result.width, result.height) or json.encode(result)
        self:log(string.format('The call "%s" answered %s.', action.code, answer))
        if action.started then
            self:showPicture()
        elseif action.photo then
            self:showPhoto(result)
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
        ui.label{text = 'Camera on "' .. haylen.platform .. '"', font = 'title'},
        ui.label{text = 'Each button runs one call of the plugin. The picture of the camera shows on the left card, the last photo on the right one, and every answer below them.', color = 'textMuted', wrap = true},
        ui.row{grow = 1, gap = 24, align = 'stretch',
            ui.scroll{width = 520, grow = 0, align = 'stretch', ui.column{gap = 12, alignItems = 'stretch', children = buttons}},
            ui.column{grow = 1, gap = 24, align = 'stretch',
                ui.row{grow = 2, gap = 24, align = 'stretch',
                    ui.card{id = 'cameraView', grow = 1, align = 'stretch', ui.label{text = 'No camera runs yet.', color = 'textMuted', wrap = true}},
                    ui.card{id = 'photoView', grow = 1, align = 'stretch', ui.label{text = 'No photo yet.', color = 'textMuted', wrap = true}},
                },
                ui.card{grow = 1, ui.scroll{grow = 1, height = 0, ui.column{id = 'lines'}}},
            },
        },
    }})

    camera.onStopped(function(stopped)
        self:log(string.format('The camera stopped with "%s": %s', stopped.code, stopped.message))
    end, {owner = self})

    -- Gamepads and TV remotes move the focus, so the first button starts with it.
    self.gui:command('state', 'focus')
    self:log('Press a button to run its call. The camera of a start ends with this scene, its owner.')
end

function Sample:exit()
    self.gui:unmount()
end

scene.push(Sample.new())
