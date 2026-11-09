-- The sample of the Local Network plugin: it listens on a port with the module `socket`, advertises that port as a service of the type `_haylen-sample._tcp`, picks a service of that type through the picker and connects to it, and logs every answer. The buttons take the mouse, touch, the keyboard, gamepads and TV remotes.
local haylen = require('haylen')
local localNetwork = require('local-network')
local scene = require('haylen.scene')
local socket = require('socket')
local ui = require('haylen.ui')

local Sample = {}
Sample.__index = Sample

local kType = '_haylen-sample._tcp'
local kName = 'Haylen Sample'
local kMaxLines = 40
local kTimeoutMs = 5000

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

-- Runs a call of the plugin in a task of the scene and logs its failure.
function Sample:run(name, work)
    scene.spawn(self, function()
        local ok, failure = pcall(work)
        if not ok then
            self:log(string.format('The step "%s" raised: %s', name, tostring(failure)))
        end
    end)
end

function Sample:state(name, call)
    self:run(name, function()
        local state, failure = call():await()
        if state then
            self:log(string.format('The permission "localNetwork" is "%s".', state))
        else
            self:log(string.format('The call "%s" failed with "%s": %s', name, tostring(failure.code), failure.message))
        end
    end)
end

-- Answers every line that a peer sends with a greeting, until the peer leaves.
function Sample:serve(listener)
    scene.spawn(self, function()
        while true do
            local peer = listener:accept():await()
            if not peer then
                return
            end
            scene.spawn(self, function()
                local line = peer:receive():await()
                if line and line ~= '' then
                    peer:send('Hello from the sample, ' .. line):await()
                end
                peer:close():await()
            end)
        end
    end)
end

function Sample:advertise()
    self:run('advertise', function()
        if not self.listener then
            local listener, failure = socket.tcp.listen('0.0.0.0', 0):await()
            if not listener then
                self:log('The sample cannot listen: ' .. tostring(failure))
                return
            end
            self.listener = listener
            self:serve(listener)
        end

        local advertised, failure = localNetwork.advertise({type = kType, name = kName, port = self.listener.port, owner = self}):await()
        if advertised then
            self:log(string.format('Advertised "%s" of the type "%s" on the port %d.', advertised.name, advertised.type, advertised.port))
        else
            self:log(string.format('The advertisement failed with "%s": %s', tostring(failure.code), failure.message))
        end
    end)
end

function Sample:pick()
    self:run('pickService', function()
        local service, failure = localNetwork.pickService(kType):await()
        if not service then
            self:log(string.format('The picker failed with "%s": %s', tostring(failure.code), failure.message))
            return
        end
        self:log(string.format('Picked "%s" at %s, port %d.', service.name, service.host, service.port))

        local client, refused = socket.tcp.connect(service.host, service.port, {timeoutMs = kTimeoutMs}):await()
        if not client then
            self:log(string.format('The connection to "%s" failed: %s', service.name, tostring(refused)))
            return
        end
        client:send(haylen.platform):await()
        local answer = client:receive():await()
        client:close():await()
        self:log(string.format('Connected to "%s", which answered "%s".', service.name, tostring(answer)))
    end)
end

function Sample:enter()
    self.gui = ui.mount(ui.safeArea{ui.column{
        gap = 24,
        padding = 32,
        ui.label{text = 'Local network on "' .. haylen.platform .. '"', font = 'title'},
        ui.label{text = 'Advertise the sample, then pick its service and connect to it. The picker of Android hands the app the service without the permission "localNetwork", and Apple platforms show a list of the services that the plugin finds.', color = 'textMuted', wrap = true},
        ui.row{gap = 16, wrap = true,
            ui.button{id = 'check', text = 'Check the permission', onClick = function() self:state('localNetwork.permission', localNetwork.permission) end},
            ui.button{id = 'ask', text = 'Ask for the permission', onClick = function() self:state('localNetwork.requestPermission', localNetwork.requestPermission) end},
            ui.button{id = 'advertise', text = 'Advertise the sample', onClick = function() self:advertise() end},
            ui.button{id = 'pick', text = 'Pick a service', onClick = function() self:pick() end},
            ui.button{id = 'stop', text = 'Stop advertising', onClick = function()
                self:run('stopAdvertising', function()
                    localNetwork.stopAdvertising():await()
                    self:log('The sample stopped advertising.')
                end)
            end},
        },
        ui.card{grow = 1, ui.scroll{id = 'log', grow = 1, ui.column{id = 'lines'}}},
    }}, {owner = self})

    -- Gamepads and TV remotes move the focus, so the first button starts with it.
    self.gui:command('check', 'focus')
    self:log('Press a button to run its call.')
end

function Sample:exit()
    if self.listener then
        self.listener:close()
        self.listener = nil
    end
    self.gui:unmount()
end

scene.push(Sample.new())
