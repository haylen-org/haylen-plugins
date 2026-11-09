package com.haylen.plugins.location

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import com.haylen.plugins.permissions.Permissions
import dev.haylen.HaylenBridge
import dev.haylen.HaylenPlugin
import dev.haylen.HaylenPluginContext
import dev.haylen.HaylenRequirements
import org.json.JSONObject

// Native part of the Location plugin on Android: one fix of `LocationManager` or its updates, and the permissions `location`, `preciseLocation` and `backgroundLocation`. The `haylen` library creates it from the `meta-data` of its manifest, and loads it when the app process starts.
class LocationPlugin : HaylenPlugin() {
    private lateinit var context: HaylenPluginContext
    private lateinit var updates: LocationUpdates
    private var background = false

    override fun onLoad(context: HaylenPluginContext) {
        this.context = context
        updates = LocationUpdates(context.application()) { event, payload -> context.emit(event, payload, false, event == "changed") }

        Permissions.register(context, LocationPermissions.location)
        Permissions.register(context, LocationPermissions.preciseLocation)
        Permissions.register(context, LocationPermissions.backgroundLocation)

        // Every app that loads the Lua API sends `reset`, so updates that an earlier app of the process left running stop.
        context.register("reset") { _, reply ->
            stop()
            reply.success(null)
        }

        context.register("current") { params, reply ->
            val options = params as JSONObject
            val precise = options.getBoolean("precise")
            requireDevice()
            Permissions.require(context, if (precise) "preciseLocation" else "location", reply) {
                updates.current(precise, options.getDouble("timeout"), reply)
            }
        }

        context.register("watch") { params, reply ->
            val options = params as JSONObject
            val precise = options.getBoolean("precise")
            val inBackground = options.getBoolean("background")
            requireDevice()
            if (inBackground) {
                requireForegroundService()
            }
            Permissions.require(context, if (precise) "preciseLocation" else "location", reply) { watchWithLocation(precise, options, inBackground, reply) }
        }

        context.register("stop") { _, reply ->
            stop()
            reply.success(null)
        }
    }

    private fun requireDevice() {
        if (!context.application().packageManager.hasSystemFeature(PackageManager.FEATURE_LOCATION)) {
            throw HaylenBridge.Failure("This device has no location.", "unsupported", null)
        }
    }

    // The foreground service that keeps a watch in the background needs the permissions that only the apps that watch in the background declare.
    private fun requireForegroundService() {
        val service = HaylenRequirements.Requirement.permission(Manifest.permission.FOREGROUND_SERVICE)
        val serviceLocation = HaylenRequirements.Requirement.permission(Manifest.permission.FOREGROUND_SERVICE_LOCATION)
        context.requirements().require(service, serviceLocation)
    }

    // A watch in the background asks for the location in the background once the app holds the location.
    private fun watchWithLocation(precise: Boolean, options: JSONObject, inBackground: Boolean, reply: HaylenBridge.Reply) {
        if (!inBackground) {
            watch(precise, options, false, reply)
            return
        }
        Permissions.require(context, "backgroundLocation", reply) { watch(precise, options, true, reply) }
    }

    private fun watch(precise: Boolean, options: JSONObject, inBackground: Boolean, reply: HaylenBridge.Reply) {
        updates.watch(precise, options.getDouble("distance").toFloat())
        stopService()

        if (inBackground) {
            val text = context.config().optString("backgroundNotification")
            val intent = Intent(context.application(), LocationWatchService::class.java).putExtra(LocationWatchService.TEXT, text)
            ContextCompat.startForegroundService(context.application(), intent)
            background = true
        }
        reply.success(null)
    }

    private fun stop() {
        updates.stop()
        stopService()
    }

    private fun stopService() {
        if (background) {
            context.application().stopService(Intent(context.application(), LocationWatchService::class.java))
            background = false
        }
    }
}
