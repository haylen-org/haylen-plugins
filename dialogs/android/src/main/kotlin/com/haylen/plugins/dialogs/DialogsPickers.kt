package com.haylen.plugins.dialogs

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import android.webkit.MimeTypeMap
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import dev.haylen.HaylenActivity
import dev.haylen.HaylenBridge
import dev.haylen.HaylenPluginContext
import java.io.IOException
import java.util.Locale
import org.json.JSONArray
import org.json.JSONObject

// The pickers of the plugin, one at a time: the document picker and the document creator of the Storage Access Framework, and the photo picker of the system, which needs no permission. The pickers belong to other apps, whose activities pause the app, so a cancel or a timeout of the app takes effect once the picker closed, and its answer goes nowhere. A picker that answers after its activity or its process ended finds no call waiting, since the stable keys of the Activity Result API deliver its answer to the next activity, and the answer is logged and dropped. Everything here runs on the main thread, and copies and writes run on the thread of the copies.
class DialogsPickers(private val context: HaylenPluginContext, private val copies: DialogsCopies) {
    // Creates a document of the MIME type that each save asks for, which `CreateDocument` fixes when it is registered. The input is the suggested name and the MIME type.
    private class CreateFile : ActivityResultContract<Array<String>, Uri?>() {
        override fun createIntent(context: Context, input: Array<String>): Intent {
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
            intent.addCategory(Intent.CATEGORY_OPENABLE)
            intent.type = input[1]
            intent.putExtra(Intent.EXTRA_TITLE, input[0])
            return intent
        }

        override fun parseResult(resultCode: Int, intent: Intent?): Uri? {
            return if (resultCode == Activity.RESULT_OK) intent?.data else null
        }
    }

    // The picker that shows: the reply of its call and the bytes of a save.
    private class Picking(val reply: HaylenBridge.Reply, val bytes: ByteArray?)

    private var openFile: ActivityResultLauncher<Array<String>>? = null
    private var openFiles: ActivityResultLauncher<Array<String>>? = null
    private var createFile: ActivityResultLauncher<Array<String>>? = null
    private var pickPhoto: ActivityResultLauncher<PickVisualMediaRequest>? = null
    private var pickPhotos: ActivityResultLauncher<PickVisualMediaRequest>? = null
    private var picking: Picking? = null

    // Called when each activity is created, before it starts, as the Activity Result API requires.
    fun register(owner: HaylenActivity) {
        val registry = owner.activityResultRegistry
        openFile = registry.register("dialogs.openFile", owner, ActivityResultContracts.OpenDocument()) { uri -> opened("The document picker", uri?.let { listOf(it) }) }
        openFiles = registry.register("dialogs.openFiles", owner, ActivityResultContracts.OpenMultipleDocuments()) { uris -> opened("The document picker", uris.ifEmpty { null }) }
        createFile = registry.register("dialogs.saveFile", owner, CreateFile()) { uri -> created(uri) }
        pickPhoto = registry.register("dialogs.openPhoto", owner, ActivityResultContracts.PickVisualMedia()) { uri -> opened("The photo picker", uri?.let { listOf(it) }) }
        pickPhotos = registry.register("dialogs.openPhotos", owner, ActivityResultContracts.PickMultipleVisualMedia()) { uris -> opened("The photo picker", uris.ifEmpty { null }) }
    }

    fun openFiles(request: JSONObject, reply: HaylenBridge.Reply) {
        val launcher = if (request.optBoolean("multiple")) openFiles else openFile
        val mimeTypes = types(extensionsOf(request))
        pick(reply, null) { launcher?.launch(mimeTypes) }
    }

    fun saveFile(request: JSONObject, reply: HaylenBridge.Reply) {
        val bytes = request.get("data") as ByteArray
        val nameAndType = arrayOf(request.getString("name"), type(extensionsOf(request)))
        pick(reply, bytes) { createFile?.launch(nameAndType) }
    }

    fun openPhotos(request: JSONObject, reply: HaylenBridge.Reply) {
        val images = PickVisualMediaRequest.Builder().setMediaType(ActivityResultContracts.PickVisualMedia.ImageOnly).build()
        val launcher = if (request.optBoolean("multiple")) pickPhotos else pickPhoto
        pick(reply, null) { launcher?.launch(images) }
    }

