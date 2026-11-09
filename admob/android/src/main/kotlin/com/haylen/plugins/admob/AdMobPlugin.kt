package com.haylen.plugins.admob

import android.app.Activity
import android.os.Bundle
import androidx.core.view.WindowInsetsCompat
import com.google.android.gms.ads.AdError
import com.google.android.gms.ads.AdListener
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.AdSize
import com.google.android.gms.ads.AdView
import com.google.android.gms.ads.FullScreenContentCallback
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.MobileAds
import com.google.android.gms.ads.RequestConfiguration
import com.google.android.gms.ads.interstitial.InterstitialAd
import com.google.android.gms.ads.interstitial.InterstitialAdLoadCallback
import com.google.android.gms.ads.rewarded.RewardItem
import com.google.android.gms.ads.rewarded.RewardedAd
import com.google.android.gms.ads.rewarded.RewardedAdLoadCallback
import com.google.android.ump.ConsentDebugSettings
import com.google.android.ump.ConsentInformation
import com.google.android.ump.ConsentRequestParameters
import com.google.android.ump.FormError
import com.google.android.ump.UserMessagingPlatform
import dev.haylen.HaylenActivity
import dev.haylen.HaylenBridge
import dev.haylen.HaylenOverlay
import dev.haylen.HaylenPlacement
import dev.haylen.HaylenPlugin
import dev.haylen.HaylenPluginContext
import dev.haylen.HaylenScreen
import org.json.JSONArray
import org.json.JSONObject

// Native part of the AdMob plugin on Android. The consent form, the privacy options, the interstitial ads and the rewarded ads are screens of the plugin, so the engine covers the app while they show. The banner is a view of the overlay, which reserves its edge of the safe area so the interface of the app moves out of its way, and the page that a tap on the banner opens covers the app until it closes.
class AdMobPlugin : HaylenPlugin() {
    private lateinit var context: HaylenPluginContext
    private var banner: AdView? = null
    private var bannerPanel: HaylenOverlay.Panel? = null
    private var bannerRequest: JSONObject? = null
    private var interstitial: InterstitialAd? = null
    private var rewarded: RewardedAd? = null

    override fun onLoad(context: HaylenPluginContext) {
        this.context = context
        val testDevices = strings(context.config().optJSONArray("testDeviceIds"))
        MobileAds.setRequestConfiguration(RequestConfiguration.Builder().setTestDeviceIds(testDevices).build())

        // Google asks apps to start the SDK away from the main thread, since it reads its state from the disk.
        context.register("start", { _, reply ->
            MobileAds.initialize(context.application()) { reply.success(JSONObject().put("started", true)) }
        }, HaylenBridge.Threading.BACKGROUND)
        context.register("consentState") { _, reply -> reply.success(consentState()) }
        registerConsent()
        registerBanner()
        registerFullScreenAds()
    }

    // The overlay of a new activity starts empty, so the banner that the app shows comes back once the window has its size.
    override fun onActivityCreated(activity: HaylenActivity, savedInstanceState: Bundle?) {
        val request = bannerRequest ?: return
        activity.window.decorView.post { showBanner(request) }
    }

    // The activity takes the views of the overlay with it, and the banner with them.
    override fun onActivityDestroyed(activity: HaylenActivity) {
        removeBanner()
    }

    // The forms of the User Messaging Platform present themselves, and the app cannot close them, so a cancel of the app waits for the person to answer the form.
    private fun registerConsent() {
        context.registerScreen("consent") { params, screen ->
            screen.onCancel {}
            requestConsent(foreground(), params as JSONObject, screen)
        }
        context.registerScreen("privacyOptions") { _, screen ->
            screen.onCancel {}
            val activity = foreground()
            UserMessagingPlatform.showPrivacyOptionsForm(activity) { error -> endConsent(screen, error) }
        }
    }

    private fun registerBanner() {
        context.register("showBanner") { params, reply ->
            val request = params as JSONObject
            showBanner(request)
            bannerRequest = request
            reply.success(JSONObject())
        }
        context.register("hideBanner") { _, reply ->
            removeBanner()
            bannerRequest = null
            reply.success(JSONObject())
        }
    }

