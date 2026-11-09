-- The sample of the Bluetooth plugin: it scans for nearby devices, lists them as buttons, connects to the one the person picks, lists its services and characteristics, reads them, writes to them and subscribes to them, with a log of every answer and of every event. Mouse, touch, keyboard, gamepads and TV remotes drive the buttons through the focus of the UI.
local bluetooth = require('bluetooth')
local haylen = require('haylen')
local json = require('json')
local scene = require('haylen.scene')
local ui = require('haylen.ui')

local Sample = {}
Sample.__index = Sample

local kMaxLines = 40

function Sample.new()
    return setmetatable({lines = {}, devices = {}, device = nil, characteristics = {}}, Sample)
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

-- Shows bytes as hexadecimal digits, since a value of a characteristic is rarely text.
local function hex(bytes)
    return (bytes:gsub('.', function(byte) return string.format('%02x ', byte:byte()) end))
end

-- Awaits the call that `start` returns, logs its failure or hands its answer to `done`.
function Sample:try(name, start, done)
    scene.spawn(self, function()
        local result, err = start():await()
        if err then
            self:log(string.format('%s failed with the code "%s": %s', name, tostring(err.code), err.message))
            return
        end
        if done then
            done(result)
        else
            self:log(name .. ': ' .. json.encode(result))
        end
    end)
end

-- The buttons of the devices that the scan found, which connect to the device they name.
function Sample:showDevices()
    local buttons = {}
    for index, device in ipairs(self.devices) do
        local signal = device.rssi and (' (' .. device.rssi .. ' dBm)') or ''
        local text = (device.name or 'A device without a name') .. signal
        buttons[index] = ui.button{text = text, onClick = function() self:connect(device) end}
    end
    self.gui:replaceChildren('devices', buttons)
end

function Sample:scan()
    self.devices = {}
    self:showDevices()
    self:try('Scan', function() return bluetooth.scan({seconds = 8, owner = self}) end, function() self:log('The scan ended.') end)
end

function Sample:connect(device)
    self:try('Connect', function() return bluetooth.connect(device.id, {timeout = 15}) end, function(result)
        self.device = result.id
        self:log('Connected to ' .. (result.name or result.id) .. '.')
    end)
end

-- Lists every characteristic of every service of the connected device, so the buttons that read, write and subscribe act on all of them.
function Sample:discover()
    if not self.device then
        self:log('Connect to a device first.')
        return
    end
    local id = self.device
    scene.spawn(self, function()
        local services, err = bluetooth.services(id):await()
        if err then
            self:log('Services failed with the code "' .. tostring(err.code) .. '": ' .. err.message)
            return
        end
        self.characteristics = {}
        for _, service in ipairs(services) do
            local characteristics, failure = bluetooth.characteristics(id, service):await()
            if failure then
                self:log('Characteristics of ' .. service .. ' failed with the code "' .. tostring(failure.code) .. '": ' .. failure.message)
            end
            for _, characteristic in ipairs(characteristics or {}) do
                table.insert(self.characteristics, {service = service, uuid = characteristic.uuid, properties = characteristic.properties})
                self:log(string.format('%s / %s: %s', service, characteristic.uuid, table.concat(characteristic.properties, ', ')))
            end
        end
        self:log(#services .. ' services and ' .. #self.characteristics .. ' characteristics.')
    end)
end

-- The characteristics of the connected device that have the property, such as every one that the app may read.
function Sample:having(property)
    if not self.device then
        self:log('Connect to a device first.')
        return {}
    end

    local matching = {}
    for _, characteristic in ipairs(self.characteristics) do
        for _, name in ipairs(characteristic.properties) do
            if name == property then
                table.insert(matching, characteristic)
                break
            end
        end
    end
    return matching
end

function Sample:readAll()
    local device = self.device
    for _, characteristic in ipairs(self:having('read')) do
        self:try('Read', function() return bluetooth.read(device, characteristic.service, characteristic.uuid) end, function(result)
            self:log(characteristic.uuid .. ' reads ' .. hex(result.value))
        end)
    end
end

function Sample:writeAll()
    local device = self.device
    for _, characteristic in ipairs(self:having('write')) do
        self:try('Write', function() return bluetooth.write(device, characteristic.service, characteristic.uuid, '\1') end)
    end
end

function Sample:subscribeAll(subscribed)
    local device = self.device
    local name = subscribed and 'Subscribe' or 'Unsubscribe'
    local change = subscribed and bluetooth.subscribe or bluetooth.unsubscribe
    for _, characteristic in ipairs(self:having('notify')) do
        self:try(name, function() return change(device, characteristic.service, characteristic.uuid) end)
    end
end

function Sample:disconnect()
    if self.device then
        local device = self.device
        self:try('Disconnect', function() return bluetooth.disconnect(device) end)
    end
end

-- Logs each device that the scan found, with its data of the maker as hexadecimal digits.
function Sample:found(devices)
    for _, device in ipairs(devices) do
        table.insert(self.devices, device)
        local shown = device
        if device.manufacturerData then
            shown = {id = device.id, name = device.name, rssi = device.rssi, services = device.services, manufacturerData = hex(device.manufacturerData)}
        end
        self:log('Found ' .. json.encode(shown))
    end
    self:showDevices()
end

function Sample:enter()
    local actions = {
        {'Permission', function() self:try('Permission', bluetooth.permission, function(state) self:log('Permission: ' .. state) end) end},
        {'Ask', function() self:try('Ask', bluetooth.requestPermission, function(state) self:log('Ask: ' .. state) end) end},
        {'Scan', function() self:scan() end},
        {'Stop the scan', function() self:try('Stop the scan', bluetooth.stopScan) end},
        {'Services', function() self:discover() end},
        {'Read', function() self:readAll() end},
        {'Write', function() self:writeAll() end},
        {'Subscribe', function() self:subscribeAll(true) end},
        {'Unsubscribe', function() self:subscribeAll(false) end},
        {'Disconnect', function() self:disconnect() end},
    }
    local buttons = {}
    for index, action in ipairs(actions) do
        buttons[index] = ui.button{id = 'action' .. index, text = action[1], onClick = action[2]}
    end

    local available = bluetooth.available and 'The native part runs here.' or ('The plugin has no native part on "' .. haylen.platform .. '", so its calls fail with "noHandler".')
    self.gui = ui.mount(ui.safeArea{ui.column{
        gap = 24,
        padding = 32,
        ui.label{text = 'Bluetooth on "' .. haylen.platform .. '"', font = 'title'},
        ui.label{text = available, color = 'textMuted', wrap = true},
        ui.row{gap = 16, wrap = true, children = buttons},
        ui.row{id = 'devices', gap = 16, wrap = true},
        ui.card{grow = 1, ui.scroll{id = 'log', grow = 1, ui.column{id = 'lines'}}},
    }}, {owner = self})

    -- Gamepads and TV remotes move the focus, so the first button starts with it.
    self.gui:command('action1', 'focus')

    bluetooth.onFound(function(devices) self:found(devices) end, {owner = self})
    bluetooth.onChanged(function(changes)
        for _, change in ipairs(changes) do
            self:log(change.characteristic .. ' notified ' .. hex(change.value))
        end
    end, {owner = self})
    bluetooth.onDisconnected(function(event)
        if event.id == self.device then
            self.device = nil
        end
        self:log('Disconnected from ' .. event.id .. ': ' .. event.reason)
    end, {owner = self})
    self:log('Scan for devices, then press one to connect to it.')
end

function Sample:exit()
    self.gui:unmount()
end

scene.push(Sample.new())