    // A device without an app that picks documents, as Android TV devices often are, fails the pickers with the code `unsupported`.
    private fun pick(reply: HaylenBridge.Reply, bytes: ByteArray?, launch: () -> Unit) {
        if (context.activity() == null) {
            reply.failure("The app has no activity to show the picker over.", "failed", null)
            return
        }
        if (picking != null) {
            reply.failure("Another picker shows. Ask for the next one once it answered.", "failed", null)
            return
        }

        val current = Picking(reply, bytes)
        picking = current
        reply.onCancel {
            if (picking === current) {
                picking = null
            }
        }
        try {
            launch()
        } catch (error: ActivityNotFoundException) {
            picking = null
            reply.failure("This device has no app that picks documents or photos, as Android TV devices often lack one.", "unsupported", null)
        }
    }

    private fun opened(picker: String, uris: List<Uri>?) {
        val current = take(picker) ?: return
        if (uris == null) {
            current.reply.success(null)
            return
        }
        val resolver = context.application().contentResolver
        val folder = copies.makeFolder()
        copies.worker.execute {
            try {
                current.reply.success(copies.copy(resolver, uris, folder))
            } catch (error: IOException) {
                current.reply.failure("The picked files could not be copied for the app: " + (error.message ?: error.toString()), "failed", null)
            } catch (error: SecurityException) {
                current.reply.failure("The picked files could not be read: " + (error.message ?: error.toString()), "failed", null)
            }
        }
    }

    // The bytes are written into the document, and the answer names it without a path, since documents have none. The document creator never replaces a file, and it adds a number to a name that is taken.
    private fun created(uri: Uri?) {
        val current = take("The document creator") ?: return
        if (uri == null) {
            current.reply.success(null)
            return
        }
        val resolver = context.application().contentResolver
        val bytes = current.bytes ?: ByteArray(0)
        copies.worker.execute {
            try {
                val output = resolver.openOutputStream(uri, "wt") ?: throw IOException("The document \"$uri\" cannot be written.")
                output.use { it.write(bytes) }
                current.reply.success(JSONObject().put("name", copies.displayName(resolver, uri)))
            } catch (error: IOException) {
                current.reply.failure("The file could not be saved: " + (error.message ?: error.toString()), "failed", null)
            } catch (error: SecurityException) {
                current.reply.failure("The file could not be saved: " + (error.message ?: error.toString()), "failed", null)
            }
        }
    }

    private fun take(picker: String): Picking? {
        val current = picking
        picking = null
        if (current == null) {
            Log.i(DialogsCopies.TAG, "$picker answered after the app that asked for it stopped, so the answer is dropped.")
        }
        return current
    }

    private fun extensionsOf(request: JSONObject): List<String> {
        val filters = request.optJSONArray("filters") ?: JSONArray()
        val extensions = ArrayList<String>()
        for (index in 0 until filters.length()) {
            val list = filters.getJSONObject(index).getJSONArray("extensions")
            for (position in 0 until list.length()) {
                extensions.add(list.getString(position).lowercase(Locale.ROOT))
            }
        }
        return extensions
    }

    // The MIME types of the extensions, or every type when an extension has none that Android knows, since the picker would hide those files otherwise.
    private fun types(extensions: List<String>): Array<String> {
        val types = LinkedHashSet<String>()
        for (extension in extensions) {
            val type = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: return arrayOf(ANY_TYPE)
            types.add(type)
        }
        return if (types.isEmpty()) arrayOf(ANY_TYPE) else types.toTypedArray()
    }

    // A document takes one MIME type: the one of the first extension that Android knows, or plain bytes.
    private fun type(extensions: List<String>): String {
        return extensions.firstNotNullOfOrNull { MimeTypeMap.getSingleton().getMimeTypeFromExtension(it) } ?: BYTES_TYPE
    }

    companion object {
        private const val ANY_TYPE = "*/*"
        private const val BYTES_TYPE = "application/octet-stream"
    }
}