    // An ad that shows cannot be closed by the app, so a cancel of the app waits for the person to close it.
    private fun registerFullScreenAds() {
        context.register("loadInterstitial") { params, reply ->
            val unit = (params as JSONObject).getString("adUnitId")
            InterstitialAd.load(context.application(), unit, AdRequest.Builder().build(), object : InterstitialAdLoadCallback() {
                override fun onAdLoaded(ad: InterstitialAd) {
                    interstitial = ad
                    reply.success(JSONObject().put("loaded", true))
                }

                override fun onAdFailedToLoad(error: LoadAdError) {
                    reply.failure(error.message, "loadFailed", JSONObject().put("errorCode", error.code))
                }
            })
        }
        context.register("loadRewarded") { params, reply ->
            val unit = (params as JSONObject).getString("adUnitId")
            RewardedAd.load(context.application(), unit, AdRequest.Builder().build(), object : RewardedAdLoadCallback() {
                override fun onAdLoaded(ad: RewardedAd) {
                    rewarded = ad
                    reply.success(JSONObject().put("loaded", true))
                }

                override fun onAdFailedToLoad(error: LoadAdError) {
                    reply.failure(error.message, "loadFailed", JSONObject().put("errorCode", error.code))
                }
            })
        }
        context.registerScreen("interstitial") { _, screen ->
            screen.onCancel {}
            val ad = interstitial ?: return@registerScreen screen.fail("No interstitial ad is loaded. Load one with \"admob.loadInterstitial\" first.", "notLoaded", null)
            val activity = foreground()
            interstitial = null
            ad.fullScreenContentCallback = FullScreenEnd(screen) { null }
            ad.show(activity)
        }
        context.registerScreen("rewarded") { _, screen ->
            screen.onCancel {}
            val ad = rewarded ?: return@registerScreen screen.fail("No rewarded ad is loaded. Load one with \"admob.loadRewarded\" first.", "notLoaded", null)
            val activity = foreground()
            rewarded = null
            var reward: RewardItem? = null
            ad.fullScreenContentCallback = FullScreenEnd(screen) { reward }
            ad.show(activity) { earned -> reward = earned }
        }
    }

    // Ends the screen of a full-screen ad once the person closes it, with the reward that the person earned, if any.
    private class FullScreenEnd(private val screen: HaylenScreen, private val reward: () -> RewardItem?) : FullScreenContentCallback() {
        override fun onAdDismissedFullScreenContent() {
            val earned = reward()
            val result = JSONObject().put("shown", true).put("rewarded", earned != null)
            if (earned != null) {
                result.put("type", earned.type).put("amount", earned.amount)
            }
            screen.finish(result)
        }

        override fun onAdFailedToShowFullScreenContent(error: AdError) {
            screen.fail(error.message, "showFailed", JSONObject().put("errorCode", error.code))
        }
    }

    // The runtime opens screens only while the activity is in the foreground.
    private fun foreground(): Activity = context.activity() ?: throw HaylenBridge.Failure("The app has no activity.", "notActive", null)

    private fun requestConsent(activity: Activity, params: JSONObject, screen: HaylenScreen) {
        val parameters = consentParameters(activity, params)
        val information = UserMessagingPlatform.getConsentInformation(activity)
        information.requestConsentInfoUpdate(activity, parameters, { showConsentForm(activity, screen) }, { error -> endConsent(screen, error) })
    }

    // The form shows only where the law asks for it, and the screen ends at once elsewhere.
    private fun showConsentForm(activity: Activity, screen: HaylenScreen) {
        UserMessagingPlatform.loadAndShowConsentFormIfRequired(activity) { error -> endConsent(screen, error) }
    }

    private fun consentParameters(activity: Activity, params: JSONObject): ConsentRequestParameters {
        val parameters = ConsentRequestParameters.Builder()
        if (!params.has("debugGeography") && !params.has("testDeviceIds")) {
            return parameters.build()
        }

        val debug = ConsentDebugSettings.Builder(activity)
        if (params.has("debugGeography")) {
            debug.setDebugGeography(debugGeography(params.getString("debugGeography")))
        }
        for (id in strings(params.optJSONArray("testDeviceIds"))) {
            debug.addTestDeviceHashedId(id)
        }
        return parameters.setConsentDebugSettings(debug.build()).build()
    }

