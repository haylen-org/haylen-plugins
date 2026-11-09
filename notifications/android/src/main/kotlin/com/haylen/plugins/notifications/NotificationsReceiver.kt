package com.haylen.plugins.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

// Posts a notification when its alarm goes off, whether the app runs, waits in the background or was closed, and sets the alarms again when the device starts, since a restart drops every alarm.
class NotificationsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            NotificationsAlarms.scheduleAll(context)
            return
        }

        val id = intent.data?.schemeSpecificPart ?: return
        val entry = NotificationsStore.get(context, id) ?: return
        NotificationsStore.remove(context, id)
        NotificationsPoster.post(context, entry)
    }

    companion object {
        const val ACTION_POST = "com.haylen.plugins.notifications.POST"
    }
}
