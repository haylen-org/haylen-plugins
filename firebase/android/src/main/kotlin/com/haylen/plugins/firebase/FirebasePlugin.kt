package com.haylen.plugins.firebase

import com.google.firebase.FirebaseApp
import dev.haylen.HaylenBridge
import dev.haylen.HaylenPlugin
import dev.haylen.HaylenPluginContext
import org.json.JSONObject

// Native part of the Firebase plugin on Android. The provider of the Firebase libraries configures the default Firebase app from the resources that the Gradle plugin of Google services makes out of `app/google-services.json`, which the tooling copies from the parameter `servicesJson`, before this plugin loads.
class FirebasePlugin : HaylenPlugin() {
    override fun onLoad(context: HaylenPluginContext) {
        context.register("app") { _, reply ->
            val app = defaultApp(context)
            val options = app.options
            val described = JSONObject()
                .put("name", app.name)
                .put("projectId", options.projectId)
                .put("appId", options.applicationId)
                .put("senderId", options.gcmSenderId)
                .put("dataCollection", app.isDataCollectionDefaultEnabled)
            reply.success(described)
        }

        context.register("setDataCollection") { params, reply ->
            // The overload of a nullable value is the current one, where `null` would bring back the default of the manifest.
            val enabled: Boolean? = (params as JSONObject).getBoolean("enabled")
            defaultApp(context).setDataCollectionDefaultEnabled(enabled)
            reply.success(JSONObject().put("enabled", enabled))
        }
    }

    // The resources of a missing or invalid `google-services.json` configure no default app, and every call of the Firebase plugins then fails with the code `notConfigured`.
    private fun defaultApp(context: HaylenPluginContext): FirebaseApp {
        val apps = FirebaseApp.getApps(context.application())
        return apps.firstOrNull { it.name == FirebaseApp.DEFAULT_APP_NAME }
            ?: throw HaylenBridge.Failure("Firebase is not configured. Give the parameter \"servicesJson\" the google-services.json of the Android app of the Firebase project.", "notConfigured", null)
    }
}
