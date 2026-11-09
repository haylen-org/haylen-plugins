-- Plugin Lab: one card per plugin of the folder, with a button for each capability, and a log of what every call answered, so the plugins are checked on each platform from one app.
local haylen = require('haylen')
local json = require('json')
local scene = require('haylen.scene')
local ui = require('haylen.ui')

local admob = require('admob')
local analytics = require('firebase-analytics')
local crashlytics = require('firebase-crashlytics')
local firebase = require('firebase')
local googleAnalytics = require('google-analytics')
local messaging = require('firebase-messaging')
local notifications = require('notifications')
local playgama = require('playgama')
local revenuecat = require('revenuecat')
local tracking = require('app-tracking-transparency')

local Lab = {}
Lab.__index = Lab

local kMaxLines = 60

function Lab.new()
    return setmetatable({lines = {}, titles = {}}, Lab)
end

-- Writes a line at the end of the log, which keeps its last lines.
function Lab:log(text)
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

-- Awaits the platform call that `start` returns and logs its answer, or the message and the code of its platform error, under the name of the action.
function Lab:report(name, start)
    local result, err = start():await()
    if err == nil then
        self:log(string.format('%s: %s', name, result == nil and 'nil' or json.encode(result)))
        return
    end

    self:log(string.format('%s failed: %s (%s)', name, tostring(err.message), tostring(err.code)))
end

function Lab:try(name, start)
    scene.spawn(self, function() self:report(name, start) end)
end

function Lab:section(title, available, actions)
    table.insert(self.titles, title)
    local buttons = {}
    for index, action in ipairs(actions) do
        buttons[index] = ui.button{text = action[1], onClick = function() self:try(title .. ' ' .. action[1], action[2]) end}
    end
    return ui.card{ui.column{
        gap = 12,
        ui.label{text = title, font = 'heading'},
        ui.label{text = available and 'The native part runs here.' or 'No native part on "' .. haylen.platform .. '", so the calls fail with "noHandler".', color = 'textMuted', font = 'caption', wrap = true},
        ui.row{gap = 12, wrap = true, children = buttons},
    }}
end

