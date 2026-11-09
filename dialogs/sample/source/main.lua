-- The sample of the Dialogs plugin: a button for every dialog, and a card for each with its last answer. Every dialog answers on a later frame and never blocks the app. The mouse, touch, the keyboard, gamepads and TV remotes move between the buttons.
local async = require('async')
local dialogs = require('dialogs')
local fs = require('fs')
local haylen = require('haylen')
local json = require('json')
local scene = require('haylen.scene')
local ui = require('haylen.ui')

local Sample = {}
Sample.__index = Sample

Sample.cancelSeconds = 2
Sample.timeoutSeconds = 4
Sample.kinds = {
    {id = 'message', title = 'A message', call = 'dialogs.message', button = 'Show a message'},
    {id = 'openFiles', title = 'Files to open', call = 'dialogs.openFiles', button = 'Open files'},
    {id = 'saveFile', title = 'Where to save', call = 'dialogs.saveFile', button = 'Save a file'},
    {id = 'openFolder', title = 'A folder', call = 'dialogs.openFolder', button = 'Open a folder'},
    {id = 'openPhotos', title = 'Photos', call = 'dialogs.openPhotos', button = 'Pick photos'},
    {id = 'giveUp', title = 'A message given up', call = 'call:cancel()', button = 'Give a message up'},
    {id = 'timeout', title = 'A message that times out', call = '{timeout = 4}', button = 'Time a message out'},
}

function Sample.new()
    return setmetatable({}, Sample)
end

function Sample:enter()
    local buttons, cards = {}, {}
    for index, kind in ipairs(Sample.kinds) do
        buttons[index] = ui.button{id = kind.id, text = kind.button, variant = index == 1 and 'primary' or 'default', onClick = function() self[kind.id](self) end}
        cards[index] = ui.card{align = 'stretch', padding = {12, 20},
            ui.row{gap = 12, ui.label{text = kind.title, font = 'heading'}, ui.label{text = kind.call, font = 'monospace', color = 'accentText'}},
            ui.label{id = kind.id .. 'Answer', text = 'Its answer shows here.', color = 'textMuted', wrap = true},
        }
    end

    self.gui = ui.mount(ui.column{grow = 1, gap = 20, padding = 32,
        ui.label{text = 'Dialogs on "' .. haylen.platform .. '"', font = 'title'},
        ui.row{gap = 12, wrap = true, children = buttons},
        ui.scroll{grow = 1, height = 0, ui.column{gap = 12, children = cards}},
    })
    self.gui:command('message', 'focus')
end

function Sample:exit()
    self.gui:unmount()
end

-- Shows the answer of a dialog, or its error, on its card and in the log. A dialog that the platform lacks or that the app gave up fails, as the plugin documents.
function Sample:run(id, call, describe)
    self.gui:set(id .. 'Answer', {text = 'Waiting for the answer.', color = 'textMuted'})
    scene.spawn(self, function()
        local answer, err = call:await()
        local text
        if err then
            text = string.format('It failed with the code "%s": %s', tostring(err.code), err.message)
        else
            text = describe(answer)
        end
        self.gui:set(id .. 'Answer', {text = text, color = 'text'})
        print(text)
    end)
end

-- Every picked file is readable at its path, so the card shows the size it reads.
function Sample:describeFiles(files)
    if not files then
        return 'The person cancelled the picker.'
    end
    local names = {}
    for _, file in ipairs(files) do
        local contents = fs.readFile(file.path):await()
        names[#names + 1] = string.format('"%s" with %d bytes', file.name, #contents)
    end
    return 'The person picked ' .. table.concat(names, ', ') .. '.'
end

function Sample:message()
    local call = dialogs.message({title = 'Unsaved changes', text = 'Save the changes before leaving?', kind = 'warning', buttons = {'Save', 'Discard', 'Cancel'}})
    self:run('message', call, function(button)
        return button and string.format('The person pressed button %d.', button) or 'The message closed without a button.'
    end)
end

function Sample:openFiles()
    local call = dialogs.openFiles({title = 'Pick files', filters = {{name = 'Images', extensions = {'png', 'jpg'}}, {name = 'Text', extensions = {'txt', 'json', 'md'}}}, multiple = true})
    self:run('openFiles', call, function(files) return self:describeFiles(files) end)
end

function Sample:saveFile()
    local report = json.encode({saved = os.date('%Y-%m-%d %H:%M:%S'), frame = haylen.frameIndex()})
    local call = dialogs.saveFile({title = 'Save the report', name = 'dialogs-report.json', data = report, filters = {{name = 'JSON', extensions = {'json'}}}})
    self:run('saveFile', call, function(saved)
        return saved and string.format('The report went to "%s".', saved.path or saved.name) or 'The person cancelled the picker.'
    end)
end

function Sample:openFolder()
    self:run('openFolder', dialogs.openFolder({title = 'Pick a folder'}), function(folder)
        return folder and 'The person picked "' .. folder .. '".' or 'The person cancelled the picker.'
    end)
end

function Sample:openPhotos()
    self:run('openPhotos', dialogs.openPhotos({multiple = true}), function(files) return self:describeFiles(files) end)
end

-- The plugin closes the message that the app gave up, and the call fails with the code "cancelled".
function Sample:giveUp()
    local call = dialogs.message({text = string.format('This message closes by itself after %d seconds.', Sample.cancelSeconds), buttons = {'OK'}})
    self:run('giveUp', call, function(button)
        return string.format('The person pressed button %d before the app gave the message up.', button or 0)
    end)
    scene.spawn(self, function()
        async.sleep(Sample.cancelSeconds * 1000):await()
        call:cancel()
    end)
end

-- The message closes when its timeout passes, and the call fails with the code "timeout".
function Sample:timeout()
    local call = dialogs.message({text = string.format('This message times out after %d seconds.', Sample.timeoutSeconds), buttons = {'OK'}, timeout = Sample.timeoutSeconds})
    self:run('timeout', call, function(button)
        return button and string.format('The person pressed button %d in time.', button) or 'The message closed without a button.'
    end)
end

scene.push(Sample.new())
