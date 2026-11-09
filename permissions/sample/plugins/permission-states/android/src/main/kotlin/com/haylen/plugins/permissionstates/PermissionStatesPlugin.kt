package com.haylen.plugins.permissionstates

import android.Manifest
import android.content.Context
import android.os.Build
import com.haylen.plugins.permissions.Permission
import com.haylen.plugins.permissions.Permissions
import dev.haylen.HaylenPlugin
import dev.haylen.HaylenPluginContext
import org.json.JSONObject

// Native part of the local plugin of the sample on Android. It registers a permission of every state through the Permissions plugin, whose permission `asked` is `POST_NOTIFICATIONS`, which shows the prompt of the system from Android 13 on, and answers `use` once the app holds the permission that the call names.
class PermissionStatesPlugin : HaylenPlugin() {
    override fun onLoad(context: HaylenPluginContext) {
        Permissions.register(context, Fixed("held", "granted"))
        Permissions.register(context, Asked())
        Permissions.register(context, Fixed("refused", "denied"))
        Permissions.register(context, Fixed("untold", "unknown"))
        Permissions.register(context, Absent())

        context.register("use") { params, reply ->
            val name = (params as JSONObject).getString("name")
            Permissions.require(context, name, reply) { reply.success("The plugin used the permission \"$name\".") }
        }
    }

    // A permission without a prompt, whose state never changes.
    private class Fixed(name: String, private val state: String) : Permission(name, "the permission \"$name\" of the sample") {
        override fun stateWithoutPrompt(context: Context): String = state
    }

    // Android asks for notifications from Android 13 on, and grants them before.
    private class Asked : Permission("asked", "notifications", Manifest.permission.POST_NOTIFICATIONS) {
        override fun required(context: Context): Array<String> {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) super.required(context) else emptyArray()
        }
    }

    private class Absent : Permission("absent", "the permission \"absent\" of the sample") {
        override fun unsupportedReason(context: Context): String = "The sample has the permission \"absent\" on no device."
    }
}