    private fun debugGeography(name: String): Int =
        when (name) {
            "eea" -> ConsentDebugSettings.DebugGeography.DEBUG_GEOGRAPHY_EEA
            "notEea" -> ConsentDebugSettings.DebugGeography.DEBUG_GEOGRAPHY_OTHER
            else -> throw HaylenBridge.Failure("The \"debugGeography\" of the consent is \"eea\" or \"notEea\", not \"$name\".", "invalidParams", null)
        }

    private fun endConsent(screen: HaylenScreen, error: FormError?) {
        if (error != null) {
            screen.fail(error.message, "consentFailed", JSONObject().put("errorCode", error.errorCode))
            return
        }
        screen.finish(consentState())
    }

    private fun consentState(): JSONObject {
        val information = UserMessagingPlatform.getConsentInformation(context.application())
        val privacyOptionsRequired = information.privacyOptionsRequirementStatus == ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED
        return JSONObject().put("status", statusName(information.consentStatus)).put("canRequestAds", information.canRequestAds()).put("privacyOptionsRequired", privacyOptionsRequired)
    }

    private fun statusName(status: Int): String =
        when (status) {
            ConsentInformation.ConsentStatus.OBTAINED -> "obtained"
            ConsentInformation.ConsentStatus.REQUIRED -> "required"
            ConsentInformation.ConsentStatus.NOT_REQUIRED -> "notRequired"
            ConsentInformation.ConsentStatus.UNKNOWN -> "unknown"
            else -> throw IllegalStateException("The User Messaging Platform reported the consent status $status, which the plugin does not know.")
        }

    // The banner takes the width of the safe area of the activity and the height that Google picks for that width.
    private fun showBanner(params: JSONObject) {
        val anchor = anchor(params.getString("position"))
        val activity = context.activity() ?: throw HaylenBridge.Failure("The app has no activity.", "noWindow", null)

        removeBanner()
        val size = AdSize.getLargeAnchoredAdaptiveBannerAdSize(activity, safeWidthDp(activity))
        val view = AdView(activity)
        view.setAdSize(size)
        view.adUnitId = params.getString("adUnitId")
        view.adListener = BannerListener(size)

        val placement = HaylenPlacement(anchor)
        placement.reserve = true
        placement.widthDp = size.width
        placement.heightDp = size.height
        banner = view
        bannerPanel = context.overlay().add(view, placement)
        view.loadAd(AdRequest.Builder().build())
    }

    private fun anchor(position: String): HaylenPlacement.Anchor =
        when (position) {
            "top" -> HaylenPlacement.Anchor.TOP
            "bottom" -> HaylenPlacement.Anchor.BOTTOM
            else -> throw HaylenBridge.Failure("The position of a banner is \"top\" or \"bottom\", not \"$position\".", "invalidParams", null)
        }

    private fun safeWidthDp(activity: Activity): Int {
        val window = activity.window.decorView
        val insets = WindowInsetsCompat.toWindowInsetsCompat(window.rootWindowInsets, window).getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
        val safeWidth = window.width - insets.left - insets.right
        return (safeWidth / activity.resources.displayMetrics.density).toInt()
    }

    private inner class BannerListener(private val size: AdSize) : AdListener() {
        override fun onAdLoaded() {
            context.emit("bannerLoaded", JSONObject().put("width", size.width).put("height", size.height))
        }

        override fun onAdFailedToLoad(error: LoadAdError) {
            context.emit("bannerFailed", JSONObject().put("message", error.message).put("code", error.code))
        }

        override fun onAdOpened() {
            context.coverApp()
        }

        override fun onAdClosed() {
            context.uncoverApp()
        }
    }

    private fun removeBanner() {
        bannerPanel?.remove()
        bannerPanel = null
        banner?.destroy()
        banner = null
    }

    private fun strings(array: JSONArray?): List<String> = List(array?.length() ?: 0) { index -> array!!.getString(index) }
}
