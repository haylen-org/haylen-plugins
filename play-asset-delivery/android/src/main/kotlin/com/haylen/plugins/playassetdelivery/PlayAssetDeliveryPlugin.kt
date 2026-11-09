package com.haylen.plugins.playassetdelivery

import android.app.Activity
import android.os.Bundle
import androidx.activity.result.ActivityResult
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import com.google.android.play.core.assetpacks.AssetPackException
import com.google.android.play.core.assetpacks.AssetPackManager
import com.google.android.play.core.assetpacks.AssetPackManagerFactory
import com.google.android.play.core.assetpacks.AssetPackState
import com.google.android.play.core.assetpacks.AssetPackStates
import com.google.android.play.core.assetpacks.model.AssetPackErrorCode
import com.google.android.play.core.assetpacks.model.AssetPackStatus
import dev.haylen.HaylenActivity
import dev.haylen.HaylenBridge
import dev.haylen.HaylenPlugin
import dev.haylen.HaylenPluginContext
import dev.haylen.HaylenScreen
import org.json.JSONObject

// Native part of the Play Asset Delivery plugin. It fetches the asset packs of Google Play that hold the named packs of the content, reports their progress, and answers each fetch with the folder where Play placed the pack, with `confirm` while Play waits for the person to accept the download, or with no folder when Play does not deliver the pack, such as for an app that Play did not install, so the content server delivers it instead.
class PlayAssetDeliveryPlugin : HaylenPlugin() {
    private lateinit var context: HaylenPluginContext
    private lateinit var manager: AssetPackManager

    // The fetches that wait for each asset pack, which only the main thread touches.
    private val waiting = HashMap<String, MutableList<HaylenBridge.Reply>>()

    // The launcher of the confirmation of Google Play, which every activity registers before it starts, and the screen that shows it.
    private var confirmation: ActivityResultLauncher<IntentSenderRequest>? = null
    private var confirming: HaylenScreen? = null

    override fun onLoad(context: HaylenPluginContext) {
        this.context = context
        manager = AssetPackManagerFactory.getInstance(context.application())
        manager.registerListener { state -> context.runOnMainThread { update(state) } }

        context.register("fetch") { params, reply -> fetch(packOf(params), reply) }
        context.register("state") { params, reply -> state(packOf(params), reply) }
        context.register("cancel") { params, reply -> cancel(packOf(params), reply) }
        context.registerScreen("confirm") { _, screen -> confirm(screen) }
    }

    // A result that Android delivers to an activity that it recreated reaches the screen that showed when the process ended.
    override fun onActivityCreated(activity: HaylenActivity, savedInstanceState: Bundle?) {
        confirmation = activity.activityResultRegistry.register("play-asset-delivery.confirm", activity, ActivityResultContracts.StartIntentSenderForResult(), ::confirmed)
    }

    private fun packOf(params: Any?): String = (params as JSONObject).getString("pack")

    private fun fetch(pack: String, reply: HaylenBridge.Reply) {
        val folder = manager.getPackLocation(pack)?.assetsPath()
        if (folder != null) {
            reply.success(JSONObject().put("folder", folder))
            return
        }

        val replies = waiting.getOrPut(pack) { mutableListOf() }
        replies.add(reply)
        if (replies.size > 1) {
            return
        }

        // A pack that waits already, such as for Wi-Fi, reports no new state, so the answer of the fetch counts as one.
        manager.fetch(listOf(pack))
            .addOnSuccessListener { states -> context.runOnMainThread { fetched(pack, states) } }
            .addOnFailureListener { error -> context.runOnMainThread { finish(pack) { fail(it, error) } } }
    }

    private fun fetched(pack: String, states: AssetPackStates) {
        val state = states.packStates()[pack] ?: return
        update(state)
    }

    private fun state(pack: String, reply: HaylenBridge.Reply) {
        manager.getPackStates(listOf(pack))
            .addOnSuccessListener { states -> reply.success(describe(pack, states.packStates()[pack])) }
            .addOnFailureListener { error -> fail(reply, error) }
    }

    private fun cancel(pack: String, reply: HaylenBridge.Reply) {
        manager.cancel(listOf(pack))
        reply.success(null)
    }

