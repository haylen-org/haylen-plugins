package com.haylen.plugins.firebaseanalytics

import android.os.Bundle
import com.google.firebase.FirebaseApp
import com.google.firebase.analytics.FirebaseAnalytics
import dev.haylen.HaylenBridge
import dev.haylen.HaylenPlugin
import dev.haylen.HaylenPluginContext
import org.json.JSONArray
import org.json.JSONObject

// Native part of the Firebase Analytics plugin on Android. It logs into the default Firebase app that the plugin `firebase` configures.
class FirebaseAnalyticsPlugin : HaylenPlugin() {
    private val consentTypes = mapOf(
        "analyticsStorage" to FirebaseAnalytics.ConsentType.ANALYTICS_STORAGE,
        "adStorage" to FirebaseAnalytics.ConsentType.AD_STORAGE,
        "adUserData" to FirebaseAnalytics.ConsentType.AD_USER_DATA,
        "adPersonalization" to FirebaseAnalytics.ConsentType.AD_PERSONALIZATION,
    )

    private lateinit var context: HaylenPluginContext

    override fun onLoad(context: HaylenPluginContext) {
        this.context = context
        registerEvents()
        registerConsent()

        context.register("appInstanceId") { _, reply ->
            analytics().appInstanceId.addOnCompleteListener { task ->
                if (!task.isSuccessful) {
                    reply.failure("Analytics gave no app instance: " + (task.exception?.message ?: "no reason"), "unavailable", null)
                    return@addOnCompleteListener
                }
                reply.success(JSONObject().put("id", task.result ?: JSONObject.NULL))
            }
        }

        context.register("resetAnalyticsData") { _, reply ->
            analytics().resetAnalyticsData()
            reply.success(JSONObject().put("reset", true))
        }
    }

    private fun registerEvents() {
        context.register("logEvent") { params, reply ->
            val call = params as? JSONObject
            val name = call?.optString("name").orEmpty()
            if (name.isEmpty()) {
                throw HaylenBridge.Failure("The method \"logEvent\" needs the name of the event.", "invalidParams", null)
            }

            val values = call?.optJSONObject("params")
            analytics().logEvent(name, values?.let(::toBundle))
            reply.success(null)
        }

        context.register("setUserId") { params, reply ->
            val call = params as? JSONObject
            val id = call?.optString("id")?.takeIf { it.isNotEmpty() }
            analytics().setUserId(id)
            reply.success(null)
        }

        context.register("setUserProperty") { params, reply ->
            val call = params as? JSONObject
            val name = call?.optString("name").orEmpty()
            if (call == null || name.isEmpty()) {
                throw HaylenBridge.Failure("The method \"setUserProperty\" needs the name of the property.", "invalidParams", null)
            }

            val value = if (call.isNull("value")) null else call.getString("value")
            analytics().setUserProperty(name, value)
            reply.success(null)
        }
    }

    private fun registerConsent() {
        context.register("setConsent") { params, reply ->
            val call = params as? JSONObject ?: JSONObject()
            val consent = mutableMapOf<FirebaseAnalytics.ConsentType, FirebaseAnalytics.ConsentStatus>()
            for (key in call.keys()) {
                val type = consentTypes[key]
                val status = call.optString(key)
                if (type == null || (status != "granted" && status != "denied")) {
                    throw HaylenBridge.Failure("The consent \"$key\" takes \"granted\" or \"denied\", for analyticsStorage, adStorage, adUserData and adPersonalization.", "invalidParams", null)
                }
                consent[type] = if (status == "granted") FirebaseAnalytics.ConsentStatus.GRANTED else FirebaseAnalytics.ConsentStatus.DENIED
            }

            analytics().setConsent(consent)
            reply.success(null)
        }

        context.register("setCollectionEnabled") { params, reply ->
            val enabled = (params as JSONObject).getBoolean("enabled")
            analytics().setAnalyticsCollectionEnabled(enabled)
            reply.success(JSONObject().put("enabled", enabled))
        }
    }

    // Analytics needs the default Firebase app, which a missing or invalid `google-services.json` leaves out.
    private fun analytics(): FirebaseAnalytics {
        val application = context.application()
        if (FirebaseApp.getApps(application).none { it.name == FirebaseApp.DEFAULT_APP_NAME }) {
            throw HaylenBridge.Failure("Firebase is not configured, so Analytics logs nothing. Give the plugin \"firebase\" a valid \"servicesJson\".", "notConfigured", null)
        }
        return FirebaseAnalytics.getInstance(application)
    }

    // Analytics takes texts, whole numbers, fractions and lists of items, so a flag becomes 1 or 0.
    private fun toBundle(values: JSONObject): Bundle {
        val bundle = Bundle()
        for (key in values.keys()) {
            when (val value = values.get(key)) {
                is String -> bundle.putString(key, value)
                is Boolean -> bundle.putLong(key, if (value) 1 else 0)
                is Int, is Long -> bundle.putLong(key, (value as Number).toLong())
                is Number -> bundle.putDouble(key, value.toDouble())
                is JSONArray -> bundle.putParcelableArray(key, toBundles(key, value))
                is JSONObject -> bundle.putBundle(key, toBundle(value))
                else -> throw HaylenBridge.Failure("The parameter \"$key\" of the event is a text, a number, a flag or a list of item tables.", "invalidParams", null)
            }
        }
        return bundle
    }

    private fun toBundles(key: String, items: JSONArray): Array<Bundle> =
        Array(items.length()) { index ->
            val item = items.optJSONObject(index) ?: throw HaylenBridge.Failure("The list \"$key\" of the event holds item tables alone.", "invalidParams", null)
            toBundle(item)
        }
}
