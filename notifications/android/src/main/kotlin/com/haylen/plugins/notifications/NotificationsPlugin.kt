package com.haylen.plugins.notifications

import android.content.Intent
import android.os.Bundle
import com.haylen.plugins.permissions.Permissions
import dev.haylen.HaylenActivity
import dev.haylen.HaylenPlugin
import dev.haylen.HaylenPluginContext
import org.json.JSONArray
import org.json.JSONObject

// Native part of the Notifications plugin on Android. The `haylen` library creates it from the `meta-data` of its manifest and loads it when the app process starts, also when the alarm of a notification or the start of the device starts the process. Each notification waits for an alarm of `AlarmManager`, which `NotificationsReceiver` answers by posting it, and its tap starts `HaylenLinkActivity` of the `haylen-links` library, which hands it to the running app or starts the app with it.
class NotificationsPlugin : HaylenPlugin() {
    private lateinit var context: HaylenPluginContext

    override fun onLoad(context: HaylenPluginContext) {
        this.context = context
        val application = context.application()
        val config = context.config()
        NotificationsPoster.createChannels(application, config.getString("channelName"), config.getString("silentChannelName"))

        // A force stop of the app or an update drops its alarms, so every start of the process sets the alarms of the notifications that wait again.
        NotificationsAlarms.scheduleAll(application)

        Permissions.register(context, NotificationsPermission())
        registerSchedule()
        registerLists()
        registerCancels()
    }

    private fun registerSchedule() {
        context.register("schedule") { params, reply ->
            val notification = NotificationsStore.Entry.fromParams(params as JSONObject)
            Permissions.require(context, "notifications", reply) {
                val application = context.application()
                NotificationsStore.put(application, notification)
                NotificationsAlarms.schedule(application, notification)
                reply.success(JSONObject().put("id", notification.id).put("date", notification.date))
            }
        }
    }

    private fun registerLists() {
        context.register("pending") { _, reply ->
            val entries = JSONArray()
            for (notification in NotificationsStore.all(context.application())) {
                entries.put(notification.describe())
            }
            reply.success(entries)
        }

        context.register("delivered") { _, reply ->
            reply.success(NotificationsPoster.delivered(context.application()))
        }
    }

    private fun registerCancels() {
        context.register("cancel") { params, reply ->
            NotificationsAlarms.cancel(context.application(), (params as JSONObject).getString("id"))
            reply.success(JSONObject())
        }

        context.register("cancelAll") { _, reply ->
            val application = context.application()
            for (notification in NotificationsStore.all(application)) {
                NotificationsAlarms.cancel(application, notification.id)
            }
            NotificationsPoster.cancelAll(application)
            reply.success(JSONObject())
        }
    }

    // The tap that launched the app comes with the intent of the first activity, and a tap while the app runs comes as a new intent. An activity that Android restores after it ended the process gets the intent again with a saved state, so it was already sent.
    override fun onActivityCreated(activity: HaylenActivity, savedInstanceState: Bundle?) {
        if (savedInstanceState == null) {
            sendOpened(activity.intent)
        }
    }

    override fun onNewIntent(intent: Intent) {
        sendOpened(intent)
    }

    // The tap on a notification of the plugin reaches the app as `opened`, retained, so the tap that launched the app waits for the first listener.
    private fun sendOpened(intent: Intent?) {
        if (intent?.action != NotificationsPoster.ACTION_OPEN) {
            return
        }
        val id = intent.getStringExtra(NotificationsPoster.EXTRA_ID) ?: return
        val data = NotificationsStore.Entry.readData(intent.getStringExtra(NotificationsPoster.EXTRA_DATA))
        val payload = JSONObject().put("id", id).put("data", data)
        context.emitRetained("opened", payload)
    }
}
