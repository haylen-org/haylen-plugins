# 🛒 RevenueCat

The RevenueCat plugin gives [Haylen](https://github.com/haylen-org/haylen) apps in-app purchases and subscriptions through RevenueCat, which checks the purchases with the stores, keeps the entitlements of each user and shows them in one dashboard for the App Store and Google Play. The app reads its offerings, buys a package, restores purchases, names its user and hears every change of the customer info.

The purchase is a screen of the plugin, so the engine covers the app while the sheet of the store shows. Customer info that changes on its own, such as a renewal, a refund or a purchase made on another device, reaches the app as an event.

| Platform | Native part | SDK |
| --- | --- | --- |
| iOS, iPadOS, Mac Catalyst, tvOS and the macOS app | `apple/RevenueCatPlugin.swift` | RevenueCat `5.102.3` as a Swift package, over StoreKit. |
| Android | The library module in `android/` | `com.revenuecat.purchases:purchases` `11.2.0` through Gradle, over Google Play Billing. |

## Installation

```sh
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path revenuecat --reference --app my-app
```

The command lists the plugin in the `plugins` section of the `haylen.json` of the app as a reference to its folder in the repository of the Haylen plugins, with an empty text for each public API key, which the app fills in with the keys of its RevenueCat project:

```json
{
    "plugins": {
        "revenuecat": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "revenuecat",
            "parameters": {
                "appleApiKey": "appl_...",
                "androidApiKey": "goog_..."
            }
        }
    }
}
```

Without `--reference`, the command copies the plugin into `plugins/revenuecat/` of the app instead. A parameter that the entry leaves out takes its default from `plugin.json`, so the app follows the defaults of newer versions of the plugin. To stay on one version of the plugin, the app names a commit in `ref` instead of the branch `main`.

## Parameters

| Parameter | Platforms | Type | Default | Meaning |
| --- | --- | --- | --- | --- |
| `appleApiKey` | iOS, Mac Catalyst, tvOS, macOS | string | Required | The public Apple API key of the RevenueCat project, which starts with `appl_`. |
| `androidApiKey` | Android | string | Required | The public Google API key of the RevenueCat project, which starts with `goog_`. |
| `debugLogs` | All | boolean | `false` | Whether the SDK writes its debug log. |

The public API keys are meant to ship in apps, while the secret keys of RevenueCat never leave the server.

## Setup

1. Create a project in [RevenueCat](https://app.revenuecat.com). Add an App Store app with the `identifier` of your `haylen.json` as its bundle ID, and a Play Store app with the same package name. Copy their public API keys into `appleApiKey` and `androidApiKey`.
2. Create the products in App Store Connect and in the Play Console, and import them into RevenueCat. Attach them to entitlements, such as `premium`, and arrange them in offerings and packages, such as the offering `default` with the packages `$rc_monthly` and `$rc_annual`.
3. Test with sandbox accounts: a sandbox Apple account, or a StoreKit configuration file of Xcode, on Apple platforms, and a license tester of the Play Console on Android, whose app comes from a testing track of Google Play at least once.

| Platform | What the plugin adds to the project |
| --- | --- |
| Apple platforms | The Swift package `RevenueCat` and `StoreKit.framework`. Purchases need the In-App Purchase capability of the App ID, which App Store Connect turns on for every app. |
| Android | The library `purchases`, which brings the permission `com.android.vending.BILLING`. |

## What each platform answers

| Call | Apple platforms | Android |
| --- | --- | --- |
| `offerings` | The products of the App Store with their prices in the currency of the account of the store. | The products of Google Play, the same way. |
| `purchase` | The sheet of the App Store, which covers the app until the person buys or closes it. | The sheet of Google Play, the same way. |
| `restorePurchases` | Syncs the purchases of the Apple account, which may ask the person to sign in. | Syncs the purchases of the Google account. |
| `customerInfo().managementUrl` | The page of the subscriptions of the Apple account. | The page of the subscriptions of Google Play. |

## Platforms without the plugin

| Platform | Reason |
| --- | --- |
| visionOS | The plugin has not been run on visionOS, so it does not list it, although RevenueCat supports it. |
| The web | RevenueCat sells on the web through a billing SDK of its own, which the plugin does not wrap. |
| Windows, Linux | RevenueCat has no SDK for them. |
| macOS in the desktop player | The player of `haylen app run` loads the native libraries of plugins alone, and this plugin has none. The macOS app, `haylen app run --target macos`, runs the Apple part. |

On these platforms the plugin has no native part, so `revenuecat.available` is `false` and every call fails with the code `noHandler`.

## Lua API

```lua
local revenuecat = require('revenuecat')
```

The calls return platform calls of `haylen.platform`, whose `await` gives the answer, or `nil` and an error with a `code` and a `message`. The codes are the error codes of RevenueCat in camelCase, the same on every platform:

| Code | When |
| --- | --- |
| `cancelled` | The person closed the sheet of the store. |
| `network`, `offlineConnection` | The device could not reach RevenueCat. |
| `invalidCredentials` | The API key is not one of the project. |
| `configuration` | The project of RevenueCat, the products of the store or the app do not match, such as offerings whose products the store does not know. |
| `purchaseNotAllowed`, `insufficientPermissions` | The device or the account may not buy, such as under parental controls. |
| `productAlreadyPurchased`, `productNotAvailableForPurchase`, `paymentPending`, `storeProblem`, `ineligible` | The store refused or delayed the purchase. |
| `notFound` | The offering or the package that the app names does not exist. |
| `unknown`, `unknownBackend`, `unexpectedBackendResponse` | RevenueCat or the store failed in another way. |

The other codes of RevenueCat keep their names in camelCase without the word `Error`, such as `receiptAlreadyInUse`, `invalidReceipt`, `missingReceiptFile`, `invalidAppUserId`, `operationAlreadyInProgress`, `logOutAnonymousUser`, `invalidSubscriberAttributes`, `customerInfo` and `signatureVerificationFailed`.

### revenuecat.available

Whether the native part of the plugin runs on this platform. Without it every call fails with the code `noHandler`.

### revenuecat.offerings()

The `await` gives `{current, all}`: the identifier of the current offering, and every offering with its `identifier`, `description` and `packages`. Each package has `identifier`, `productIdentifier`, `title`, `description`, `price`, a number, `priceString`, the price as the store writes it, and `currencyCode`.

```lua
local async = require('async')
local revenuecat = require('revenuecat')

async.spawn(function()
    local offerings, err = revenuecat.offerings():await()
    if not offerings then
        print(err.code, err.message)
        return
    end
    for _, offering in ipairs(offerings.all) do
        for _, package in ipairs(offering.packages) do
            print(offering.identifier, package.identifier, package.priceString)
        end
    end
end)
```

### revenuecat.purchase(package, offering)

Buys the package `package` of the offering `offering`, or of the current offering when `offering` is `nil`, with the sheet of the store, which covers the app while it shows. The `await` gives `{productIdentifier, customerInfo}`. The call fails with the code `cancelled` when the person closes the sheet, `notFound` when the offering or the package does not exist, and the codes of RevenueCat otherwise. The sheet belongs to the store, so `call:cancel()` and the `timeout` of a call fail the call at once, while the sheet stays until the person answers it.

```lua
local async = require('async')
local revenuecat = require('revenuecat')

async.spawn(function()
    local bought, err = revenuecat.purchase('$rc_monthly'):await()
    if bought then
        print('Bought ' .. bought.productIdentifier .. '.')
    elseif err.code ~= 'cancelled' then
        print('The purchase failed: ' .. err.message)
    end
end)
```

### revenuecat.customerInfo()

The `await` gives the customer info, `{appUserId, activeEntitlements, activeSubscriptions, purchasedProducts, managementUrl}`. The list `activeEntitlements` holds the identifiers of the entitlements that the user holds now, `activeSubscriptions` and `purchasedProducts` hold product identifiers, and `managementUrl` is the page where the person manages the subscriptions, or `nil`.

```lua
local async = require('async')
local revenuecat = require('revenuecat')

async.spawn(function()
    local info = revenuecat.customerInfo():await()
    for _, entitlement in ipairs(info and info.activeEntitlements or {}) do
        print('Active: ' .. entitlement)
    end
end)
```

### revenuecat.restorePurchases()

Restores the purchases of the account of the store, which stores ask apps to offer behind a button. The `await` gives the customer info.

### revenuecat.logIn(appUserId), revenuecat.logOut()

The function `logIn` names the user of the app in RevenueCat, so the purchases follow the account of the app across devices. Its `await` gives `{customerInfo, created}`, where `created` tells whether RevenueCat met the user for the first time. The function `logOut` goes back to an anonymous user, and its `await` gives the customer info of that user. It fails with the code `logOutAnonymousUser` while the user is anonymous already.

```lua
local async = require('async')
local revenuecat = require('revenuecat')

async.spawn(function()
    local signedIn, err = revenuecat.logIn('player-42'):await()
    print(signedIn and signedIn.customerInfo.appUserId or err.code)
end)
```

### revenuecat.onCustomerInfo(listener, options)

Calls `listener(customerInfo)` whenever the customer info changes on its own, and returns the connection, whose `disconnect()` stops it. The table `options` may hold an `owner`, such as a scene, and the listener ends with it. The plugin sends the event retained, so the change that RevenueCat finds while the app starts waits for the first listener.

```lua
local revenuecat = require('revenuecat')

revenuecat.onCustomerInfo(function(info)
    for _, entitlement in ipairs(info.activeEntitlements) do
        print('Active: ' .. entitlement)
    end
end)
```

## Native API

| Method, screen or event | Params or payload | Answer |
| --- | --- | --- |
| `revenuecat.customerInfo`, `revenuecat.restorePurchases`, `revenuecat.logOut` | `{}` | `{appUserId, activeEntitlements, activeSubscriptions, purchasedProducts, managementUrl}` |
| `revenuecat.offerings` | `{}` | `{current, all}` |
| `revenuecat.logIn` | `{appUserId}` | `{customerInfo, created}` |
| `revenuecat.purchase` (screen) | `{package, offering}` | `{productIdentifier, customerInfo}` |
| `revenuecat.customerInfoUpdated` (retained event) | `{appUserId, activeEntitlements, activeSubscriptions, purchasedProducts, managementUrl}` | |

## License

MIT, like Haylen.
