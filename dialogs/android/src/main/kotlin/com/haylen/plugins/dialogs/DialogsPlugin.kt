package com.haylen.plugins.dialogs

import android.os.Bundle
import dev.haylen.HaylenActivity
import dev.haylen.HaylenPlugin
import dev.haylen.HaylenPluginContext
import org.json.JSONObject

// Native part of the Dialogs plugin on Android. The `haylen` library creates it from the `meta-data` of its manifest, and loads it when the app process starts. A message is an `AlertDialog` of AppCompat over the activity. The pickers are the document picker and the document creator of the Storage Access Framework and the photo picker of the system, whose launchers the plugin registers under stable keys when each activity is created.
class DialogsPlugin : HaylenPlugin() {
    private val messages = DialogsMessages()
    private lateinit var pickers: DialogsPickers

    override fun onLoad(context: HaylenPluginContext) {
        val copies = DialogsCopies(context.application())
        copies.clear()
        pickers = DialogsPickers(context, copies)

        context.register("message") { params, reply -> messages.show(context.activity(), params as JSONObject, reply) }
        context.register("openFiles") { params, reply -> pickers.openFiles(params as JSONObject, reply) }
        context.register("saveFile") { params, reply -> pickers.saveFile(params as JSONObject, reply) }
        context.register("openFolder") { _, reply -> reply.failure("Android folders have no paths, so Android opens no folders.", "unsupported", null) }
        context.register("openPhotos") { params, reply -> pickers.openPhotos(params as JSONObject, reply) }
    }

    override fun onActivityCreated(activity: HaylenActivity, savedInstanceState: Bundle?) {
        pickers.register(activity)
    }

    // The messages of an activity that goes away close with it, since the app that showed them stopped.
    override fun onActivityDestroyed(activity: HaylenActivity) {
        messages.dismissAll()
    }
}
