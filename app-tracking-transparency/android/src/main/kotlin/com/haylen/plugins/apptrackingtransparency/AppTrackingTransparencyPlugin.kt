package com.haylen.plugins.apptrackingtransparency

import com.haylen.plugins.permissions.Permission
import com.haylen.plugins.permissions.Permissions
import dev.haylen.HaylenBridge
import dev.haylen.HaylenPlugin
import dev.haylen.HaylenPluginContext

// Native part of the App Tracking Transparency plugin on Android. Android shows no prompt for tracking, so the permission `tracking`, which it registers through the Permissions plugin, needs no permission of the manifest and answers `granted`. The advertising identifier of Android belongs to Google Play services, which this plugin does not bring, so `advertisingId` fails with the code `unsupported`.
class AppTrackingTransparencyPlugin : HaylenPlugin() {
    override fun onLoad(context: HaylenPluginContext) {
        Permissions.register(context, Permission("tracking", "tracking across the apps and websites of other companies"))

        context.register("advertisingId") { _, _ ->
            throw HaylenBridge.Failure("Android gives the advertising identifier through Google Play services, which the plugin \"app-tracking-transparency\" does not bring.", "unsupported", null)
        }
    }
}
