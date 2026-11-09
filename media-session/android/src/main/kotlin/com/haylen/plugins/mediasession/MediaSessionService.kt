package com.haylen.plugins.mediasession

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import androidx.core.app.ServiceCompat

// Keeps the app in the foreground while what it plays shows as playing, with the media notification of its media session as the notification of the service, so Android neither freezes nor ends the process while the sound plays in the background. The manifest of the module declares it with the type `mediaPlayback` and its permissions.
class MediaSessionService : Service() {
    // Android expects the notification of the service at once, also when the app paused in between, so the service shows it and then leaves the foreground again. The controls start the service only after they showed a notification.
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = checkNotNull(MediaSessionControls.notification) { "The media session service started before the controls showed a notification." }
        ServiceCompat.startForeground(this, MediaSessionControls.NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)

        if (!MediaSessionControls.foreground) {
            stopSelf()
        }

        return START_NOT_STICKY
    }

    // The notification stays in the shade with the paused controls, and goes with the service once the app left the controls, since Android keeps the notification of a service from being cancelled.
    override fun onDestroy() {
        ServiceCompat.stopForeground(this, if (MediaSessionControls.isShowing) ServiceCompat.STOP_FOREGROUND_DETACH else ServiceCompat.STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
