package com.haylen.plugins.dialogs

import androidx.appcompat.app.AlertDialog
import dev.haylen.HaylenActivity
import dev.haylen.HaylenBridge
import org.json.JSONObject

// The messages of the plugin, each an `AlertDialog` of AppCompat. In the order of the buttons of the app, its buttons are the positive, the negative and the neutral button of the dialog, so the first one sits on the right. The back button and a touch outside dismiss a message without a button. An Android app keeps running while a message shows, so a cancel or a timeout of the app closes the message at once. Everything here runs on the main thread.
class DialogsMessages {
    private val shown = HashSet<AlertDialog>()

    fun show(activity: HaylenActivity?, request: JSONObject, reply: HaylenBridge.Reply) {
        if (activity == null) {
            reply.failure("The app has no activity to show the message over.", "failed", null)
            return
        }
        val buttons = request.getJSONArray("buttons")
        val builder = AlertDialog.Builder(activity)
        builder.setMessage(request.getString("text"))
        val title = request.optString("title")
        if (title.isNotEmpty()) {
            val icon = if (request.optString("kind") == "info") android.R.drawable.ic_dialog_info else android.R.drawable.ic_dialog_alert
            builder.setTitle(title)
            builder.setIcon(icon)
        }
        builder.setPositiveButton(buttons.getString(0)) { _, _ -> reply.success(1) }
        if (buttons.length() > 1) {
            builder.setNegativeButton(buttons.getString(1)) { _, _ -> reply.success(2) }
        }
        if (buttons.length() > 2) {
            builder.setNeutralButton(buttons.getString(2)) { _, _ -> reply.success(3) }
        }
        builder.setOnCancelListener { reply.success(null) }

        val message = builder.create()
        message.setOnDismissListener { shown.remove(message) }
        shown.add(message)
        reply.onCancel { message.dismiss() }
        message.show()
    }

    fun dismissAll() {
        for (message in shown.toList()) {
            message.dismiss()
        }
        shown.clear()
    }
}
