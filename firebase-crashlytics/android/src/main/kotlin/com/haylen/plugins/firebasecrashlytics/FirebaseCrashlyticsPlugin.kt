package com.haylen.plugins.firebasecrashlytics

import android.os.Handler
import android.os.Looper
import com.google.firebase.FirebaseApp
import com.google.firebase.crashlytics.FirebaseCrashlytics
import com.google.firebase.crashlytics.setCustomKeys
import dev.haylen.HaylenBridge
import dev.haylen.HaylenPlugin
import dev.haylen.HaylenPluginContext
import org.json.JSONArray
import org.json.JSONObject

// Native part of the Firebase Crashlytics plugin on Android. Crashlytics reports through the default Firebase app that the plugin `firebase` configures, and every Lua error that stops the app reaches it as a non-fatal error with the frames of the Lua stack.
class FirebaseCrashlyticsPlugin : HaylenPlugin() {
    // A Lua error as an exception whose stack trace is the Lua stack, from the innermost call outward.
    class LuaError(message: String, frames: JSONArray) : Exception(message) {
        init {
            stackTrace = Array(frames.length()) { index ->
                val frame = frames.getJSONObject(index)
                StackTraceElement("lua", frame.optString("function", "?"), frame.optString("source", "?"), frame.optInt("line"))
            }
        }
    }

    private lateinit var context: HaylenPluginContext
    private var reportsLuaErrors = false

    override fun onLoad(context: HaylenPluginContext) {
        this.context = context
        reportsLuaErrors = context.config().getBoolean("reportLuaErrors")
        registerReports()
        registerCollection()

        // Crashes the app on purpose after the answer, so a project checks that its crashes reach Crashlytics.
        context.register("crash") { _, reply ->
            requireConfigured()
            reply.success(JSONObject().put("crashing", true))
            Handler(Looper.getMainLooper()).postDelayed({ throw RuntimeException("A test crash that the app asked for through the plugin \"firebase-crashlytics\".") }, 500)
        }
    }

    override fun onAppError(error: JSONObject) {
        if (!reportsLuaErrors || !isConfigured()) {
            return
        }
        val message = error.optString("message", "The Lua code of the app failed.")
        val frames = error.optJSONArray("frames") ?: JSONArray()
        FirebaseCrashlytics.getInstance().recordException(LuaError(message, frames))
    }

    private fun registerReports() {
        context.register("log") { params, reply ->
            val message = (params as JSONObject).getString("message")
            crashlytics().log(message)
            reply.success(JSONObject().put("logged", true))
        }

        context.register("setUserId") { params, reply ->
            val call = params as? JSONObject
            val id = if (call == null || call.isNull("id")) "" else call.getString("id")
            crashlytics().setUserId(id)
            reply.success(null)
        }

        // Custom keys take texts, numbers and flags.
        context.register("setCustomKeys") { params, reply ->
            val keys = params as? JSONObject ?: throw HaylenBridge.Failure("The method \"setCustomKeys\" needs a table of keys and values.", "invalidParams", null)
            crashlytics().setCustomKeys {
                for (key in keys.keys()) {
                    when (val value = keys.get(key)) {
                        is Boolean -> key(key, value)
                        is Int, is Long -> key(key, (value as Number).toLong())
                        is Number -> key(key, value.toDouble())
                        is String -> key(key, value)
                        else -> throw HaylenBridge.Failure("The custom key \"$key\" takes a text, a number or a flag.", "invalidParams", null)
                    }
                }
            }
            reply.success(null)
        }

        context.register("recordError") { params, reply ->
            val call = params as? JSONObject
            if (call == null || !call.has("message")) {
                throw HaylenBridge.Failure("The method \"recordError\" needs the message of the error.", "invalidParams", null)
            }
            val frames = call.optJSONArray("frames") ?: JSONArray()
            crashlytics().recordException(LuaError(call.getString("message"), frames))
            reply.success(null)
        }
    }

    private fun registerCollection() {
        context.register("setCollectionEnabled") { params, reply ->
            val enabled = (params as JSONObject).getBoolean("enabled")
            crashlytics().isCrashlyticsCollectionEnabled = enabled
            reply.success(JSONObject().put("enabled", enabled))
        }

        context.register("didCrashOnPreviousExecution") { _, reply ->
            reply.success(JSONObject().put("crashed", crashlytics().didCrashOnPreviousExecution()))
        }

        context.register("sendUnsentReports") { _, reply ->
            crashlytics().sendUnsentReports()
            reply.success(JSONObject().put("sent", true))
        }

        context.register("deleteUnsentReports") { _, reply ->
            crashlytics().deleteUnsentReports()
            reply.success(JSONObject().put("deleted", true))
        }
    }

    private fun isConfigured(): Boolean =
        FirebaseApp.getApps(context.application()).any { it.name == FirebaseApp.DEFAULT_APP_NAME }

    // Crashlytics needs the default Firebase app, which a missing or invalid `google-services.json` leaves out.
    private fun requireConfigured() {
        if (!isConfigured()) {
            throw HaylenBridge.Failure("Firebase is not configured, so Crashlytics reports nothing. Give the plugin \"firebase\" a valid \"servicesJson\".", "notConfigured", null)
        }
    }

    private fun crashlytics(): FirebaseCrashlytics {
        requireConfigured()
        return FirebaseCrashlytics.getInstance()
    }
}
