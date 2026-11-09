package com.haylen.plugins.localnetwork

import android.content.Context
import android.net.nsd.DiscoveryRequest
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.os.ext.SdkExtensions
import androidx.annotation.RequiresExtension
import dev.haylen.HaylenBridge
import java.net.Inet4Address
import org.json.JSONArray
import org.json.JSONObject

// The picker of the system that `NsdManager` shows for a discovery with `DiscoveryRequest.FLAG_SHOW_PICKER`: the person picks one service of the type, and the app then reaches its addresses without the permission `ACCESS_LOCAL_NETWORK`, a grant that lasts across restarts. The picker comes with the update 22 of the extensions of Android 13, which every Android 14 and later receives.
class LocalNetworkPicker(private val context: Context) {
    fun pick(type: String, reply: HaylenBridge.Reply) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || SdkExtensions.getExtensionVersion(Build.VERSION_CODES.TIRAMISU) < PICKER_EXTENSION) {
            throw HaylenBridge.Failure("This device has no picker of the services of the local network, which comes with Android 14 and the updates of the system that bring it.", "unsupported", null)
        }
        show(type, reply)
    }

    // The picker answers once: the service the person picked, after which the callback ends itself, or the end of the callback without a service when the person closed the picker.
    @RequiresExtension(extension = Build.VERSION_CODES.TIRAMISU, version = PICKER_EXTENSION)
    private fun show(type: String, reply: HaylenBridge.Reply) {
        val manager = context.getSystemService(NsdManager::class.java)
        val request = DiscoveryRequest.Builder(type).setFlags(DiscoveryRequest.FLAG_SHOW_PICKER).build()
        val callback = object : NsdManager.ServiceInfoCallback {
            private var answered = false

            override fun onServiceInfoCallbackRegistrationFailed(errorCode: Int) {
                answer { reply.failure("The system did not show the picker of the services of the type \"$type\", with the error $errorCode of NsdManager.", "failed", null) }
            }

            override fun onServiceUpdated(serviceInfo: NsdServiceInfo) {
                answer {
                    try {
                        reply.success(picked(serviceInfo, type))
                    } catch (failure: HaylenBridge.Failure) {
                        reply.failure(failure)
                    }
                }
            }

            override fun onServiceLost() {}

            override fun onServiceInfoCallbackUnregistered() {
                answer { reply.failure("The person closed the picker of services.", "cancelled", null) }
            }

            private fun answer(send: () -> Unit) {
                if (!answered) {
                    answered = true
                    send()
                }
            }
        }
        manager.registerServiceInfoCallback(request, context.mainExecutor, callback)
    }

    private companion object {
        const val PICKER_EXTENSION = 22

        // The first IPv4 address is the host, which every network library takes, and the list keeps every address of the service.
        fun picked(service: NsdServiceInfo, type: String): JSONObject {
            val addresses = service.hostAddresses
            val host = addresses.firstOrNull { it is Inet4Address } ?: addresses.firstOrNull()
                ?: throw HaylenBridge.Failure("The service \"${service.serviceName}\" that the person picked names no address.", "unreachable", null)
            val texts = JSONArray()
            for (address in addresses) {
                texts.put(address.hostAddress)
            }
            return JSONObject().put("name", service.serviceName).put("type", type).put("host", host.hostAddress).put("port", service.port).put("addresses", texts)
        }
    }
}
