package com.haylen.plugins.links

import android.content.Intent
import android.net.Uri
import dev.haylen.HaylenBridge
import dev.haylen.HaylenPlugin
import dev.haylen.HaylenPluginContext
import org.json.JSONObject

// Native part of the Links plugin on Android. The `haylen` library creates it from the `meta-data` of its manifest, and loads it when the app process starts.
class LinksPlugin : HaylenPlugin() {
    override fun onLoad(context: HaylenPluginContext) {
        // Answers `links.open` on the main thread with `true` once an activity took the view intent of the url, and fails with the code `unsupported` when none does.
        context.register("open") { params, reply ->
            val url = (params as JSONObject).getString("url")
            val activity = context.activity() ?: throw HaylenBridge.Failure("The url opens only while the app has an activity.", "unsupported", null)
            try {
                activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
            } catch (refused: RuntimeException) {
                // No activity takes the url, or Android refuses it, such as a file url that would leave the app.
                throw HaylenBridge.Failure("No app on this device opens \"$url\".", "unsupported", null)
            }
            reply.success(true)
        }
    }
}
