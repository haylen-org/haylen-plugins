package com.haylen.plugins.notifications

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.app.NotificationManagerCompat

// The alarms of the notifications that wait. An alarm wakes the process in the background, or starts it when it was closed, which a timer of the process could not. It goes off while the device idles too, at about its time, so the plugin needs no permission for exact alarms, which Android keeps for alarm clocks and calendars.
object NotificationsAlarms {
    fun schedule(context: Context, entry: NotificationsStore.Entry) {
        val manager = context.getSystemService(AlarmManager::class.java)
        manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, (entry.date * 1000).toLong(), alarm(context, entry.id))
    }

    fun scheduleAll(context: Context) {
        for (entry in NotificationsStore.all(context)) {
            schedule(context, entry)
        }
    }

    // Cancels the alarm of a notification that waits and takes away the notification when it already posted.
    fun cancel(context: Context, id: String) {
        context.getSystemService(AlarmManager::class.java).cancel(alarm(context, id))
        NotificationsStore.remove(context, id)
        NotificationManagerCompat.from(context).cancel(NotificationsPoster.tag(id), 0)
    }

    // The data of the intent names the notification, so two notifications never share an alarm, whatever the hashes of their ids.
    private fun alarm(context: Context, id: String): PendingIntent {
        val post = Intent(context, NotificationsReceiver::class.java)
        post.action = NotificationsReceiver.ACTION_POST
        post.data = Uri.fromParts("notification", id, null)
        return PendingIntent.getBroadcast(context, 0, post, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }
}
