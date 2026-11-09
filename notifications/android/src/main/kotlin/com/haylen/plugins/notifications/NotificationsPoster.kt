package com.haylen.plugins.notifications

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import dev.haylen.HaylenLinkActivity
import org.json.JSONArray
import org.json.JSONObject

// Posts the notifications of the plugin in its two channels, with sound and without, and lists the ones that show. Each one carries the tag of the plugin with its id, so the plugin finds its own notifications among those of the app. Android fixes the sound of a channel once it exists, so the sound of a notification picks its channel.
object NotificationsPoster {
    const val ACTION_OPEN = "com.haylen.plugins.notifications.OPEN"
    const val EXTRA_ID = "com.haylen.plugins.notifications.ID"
    const val EXTRA_DATA = "com.haylen.plugins.notifications.DATA"

    private const val CHANNEL = "notifications"
    private const val SILENT_CHANNEL = "notifications.silent"
    private const val TAG_PREFIX = "notifications."
    private const val LOG_TAG = "notifications"

    fun tag(id: String) = TAG_PREFIX + id

    fun createChannels(context: Context, name: String, silentName: String) {
        val manager = NotificationManagerCompat.from(context)
        manager.createNotificationChannel(NotificationChannelCompat.Builder(CHANNEL, NotificationManagerCompat.IMPORTANCE_HIGH).setName(name).build())
        manager.createNotificationChannel(NotificationChannelCompat.Builder(SILENT_CHANNEL, NotificationManagerCompat.IMPORTANCE_HIGH).setName(silentName).setSound(null, null).build())
    }

    // The tap starts `HaylenLinkActivity`, whose data names the notification, so the taps of two notifications never share an intent.
    fun post(context: Context, entry: NotificationsStore.Entry) {
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) {
            Log.w(LOG_TAG, "The notification \"${entry.id}\" was dropped, because the person turned the notifications of the app off.")
            return
        }

        val open = Intent(context, HaylenLinkActivity::class.java)
        open.action = ACTION_OPEN
        open.data = Uri.fromParts("notification", entry.id, null)
        open.putExtra(EXTRA_ID, entry.id)
        open.putExtra(EXTRA_DATA, entry.dataText())
        open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        val tap = PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val extras = Bundle()
        extras.putString(EXTRA_DATA, entry.dataText())

        val builder = NotificationCompat.Builder(context, if (entry.sound) CHANNEL else SILENT_CHANNEL)
        builder.setSmallIcon(R.drawable.notifications_icon)
        builder.setContentTitle(entry.title)
        builder.setContentText(entry.body)
        builder.setStyle(NotificationCompat.BigTextStyle().bigText(entry.body))
        builder.setContentIntent(tap)
        builder.setAutoCancel(true)
        builder.setWhen(System.currentTimeMillis())
        builder.addExtras(extras)
        entry.badge?.let { builder.setNumber(it) }

        try {
            manager.notify(tag(entry.id), 0, builder.build())
        } catch (denied: SecurityException) {
            Log.w(LOG_TAG, "The notification \"${entry.id}\" was dropped, because the app lacks the permission \"android.permission.POST_NOTIFICATIONS\".", denied)
        }
    }

    // The notifications of the plugin that show, in the order they posted.
    fun delivered(context: Context): JSONArray {
        val manager = context.getSystemService(NotificationManager::class.java)
        val shown = manager.activeNotifications.filter { it.tag?.startsWith(TAG_PREFIX) == true }.sortedBy { it.postTime }
        val entries = JSONArray()
        for (status in shown) {
            val extras = status.notification.extras
            val entry = JSONObject().put("id", status.tag.removePrefix(TAG_PREFIX))
            entry.put("title", extras.getCharSequence(NotificationCompat.EXTRA_TITLE)?.toString() ?: "")
            entry.put("body", extras.getCharSequence(NotificationCompat.EXTRA_TEXT)?.toString() ?: "")
            entry.put("date", status.postTime / 1000.0)
            entry.put("data", NotificationsStore.Entry.readData(extras.getString(EXTRA_DATA)))
            entries.put(entry)
        }
        return entries
    }

    fun cancelAll(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        for (status in manager.activeNotifications) {
            if (status.tag?.startsWith(TAG_PREFIX) == true) {
                manager.cancel(status.tag, status.id)
            }
        }
    }
}
