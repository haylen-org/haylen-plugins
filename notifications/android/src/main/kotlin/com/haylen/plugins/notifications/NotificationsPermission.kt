package com.haylen.plugins.notifications

import android.Manifest
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationManagerCompat
import com.haylen.plugins.permissions.Permission

// The permission `notifications`, which Android asks the person for from Android 13 on. Before that the app needs no permission, while the person may turn the notifications of the app off in the settings, which no prompt turns on again.
class NotificationsPermission : Permission("notifications", "notifications") {
    override fun required(context: Context): Array<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) arrayOf(Manifest.permission.POST_NOTIFICATIONS) else emptyArray()
    }

    override fun stateWithoutPrompt(context: Context): String {
        return if (NotificationManagerCompat.from(context).areNotificationsEnabled()) "granted" else "denied"
    }
}
