package com.haylen.plugins.location

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

// The foreground service of type `location` that keeps the updates of a watch coming while the app is in the background, with the notification that Android shows for it. The watch starts it while the app is in front, as Android requires, and stops it with the updates.
class LocationWatchService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val text = intent?.getStringExtra(TEXT) ?: ""
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION else 0
        ServiceCompat.startForeground(this, NOTIFICATION, notification(text), type)
        return START_NOT_STICKY
    }

    private fun notification(text: String): Notification {
        val channel = NotificationChannel(CHANNEL, text, NotificationManager.IMPORTANCE_LOW)
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)

        val title = applicationInfo.loadLabel(packageManager)
        val builder = NotificationCompat.Builder(this, CHANNEL)
        builder.setSmallIcon(applicationInfo.icon)
        builder.setContentTitle(title)
        builder.setContentText(text)
        builder.setOngoing(true)
        return builder.build()
    }

    companion object {
        const val TEXT = "com.haylen.plugins.location.text"
        private const val CHANNEL = "com.haylen.plugins.location"
        private const val NOTIFICATION = 0x4C4F43
    }
}
