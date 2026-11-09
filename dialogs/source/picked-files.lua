-- The call of a picker on the web, where the browser hands the picked files over as bytes. The plugin writes them into the folder `tmp/dialogs` of the storage before the call answers, so the app reads every file at its path as on the other platforms. It offers what a platform call offers: `await`, `cancel`, `id`, `done` and `promise`.
local async = require('async')
local fs = require('fs')
local log = require('log')
local storage = require('haylen.storage')

local PickedFiles = {}

local kFolder = storage.root() .. '/tmp/dialogs'

-- The copies of an earlier app are gone once the plugin loads again, so the folder never grows. The writes of a pick wait for it, and a folder that cannot be emptied keeps its old files, which the log names.
local function clearFolder()
    if not fs.exists(kFolder) then
        return nil
    end
    local removal = fs.removeRecursive(kFolder)
    return removal:catch(function(err)
        log.warn('The copies of picked files in "' .. kFolder .. '" could not be removed: ' .. tostring(err))
    end)
end

local clearing = clearFolder()

local nextPick = 1

-- A failure of the plugin itself, which reads as its message like the errors of platform calls.
local Failure = {
    __tostring = function(failure) return failure.message end,
    __concat = function(left, right) return tostring(left) .. tostring(right) end,
}

local function newFailure(message)
    return setmetatable({message = message, code = 'failed'}, Failure)
end

-- Each pick writes into a numbered folder of its own, and a second file of the same name goes into a numbered folder inside it.
local function write(picked)
    if clearing then
        clearing:await()
    end
    local folder = kFolder .. '/' .. nextPick
    nextPick = nextPick + 1

    local used = {}
    local files = {}
    for index, file in ipairs(picked) do
        local place = folder
        if used[file.name] then
            place = folder .. '/' .. index
        end
        used[file.name] = true
        fs.mkdir(place):await()
        local path = place .. '/' .. file.name
        fs.writeFile(path, file.data):await()
        files[index] = {name = file.name, path = path}
    end
    return files
end

local function finish(call)
    local picked, err = call.picker:await()
    if err then
        return {err = err}
    end
    if picked == nil then
        return {}
    end

    local ok, files = pcall(write, picked)
    if not ok then
        return {err = newFailure('The picked files could not be written for the app: ' .. tostring(files))}
    end
    return {files = files}
end

local methods = {}

function methods:await()
    if not self.outcome then
        self.outcome = async.promise(function() return finish(self) end)
    end
    local outcome = self.outcome:await()
    return outcome.files, outcome.err
end

function methods:cancel()
    return self.picker:cancel()
end

-- The promise resolves with the files and fails with the message of the error, like the promise of a platform call.
local function getPromise(call)
    if not call.promise then
        call.promise = async.promise(function()
            local files, err = call:await()
            if err then
                error(tostring(err), 0)
            end
            return files
        end)
    end
    return call.promise
end

local Call = {
    __index = function(call, key)
        if key == 'id' then
            return call.picker.id
        end
        if key == 'done' then
            if call.outcome then
                return call.outcome:isDone()
            end
            return call.picker.done
        end
        if key == 'promise' then
            return getPromise(call)
        end
        return methods[key]
    end,
}

function PickedFiles.new(picker)
    return setmetatable({picker = picker}, Call)
end

return PickedFiles
