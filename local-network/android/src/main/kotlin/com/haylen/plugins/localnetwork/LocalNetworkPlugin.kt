package com.haylen.plugins.localnetwork

import com.haylen.plugins.permissions.Permissions
import dev.haylen.HaylenPlugin
import dev.haylen.HaylenPluginContext
import org.json.JSONObject

// Native part of the Local Network plugin on Android: the permission `localNetwork`, the picker of the services of `NsdManager`, which hands the app the service the person picks without the permission, and the advertisement of a service of the app. The `haylen` library creates it from the `meta-data` of its manifest, and loads it when the app process starts.
class LocalNetworkPlugin : HaylenPlugin() {
    private lateinit var advertisement: LocalNetworkAdvertisement

    override fun onLoad(context: HaylenPluginContext) {
        val picker = LocalNetworkPicker(context.application())
        advertisement = LocalNetworkAdvertisement(context.application())

        Permissions.register(context, LocalNetworkPermission())

        // Every app that loads the Lua API sends `reset`, so an advertisement that an earlier app of the process left stops.
        context.register("reset") { _, reply ->
            advertisement.stop()
            reply.success(null)
        }

        context.register("pickService") { params, reply ->
            picker.pick((params as JSONObject).getString("type"), reply)
        }

        // A service of the app receives connections from the local network, which needs the permission on Android 17 and later.
        context.register("advertise") { params, reply ->
            val options = params as JSONObject
            Permissions.require(context, "localNetwork", reply) {
                advertisement.start(options.getString("type"), options.getString("name"), options.getInt("port"), reply)
            }
        }

        context.register("stopAdvertising") { _, reply ->
            advertisement.stop()
            reply.success(null)
        }
    }
}
