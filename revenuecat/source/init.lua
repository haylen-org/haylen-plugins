-- Lua API of the RevenueCat plugin, which an app loads with `require('revenuecat')`. RevenueCat starts with the app, the purchase is a screen that covers the app while the sheet of the store shows, and customer info that changes on its own reaches `onCustomerInfo`, retained, so a renewal found while the app starts waits for the first listener.
local platform = require('haylen.platform')

local handle = platform.plugin('revenuecat')
local revenuecat = {}

-- Whether the native part runs on this platform. Without it every call fails with the code `noHandler`.
revenuecat.available = handle.native

-- Returns a platform call whose `await` gives the customer info: `{appUserId, activeEntitlements, activeSubscriptions, purchasedProducts, managementUrl}`.
function revenuecat.customerInfo()
    return handle:call('customerInfo')
end

-- Returns a platform call whose `await` gives `{current, all}`, the identifier of the current offering and every offering with its `identifier`, `description` and `packages`, each package with `identifier`, `productIdentifier`, `title`, `description`, `price`, `priceString` and `currencyCode`.
function revenuecat.offerings()
    return handle:call('offerings')
end

-- Buys a package of an offering, the current one when `offering` is `nil`. Returns a platform call whose `await` gives `{productIdentifier, customerInfo}`, or fails with the code `cancelled` when the person closes the sheet.
function revenuecat.purchase(package, offering)
    return handle:openScreen('purchase', {package = package, offering = offering})
end

-- Restores the purchases of the account of the store, and returns a platform call whose `await` gives the customer info.
function revenuecat.restorePurchases()
    return handle:call('restorePurchases')
end

-- Names the user of the app in RevenueCat, so the purchases follow the user across devices. Returns a platform call whose `await` gives `{customerInfo, created}`, where `created` tells whether RevenueCat met the user for the first time.
function revenuecat.logIn(appUserId)
    return handle:call('logIn', {appUserId = appUserId})
end

-- Goes back to an anonymous user, and returns a platform call whose `await` gives the customer info of that user.
function revenuecat.logOut()
    return handle:call('logOut')
end

-- Calls `listener(customerInfo)` whenever the customer info changes on its own, such as a renewal or a purchase on another device, and returns the connection that stops it.
function revenuecat.onCustomerInfo(listener, options)
    return handle:on('customerInfoUpdated', listener, options)
end

return revenuecat
