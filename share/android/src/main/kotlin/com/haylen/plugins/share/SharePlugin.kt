package com.haylen.plugins.share

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import dev.haylen.HaylenActivity
import dev.haylen.HaylenBridge
import dev.haylen.HaylenPlugin
import dev.haylen.HaylenPluginContext
import java.io.File
import org.json.JSONArray
import org.json.JSONObject

// Native part of the Share plugin on Android: `ACTION_SEND` or `ACTION_SEND_MULTIPLE` in the chooser of the system, with the files of the share behind the `ShareFileProvider` of the plugin. The chooser tells the app that the person picked through a broadcast of the plugin, and its result comes once the person leaves it, so `shared` tells whether the person picked an app. Android tells nothing of what the picked app did with the share.
class SharePlugin : HaylenPlugin() {
    private lateinit var context: HaylenPluginContext
    private var chooser: ActivityResultLauncher<Intent>? = null
    private var pending: HaylenBridge.Reply? = null
    private var chosen: ComponentName? = null

    override fun onLoad(context: HaylenPluginContext) {
        this.context = context
        val application = context.application()

        // The broadcast that the chooser sends once the person picks an app, which only the app itself may send.
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(receiverContext: Context, intent: Intent) {
                chosen = chosenComponent(intent)
            }
        }
        ContextCompat.registerReceiver(application, receiver, IntentFilter(ACTION_CHOSEN), ContextCompat.RECEIVER_NOT_EXPORTED)

        context.register("share") { params, reply ->
            val launcher = chooser ?: throw HaylenBridge.Failure("The app has no activity yet.", "noWindow", null)
            if (pending != null) {
                throw HaylenBridge.Failure("The share sheet already shows.", "busy", null)
            }
            val json = params as JSONObject
            val send = sendIntent(json)
            val picked = Intent(ACTION_CHOSEN).setPackage(application.packageName)
            val sender = PendingIntent.getBroadcast(application, 0, picked, PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            chosen = null
            pending = reply
            launcher.launch(Intent.createChooser(send, text(json, "title"), sender.intentSender))
        }
    }

    // The activity takes the launcher before it starts, under a key of the plugin, so a result that Android delivers to a new activity finds it.
    override fun onActivityCreated(activity: HaylenActivity, savedInstanceState: Bundle?) {
        chooser = activity.activityResultRegistry.register(RESULT_KEY, activity, ActivityResultContracts.StartActivityForResult()) {
            val reply = pending
            pending = null
            if (reply == null) {
                Log.i(TAG, "The chooser closed after the app started again, and no call waits for it.")
                return@register
            }
            val result = JSONObject().put("shared", chosen != null)
            chosen?.let { result.put("target", it.packageName) }
            reply.success(result)
        }
    }

    override fun onActivityDestroyed(activity: HaylenActivity) {
        chooser = null
    }

    private fun sendIntent(params: JSONObject): Intent {
        val files = writeFiles(params.optJSONArray("files") ?: JSONArray())
        val texts = listOfNotNull(text(params, "text"), text(params, "url"))
        val send = Intent(if (files.size > 1) Intent.ACTION_SEND_MULTIPLE else Intent.ACTION_SEND)
        send.type = mediaType(files)

        if (texts.isNotEmpty()) {
            send.putExtra(Intent.EXTRA_TEXT, texts.joinToString("\n"))
        }
        text(params, "title")?.let { send.putExtra(Intent.EXTRA_SUBJECT, it) }

        if (files.size == 1) {
            send.putExtra(Intent.EXTRA_STREAM, files[0].uri)
        } else if (files.size > 1) {
            send.putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(files.map { it.uri }))
        }

        // The clip data grants the picked app the right to read the files, which the chooser hands on.
        if (files.isNotEmpty()) {
            val clip = ClipData.newRawUri(null, files[0].uri)
            for (file in files.drop(1)) {
                clip.addItem(ClipData.Item(file.uri))
            }
            send.clipData = clip
            send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        return send
    }

    private fun text(params: JSONObject, key: String): String? {
        return if (params.has(key) && !params.isNull(key)) params.getString(key) else null
    }

    private class SharedFile(val uri: Uri, val type: String)

    // The files of the last share leave first, since the app that the person picked may still read them after the chooser closed.
    private fun writeFiles(files: JSONArray): List<SharedFile> {
        val application = context.application()
        val folder = File(application.cacheDir, "share")
        folder.deleteRecursively()
        if (files.length() == 0) {
            return emptyList()
        }

        folder.mkdirs()
        val authority = application.packageName + ".share"
        val written = ArrayList<SharedFile>()
        for (index in 0 until files.length()) {
            val file = files.getJSONObject(index)
            val destination = File(folder, file.getString("name"))
            destination.writeBytes(file.get("bytes") as ByteArray)
            written.add(SharedFile(FileProvider.getUriForFile(application, authority, destination), file.getString("type")))
        }
        return written
    }

    // Text alone is `text/plain`, files of one type keep it, files of one family such as images take `image/*`, and other files `*/*`.
    private fun mediaType(files: List<SharedFile>): String {
        if (files.isEmpty()) {
            return "text/plain"
        }
        val types = files.map { it.type }.toSet()
        if (types.size == 1) {
            return types.first()
        }
        val families = types.map { it.substringBefore('/') }.toSet()
        return if (families.size == 1) families.first() + "/*" else "*/*"
    }

    private fun chosenComponent(intent: Intent): ComponentName? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_CHOSEN_COMPONENT, ComponentName::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_CHOSEN_COMPONENT)
        }
    }

    companion object {
        private const val ACTION_CHOSEN = "com.haylen.plugins.share.CHOSEN"
        private const val RESULT_KEY = "share.share"
        private const val TAG = "share"
    }
}
