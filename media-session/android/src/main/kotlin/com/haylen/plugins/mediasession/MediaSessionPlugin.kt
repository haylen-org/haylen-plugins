package com.haylen.plugins.mediasession

import dev.haylen.HaylenActivity
import dev.haylen.HaylenPlugin
import dev.haylen.HaylenPluginContext
import org.json.JSONObject

// Native part of the Media Session plugin on Android. The `haylen` library creates it from the `meta-data` of its manifest, and loads it when the app process starts. Its handlers run on the main thread, where the controls of `MediaSessionControls` live.
class MediaSessionPlugin : HaylenPlugin() {
    override fun onLoad(context: HaylenPluginContext) {
        // The controls belong to the activity, so a call that arrives while the app has none changes nothing.
        context.register("setNowPlaying") { params, reply ->
            val activity = context.activity()
            if (activity != null) {
                MediaSessionControls.show(activity, context, params as JSONObject)
            }
            reply.success(null)
        }

        context.register("clear") { _, reply ->
            MediaSessionControls.release()
            reply.success(null)
        }

        context.register("nowPlaying") { _, reply ->
            reply.success(MediaSessionControls.describe())
        }
    }

    override fun onActivityDestroyed(activity: HaylenActivity) {
        MediaSessionControls.release(activity)
    }
}
