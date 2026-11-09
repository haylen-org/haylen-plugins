package com.haylen.plugins.revenuecat

import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.LogLevel
import com.revenuecat.purchases.Offering
import com.revenuecat.purchases.Offerings
import com.revenuecat.purchases.Package
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.PurchasesError
import com.revenuecat.purchases.getCustomerInfoWith
import com.revenuecat.purchases.getOfferingsWith
import com.revenuecat.purchases.interfaces.UpdatedCustomerInfoListener
import com.revenuecat.purchases.logInWith
import com.revenuecat.purchases.logOutWith
import com.revenuecat.purchases.models.StoreTransaction
import com.revenuecat.purchases.purchaseWith
import com.revenuecat.purchases.restorePurchasesWith
import dev.haylen.HaylenBridge
import dev.haylen.HaylenPlugin
import dev.haylen.HaylenPluginContext
import dev.haylen.HaylenScreen
import org.json.JSONArray
import org.json.JSONObject

// Native part of the RevenueCat plugin on Android. It configures RevenueCat when the process starts with the parameter `androidApiKey`, answers with offerings and customer info as plain tables, and sells a package through the screen `purchase`, which covers the app while the sheet of Google Play shows. Customer info that changes on its own reaches the app as the retained event `customerInfoUpdated`.
class RevenueCatPlugin : HaylenPlugin() {
    private lateinit var context: HaylenPluginContext

    override fun onLoad(context: HaylenPluginContext) {
        this.context = context
        val config = context.config()
        Purchases.logLevel = if (config.optBoolean("debugLogs")) LogLevel.DEBUG else LogLevel.WARN

        // The tooling stops a build whose haylen.json gives no key.
        val apiKey = config.getString("androidApiKey")
        Purchases.configure(PurchasesConfiguration.Builder(context.application(), apiKey).build())
        Purchases.sharedInstance.updatedCustomerInfoListener = UpdatedCustomerInfoListener { info ->
            context.emit("customerInfoUpdated", describe(info), true, false)
        }

        registerCustomer()
        registerPurchase()
    }

    private fun registerCustomer() {
        context.register("customerInfo") { _, reply ->
            Purchases.sharedInstance.getCustomerInfoWith({ error -> fail(reply, error) }) { info -> reply.success(describe(info)) }
        }
        context.register("offerings") { _, reply ->
            Purchases.sharedInstance.getOfferingsWith({ error -> fail(reply, error) }) { offerings -> reply.success(describe(offerings)) }
        }
        context.register("restorePurchases") { _, reply ->
            Purchases.sharedInstance.restorePurchasesWith({ error -> fail(reply, error) }) { info -> reply.success(describe(info)) }
        }
        context.register("logIn") { params, reply ->
            val user = (params as JSONObject).getString("appUserId")
            Purchases.sharedInstance.logInWith(user, { error -> fail(reply, error) }) { info, created ->
                reply.success(JSONObject().put("customerInfo", describe(info)).put("created", created))
            }
        }
        context.register("logOut") { _, reply ->
            Purchases.sharedInstance.logOutWith({ error -> fail(reply, error) }) { info -> reply.success(describe(info)) }
        }
    }

    // The sheet of Google Play shows itself, and the app cannot close it, so a cancel of the app waits for the person to answer the sheet.
    private fun registerPurchase() {
        context.registerScreen("purchase") { params, screen ->
            screen.onCancel {}
            val purchase = params as JSONObject
            Purchases.sharedInstance.getOfferingsWith({ error -> fail(screen, error) }) { offerings -> buyFromOfferings(screen, offerings, purchase) }
        }
    }

    // The offerings of RevenueCat arrive after the opener returned, so the failures of the package end the screen here.
    private fun buyFromOfferings(screen: HaylenScreen, offerings: Offerings, purchase: JSONObject) {
        try {
            buy(screen, packageOf(offerings, purchase))
        } catch (failure: HaylenBridge.Failure) {
            screen.fail(failure)
        }
    }

    // The package of the offering that the app names, or of the current offering without a name.
    private fun packageOf(offerings: Offerings, purchase: JSONObject): Package {
        val offering: Offering? = if (purchase.has("offering")) offerings[purchase.getString("offering")] else offerings.current
        if (offering == null) {
            throw HaylenBridge.Failure("RevenueCat has no offering \"" + purchase.optString("offering", "current") + "\".", "notFound", null)
        }

        val name = purchase.getString("package")
        return offering.availablePackages.firstOrNull { it.identifier == name } ?: throw HaylenBridge.Failure("The offering \"" + offering.identifier + "\" holds no package \"" + name + "\".", "notFound", null)
    }

    private fun buy(screen: HaylenScreen, selected: Package) {
        val activity = context.activity() ?: throw HaylenBridge.Failure("The app has no activity.", "notActive", null)
        val parameters = PurchaseParams.Builder(activity, selected).build()
        Purchases.sharedInstance.purchaseWith(parameters, { error, _ -> fail(screen, error) }) { transaction, info ->
            screen.finish(JSONObject().put("productIdentifier", productOf(transaction, selected)).put("customerInfo", describe(info)))
        }
    }

    private fun productOf(transaction: StoreTransaction?, selected: Package): String = transaction?.productIds?.firstOrNull() ?: selected.product.id

    private fun fail(reply: HaylenBridge.Reply, error: PurchasesError) {
        reply.failure(error.message, RevenueCatErrors.code(error), null)
    }

    private fun fail(screen: HaylenScreen, error: PurchasesError) {
        screen.fail(error.message, RevenueCatErrors.code(error), null)
    }

    private fun describe(info: CustomerInfo): JSONObject =
        JSONObject()
            .put("appUserId", info.originalAppUserId)
            .put("activeEntitlements", JSONArray(info.entitlements.active.keys.sorted()))
            .put("activeSubscriptions", JSONArray(info.activeSubscriptions.sorted()))
            .put("purchasedProducts", JSONArray(info.allPurchasedProductIds.sorted()))
            .put("managementUrl", info.managementURL?.toString() ?: JSONObject.NULL)

    private fun describe(offerings: Offerings): JSONObject {
        val all = JSONArray()
        for (offering in offerings.all.values.sortedBy { it.identifier }) {
            val packages = JSONArray()
            for (item in offering.availablePackages) {
                packages.put(describe(item))
            }
            all.put(JSONObject().put("identifier", offering.identifier).put("description", offering.serverDescription).put("packages", packages))
        }
        return JSONObject().put("current", offerings.current?.identifier ?: JSONObject.NULL).put("all", all)
    }

    private fun describe(item: Package): JSONObject {
        val price = item.product.price
        return JSONObject()
            .put("identifier", item.identifier)
            .put("productIdentifier", item.product.id)
            .put("title", item.product.title)
            .put("description", item.product.description)
            .put("price", price.amountMicros / 1_000_000.0)
            .put("priceString", price.formatted)
            .put("currencyCode", price.currencyCode)
    }
}
