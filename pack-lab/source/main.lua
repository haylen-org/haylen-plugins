-- Loads an asset of a pack that downloads when the app asks for it and of one that downloads with the install, which Google Play delivers through the Play Asset Delivery plugin and the App Store through the Background Assets plugin, and shows and logs what each load gives.
local assets = require('haylen.assets')
local async = require('async')
local backgroundAssets = require('background-assets')
local delivery = require('play-asset-delivery')
local log = require('log')
local ui = require('haylen.ui')

local gui = ui.mount(ui.column{
    align = 'center',
    gap = 24,
    ui.label{text = 'Pack delivery', font = 'title', align = 'center'},
    ui.label{id = 'chapter', text = 'Loading the chapter pack.', align = 'center'},
    ui.label{id = 'music', text = 'Loading the music pack.', align = 'center'},
})

delivery.addSource()
backgroundAssets.addSource()

for _, entry in ipairs({{id = 'chapter', path = 'chapters/two/story.json', pack = 'chapter-2'}, {id = 'music', path = 'music/intro.json', pack = 'intro.music'}}) do
    async.spawn(function()
        local loaded, err = assets.loadAsync(entry.path):await()
        local text = loaded and ('Loaded "' .. loaded.title .. '" from the pack "' .. entry.pack .. '".') or ('Failed to load the pack "' .. entry.pack .. '". ' .. tostring(err))
        log.info('Pack delivery check: ' .. text)
        gui:set(entry.id, {text = text})
        local state = (delivery.available and delivery or backgroundAssets).state(entry.pack):await()
        log.info('Pack delivery check: The pack "' .. entry.pack .. '" is "' .. (state and state.status or 'unknown') .. '".')
    end)
end
