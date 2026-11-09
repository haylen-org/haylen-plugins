-- Lua API of the AdMob plugin, which an app loads with `require('admob')`. Full-screen ads and the consent forms are screens, so the engine covers the app while they show, and the banner reserves its edge of the safe area, so the interface of the app moves out of its way.
local platform = require('haylen.platform')

local handle = platform.plugin('admob')
local admob = {}

local kPositions = {top = true, bottom = true}

-- Whether the native part runs on this platform. Without it every call fails with the code `noHandler`.
admob.available = handle.native

-- The ad units of the test ads of Google, which serve test ads without an account.
admob.testUnits = {
    ios = {banner = 'ca-app-pub-3940256099942544/2435281174', interstitial = 'ca-app-pub-3940256099942544/4411468910', rewarded = 'ca-app-pub-3940256099942544/1712485313'},
    android = {banner = 'ca-app-pub-3940256099942544/9214589741', interstitial = 'ca-app-pub-3940256099942544/1033173712', rewarded = 'ca-app-pub-3940256099942544/5224354917'},
}

-- Starts the SDK, which the app does once it may request ads. Returns a platform call whose `await` gives `{started = true}`.
function admob.start()
    return handle:call('start')
end

-- Asks the person for consent with the form of the User Messaging Platform when the law asks for it, and returns a platform call whose `await` gives `{status, canRequestAds, privacyOptionsRequired}`. The options take `debugGeography`, `'eea'` or `'notEea'`, and `testDeviceIds`, to try the form outside the region where it shows.
function admob.requestConsent(options)
    return handle:openScreen('consent', options or {})
end

-- Returns a platform call whose `await` gives the consent that the device holds now, `{status, canRequestAds, privacyOptionsRequired}`, without asking.
function admob.consentState()
    return handle:call('consentState')
end

-- Shows the privacy options form, which the app offers from its settings when `privacyOptionsRequired` is true. Returns a platform call whose `await` gives the consent once the person closes the form.
function admob.showPrivacyOptions()
    return handle:openScreen('privacyOptions')
end

-- Shows an adaptive banner of the ad unit at the `'bottom'` or `'top'` of the safe area, and moves the safe area out of its way. Returns a platform call whose `await` gives `{}` once the banner is placed, while `onBannerLoaded` and `onBannerFailed` tell whether an ad came.
function admob.showBanner(adUnitId, position)
    position = position or 'bottom'
    if not kPositions[position] then
        error(string.format('The position of a banner is "top" or "bottom", not "%s".', tostring(position)), 2)
    end
    return handle:call('showBanner', {adUnitId = adUnitId, position = position})
end

-- Takes the banner away and gives its edge of the safe area back.
function admob.hideBanner()
    return handle:call('hideBanner')
end

-- Loads an interstitial ad, which a later `showInterstitial` presents at once. Returns a platform call whose `await` gives `{loaded = true}`, or fails with the code `loadFailed` when no ad came.
function admob.loadInterstitial(adUnitId)
    return handle:call('loadInterstitial', {adUnitId = adUnitId})
end

-- Loads a rewarded ad, which a later `showRewarded` presents at once. Returns a platform call whose `await` gives `{loaded = true}`, or fails with the code `loadFailed` when no ad came.
function admob.loadRewarded(adUnitId)
    return handle:call('loadRewarded', {adUnitId = adUnitId})
end

-- Shows the loaded interstitial ad. Returns a platform call whose `await` gives `{shown = true, rewarded = false}` once the person closes it, or fails with the code `notLoaded`.
function admob.showInterstitial()
    return handle:openScreen('interstitial')
end

-- Shows the loaded rewarded ad. Returns a platform call whose `await` gives `{shown, rewarded, type, amount}` once the person closes it, where `rewarded` tells whether the person earned the reward.
function admob.showRewarded()
    return handle:openScreen('rewarded')
end

-- Calls `listener({width, height})` when a banner loads, and returns the connection that stops it.
function admob.onBannerLoaded(listener, options)
    return handle:on('bannerLoaded', listener, options)
end

-- Calls `listener({message, code})` when a banner fails to load, and returns the connection that stops it.
function admob.onBannerFailed(listener, options)
    return handle:on('bannerFailed', listener, options)
end

return admob
