package com.haylen.plugins.bluetooth

import com.haylen.plugins.permissions.Permissions
import dev.haylen.HaylenBridge
import dev.haylen.HaylenPlugin
import dev.haylen.HaylenPluginContext
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

// Native part of the Bluetooth plugin on Android, built on the Bluetooth Low Energy API of the system. The `haylen` library creates it from the `meta-data` of its manifest and loads it when the app process starts. Every method but `stopScan` and `disconnect` asks for the permission `bluetooth` first, where the app does not hold it yet, and `BluetoothCentral` does the work on the main thread.
class BluetoothPlugin : HaylenPlugin() {
    private lateinit var context: HaylenPluginContext
    private lateinit var central: BluetoothCentral

    override fun onLoad(context: HaylenPluginContext) {
        this.context = context
        central = BluetoothCentral(context)
        Permissions.register(context, BluetoothPermission())

        handle("scan") { params, reply -> central.scan(uuids(params, "services"), params.getDouble("seconds"), reply) }
        context.register("stopScan") { _, reply ->
            central.stopScan()
            reply.success(JSONObject())
        }
        handle("connect") { params, reply -> central.connect(params.getString("id"), reply) }
        context.register("disconnect") { params, reply -> central.disconnect((params as JSONObject).getString("id"), reply) }
        handle("services") { params, reply -> central.services(params.getString("id"), reply) }
        handle("characteristics") { params, reply -> central.characteristics(params.getString("id"), UUID.fromString(params.getString("service")), reply) }
        handle("read") { params, reply -> central.read(target(params), reply) }
        handle("write") { params, reply -> central.write(target(params), params.get("value") as ByteArray, params.getBoolean("response"), reply) }
        handle("subscribe") { params, reply -> central.setNotify(target(params), true, reply) }
        handle("unsubscribe") { params, reply -> central.setNotify(target(params), false, reply) }
    }

    // Answers `bluetooth.<method>` once the app holds the permission, with the parameters as a JSON object.
    private fun handle(method: String, body: (JSONObject, HaylenBridge.Reply) -> Unit) {
        context.register(method) { params, reply ->
            Permissions.require(context, "bluetooth", reply) { body(params as JSONObject, reply) }
        }
    }

    // An empty list of Lua crosses the bridge as an empty object.
    private fun uuids(params: JSONObject, key: String): List<UUID> {
        val value = params.get(key)
        if (value is JSONObject && value.length() == 0) {
            return emptyList()
        }

        val list = value as? JSONArray ?: throw HaylenBridge.Failure("The call needs \"$key\" as a list of UUIDs.", "invalidParams", null)
        return (0 until list.length()).map { UUID.fromString(list.getString(it)) }
    }

    private fun target(params: JSONObject): BluetoothCentral.Target {
        val service = UUID.fromString(params.getString("service"))
        val characteristic = UUID.fromString(params.getString("characteristic"))
        return BluetoothCentral.Target(params.getString("id"), service, characteristic)
    }
}