function Lab:enter()
    local units = admob.testUnits[haylen.platform] or admob.testUnits.android
    local sections = {
        self:section('Firebase', firebase.available, {
            {'App', firebase.app},
            {'Collect data', function() return firebase.setDataCollection(true) end},
        }),
        self:section('Analytics', analytics.available, {
            {'Log event', function() return analytics.logEvent('lab_opened', {screen = 'lab', count = 1}) end},
            {'User', function() return analytics.setUserId('lab-user') end},
            {'Consent', function() return analytics.setConsent({analyticsStorage = 'granted', adStorage = 'denied'}) end},
            {'Instance ID', analytics.appInstanceId},
        }),
        self:section('Crashlytics', crashlytics.available, {
            {'Log', function() return crashlytics.log('The lab pressed a button.') end},
            {'Keys', function() return crashlytics.setCustomKeys({level = 3, mode = 'lab', sound = true}) end},
            {'Record error', function() return crashlytics.recordError('An error that the lab records.', {{source = 'source/main.lua', line = 1, ['function'] = 'lab'}}) end},
            {'Crashed before', crashlytics.didCrashOnPreviousExecution},
        }),
        self:section('Notifications', notifications.available, {
            {'Permission', function() return notifications.permission() end},
            {'Request', function() return notifications.requestPermission() end},
            {'Schedule', function() return notifications.schedule({id = 'lab', title = 'Plugin Lab', body = 'A notification of the lab.', seconds = 5}) end},
            {'Pending', notifications.pending},
        }),
        self:section('Messaging', messaging.available, {
            {'Register', messaging.register},
            {'Unregister', messaging.unregister},
            {'Subscribe', function() return messaging.subscribe('lab') end},
        }),
        self:section('AdMob', admob.available, {
            {'Consent', function() return admob.requestConsent({debugGeography = 'eea'}) end},
            {'Start', admob.start},
            {'Banner', function() return admob.showBanner(units.banner, 'bottom') end},
            {'Hide banner', admob.hideBanner},
            {'Load interstitial', function() return admob.loadInterstitial(units.interstitial) end},
            {'Interstitial', admob.showInterstitial},
            {'Load rewarded', function() return admob.loadRewarded(units.rewarded) end},
            {'Rewarded', admob.showRewarded},
        }),
        self:section('RevenueCat', revenuecat.available, {
            {'Customer', revenuecat.customerInfo},
            {'Offerings', revenuecat.offerings},
            {'Restore', revenuecat.restorePurchases},
        }),
        self:section('Tracking', tracking.available, {
            {'Permission', function() return tracking.permission() end},
            {'Request', function() return tracking.requestPermission() end},
            {'Advertising ID', tracking.advertisingId},
        }),
        self:section('Playgama', playgama.available, {
            {'Platform', playgama.platform},
            {'Game ready', function() return playgama.sendMessage('gameReady') end},
            {'Interstitial', playgama.showInterstitial},
            {'Rewarded', playgama.showRewarded},
            {'Save', function() return playgama.storageSet('lab', 'saved') end},
            {'Load', function() return playgama.storageGet('lab') end},
        }),
        self:section('Google Analytics', googleAnalytics.available, {
            {'Log event', function() return googleAnalytics.logEvent('lab_opened', {screen = 'lab'}) end},
            {'Client ID', googleAnalytics.clientId},
        }),
    }

    self.gui = ui.mount(ui.safeArea{ui.column{
        gap = 16,
        padding = 24,
        ui.label{text = 'Plugin Lab on "' .. haylen.platform .. '"', font = 'title'},
        ui.card{ui.scroll{id = 'log', height = 360, ui.column{id = 'lines'}}},
        ui.scroll{height = 1300, ui.column{gap = 20, children = sections}},
    }})

    -- The events of the plugins land in the log too, also the ones that waited for this listener, such as the tap that opened the app.
    messaging.onMessage(function(message) self:log('Message: ' .. json.encode(message)) end, {owner = self})
    messaging.onOpened(function(message) self:log('Opened: ' .. json.encode(message)) end, {owner = self})
    messaging.onRegistered(function(event) self:log('Registered: ' .. event.installationId) end, {owner = self})
    notifications.onOpened(function(event) self:log('Notification opened: ' .. json.encode(event)) end, {owner = self})
    admob.onBannerLoaded(function(event) self:log('Banner loaded: ' .. json.encode(event)) end, {owner = self})
    admob.onBannerFailed(function(event) self:log('Banner failed: ' .. json.encode(event)) end, {owner = self})
    revenuecat.onCustomerInfo(function(info) self:log('Customer info: ' .. json.encode(info)) end, {owner = self})
    playgama.onPauseChanged(function(event) self:log('Pause: ' .. tostring(event.paused)) end, {owner = self})
    self:log('Sections: ' .. table.concat(self.titles, ', '))
    self:log('Plugins: ' .. json.encode(require('haylen.platform').plugins()))
    self:runChecks(units)
end

-- Runs, one after another, every call that needs no answer of a person, so one start of the lab checks each plugin on its platform. Prompts, consent forms, full-screen ads and purchases wait for a person, so they stay behind their buttons.
function Lab:runChecks(units)
    local checks = {
        {'Firebase app', firebase.app},
        {'Analytics event', function() return analytics.logEvent('lab_checked', {count = 1, ready = true}) end},
        {'Analytics instance', analytics.appInstanceId},
        {'Crashlytics keys', function() return crashlytics.setCustomKeys({lab = true}) end},
        {'Crashlytics error', function() return crashlytics.recordError('The lab records an error.') end},
        {'Crashed before', crashlytics.didCrashOnPreviousExecution},
        {'Notifications permission', function() return notifications.permission() end},
        {'Notifications pending', notifications.pending},
        {'Messaging register', messaging.register},
        {'AdMob consent', admob.consentState},
        {'AdMob start', admob.start},
        {'AdMob banner', function() return admob.showBanner(units.banner, 'bottom') end},
        {'AdMob interstitial', function() return admob.loadInterstitial(units.interstitial) end},
        {'AdMob rewarded', function() return admob.loadRewarded(units.rewarded) end},
        {'RevenueCat customer', revenuecat.customerInfo},
        {'RevenueCat offerings', revenuecat.offerings},
        {'Tracking permission', function() return tracking.permission() end},
        {'Playgama platform', playgama.platform},
        {'Playgama save', function() return playgama.storageSet('lab', 'saved') end},
        {'Playgama load', function() return playgama.storageGet('lab') end},
        {'Google Analytics event', function() return googleAnalytics.logEvent('lab_checked') end},
        {'Google Analytics client', googleAnalytics.clientId},
    }
    scene.spawn(self, function()
        for _, check in ipairs(checks) do
            self:report(check[1], check[2])
        end
        self:log('The checks ended.')
    end)
end

function Lab:exit()
    self.gui:unmount()
end

scene.push(Lab.new())
