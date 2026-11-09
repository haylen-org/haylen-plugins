package com.haylen.plugins.localnetwork

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import androidx.core.content.ContextCompat
import dev.haylen.HaylenBridge
import org.json.JSONObject

// The service of the app that `NsdManager` advertises on the local network, by its type, the name that people see and the port where the app listens, while the app owns the socket itself. One advertisement runs at a time, its answers reach the main thread, and the call that started it answers with the name that the network took, which differs from the name asked for when another service of the network holds it.
class LocalNetworkAdvertisement(context: Context) {
    // The registration that runs and the call that waits for its name, until the name or a failure answers it.
    private class Running(val listener: NsdManager.RegistrationListener, var reply: HaylenBridge.Reply?)

    private val manager = context.getSystemService(NsdManager::class.java)
    private val main = ContextCompat.getMainExecutor(context)
    private var running: Running? = null

    fun start(type: String, name: String, port: Int, reply: HaylenBridge.Reply) {
        stop()

        val service = NsdServiceInfo()
        service.serviceName = name
        service.serviceType = type
        service.port = port

        val registration = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(info: NsdServiceInfo) {
                main.execute {
                    val waiting = current(this)?.takeReply()
                    waiting?.success(JSONObject().put("name", info.serviceName).put("type", type).put("port", port))
                }
            }

            override fun onRegistrationFailed(info: NsdServiceInfo, errorCode: Int) {
                main.execute {
                    val failed = current(this) ?: return@execute
                    running = null
                    failed.takeReply()?.failure("The system did not advertise the service \"$name\" of the type \"$type\", with the error $errorCode of NsdManager.", "failed", null)
                }
            }

            override fun onServiceUnregistered(info: NsdServiceInfo) {}

            override fun onUnregistrationFailed(info: NsdServiceInfo, errorCode: Int) {}
        }
        running = Running(registration, reply)
        manager.registerService(service, NsdManager.PROTOCOL_DNS_SD, registration)
    }

    // Ends the advertisement, and a call that still waits for its name fails with the code `cancelled`.
    fun stop() {
        val stopped = running ?: return
        running = null
        manager.unregisterService(stopped.listener)
        stopped.takeReply()?.failure("The app stopped the advertisement before the network took it.", "cancelled", null)
    }

    // The answers of a registration that a later one replaced reach nothing.
    private fun current(listener: NsdManager.RegistrationListener): Running? = running?.takeIf { it.listener === listener }

    private fun Running.takeReply(): HaylenBridge.Reply? {
        val waiting = reply
        reply = null
        return waiting
    }
}