    private fun update(state: AssetPackState) {
        val pack = state.name()
        context.emit("progress", describe(pack, state))
        when (state.status()) {
            AssetPackStatus.COMPLETED -> finish(pack) { it.success(JSONObject().put("folder", manager.getPackLocation(pack)?.assetsPath() ?: JSONObject.NULL)) }
            AssetPackStatus.FAILED -> finish(pack) { fail(it, state.errorCode(), null) }
            AssetPackStatus.CANCELED -> finish(pack) { it.failure("The download of the asset pack \"$pack\" was cancelled.", "cancelled", null) }
            AssetPackStatus.WAITING_FOR_WIFI, AssetPackStatus.REQUIRES_USER_CONFIRMATION -> finish(pack) { it.success(JSONObject().put("confirm", true)) }
        }
    }

    private fun finish(pack: String, answer: (HaylenBridge.Reply) -> Unit) {
        waiting.remove(pack)?.forEach(answer)
    }

    private fun fail(reply: HaylenBridge.Reply, error: Exception) {
        val code = (error as? AssetPackException)?.errorCode ?: AssetPackErrorCode.INTERNAL_ERROR
        fail(reply, code, error.message)
    }

    // Packs that Google Play does not deliver to this app answer with no folder, so the next source of packs or the content server delivers them.
    private fun fail(reply: HaylenBridge.Reply, code: Int, message: String?) {
        when (code) {
            AssetPackErrorCode.APP_UNAVAILABLE, AssetPackErrorCode.PACK_UNAVAILABLE, AssetPackErrorCode.API_NOT_AVAILABLE, AssetPackErrorCode.APP_NOT_OWNED, AssetPackErrorCode.UNRECOGNIZED_INSTALLATION -> reply.success(JSONObject().put("folder", JSONObject.NULL))
            AssetPackErrorCode.NETWORK_ERROR -> reply.failure("Google Play could not download the asset pack, since the device is offline.", "networkError", null)
            AssetPackErrorCode.INSUFFICIENT_STORAGE -> reply.failure("The device has no room for the asset pack.", "insufficientStorage", null)
            else -> reply.failure("Google Play failed to deliver the asset pack with the error $code. ${message ?: ""}".trim(), "fetchFailed", JSONObject().put("errorCode", code))
        }
    }

    private fun confirm(screen: HaylenScreen) {
        val launcher = confirmation ?: return screen.fail("The app has no activity.", "notActive", null)
        if (!manager.showConfirmationDialog(launcher)) {
            screen.fail("No asset pack waits for the confirmation of the person.", "notRequired", null)
            return
        }
        confirming = screen
    }

    private fun confirmed(result: ActivityResult) {
        val screen = confirming ?: context.restoredScreen() ?: return
        confirming = null
        screen.finish(JSONObject().put("confirmed", result.resultCode == Activity.RESULT_OK))
    }

    private fun describe(pack: String, state: AssetPackState?): JSONObject {
        if (state == null) {
            return JSONObject().put("pack", pack).put("status", "unknown").put("receivedBytes", 0).put("totalBytes", 0)
        }
        return JSONObject()
            .put("pack", pack)
            .put("status", statusName(state.status()))
            .put("receivedBytes", state.bytesDownloaded())
            .put("totalBytes", state.totalBytesToDownload())
    }

    private fun statusName(status: Int): String = when (status) {
        AssetPackStatus.UNKNOWN -> "unknown"
        AssetPackStatus.PENDING -> "pending"
        AssetPackStatus.DOWNLOADING -> "downloading"
        AssetPackStatus.TRANSFERRING -> "transferring"
        AssetPackStatus.COMPLETED -> "completed"
        AssetPackStatus.FAILED -> "failed"
        AssetPackStatus.CANCELED -> "cancelled"
        AssetPackStatus.WAITING_FOR_WIFI -> "waitingForWifi"
        AssetPackStatus.NOT_INSTALLED -> "notInstalled"
        AssetPackStatus.REQUIRES_USER_CONFIRMATION -> "requiresUserConfirmation"
        else -> throw IllegalArgumentException("Google Play reported the asset pack status $status, which the library of the plugin does not name.")
    }
}
