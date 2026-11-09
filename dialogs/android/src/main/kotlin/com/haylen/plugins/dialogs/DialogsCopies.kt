package com.haylen.plugins.dialogs

import android.app.Application
import android.content.ContentResolver
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

// The copies of picked documents and photos, which have no paths on Android, in the folder `dialogs` of the cache folder of the app, which the plugin empties when the process starts, so the folder never grows. Each dialog copies into a numbered folder of its own, and a second file of the same name goes into a numbered folder inside it. Copies and writes run on a thread of their own, since files may be large.
class DialogsCopies(application: Application) {
    private val root = File(application.cacheDir, "dialogs")
    private var nextFolder = 1

    val worker: ExecutorService = Executors.newSingleThreadExecutor { task -> Thread(task, "dialogs").apply { isDaemon = true } }

    // A folder that cannot be emptied keeps its old copies, which the log names, and the new ones go next to them.
    fun clear() {
        worker.execute {
            if (root.exists() && !root.deleteRecursively()) {
                Log.w(TAG, "The copies of picked files in \"$root\" could not be removed.")
            }
        }
    }

    // Called on the main thread when a picker answers.
    fun makeFolder(): File {
        val folder = File(root, nextFolder.toString())
        nextFolder += 1
        return folder
    }

    // Copies the documents into the folder on the thread of the copies, and returns them as the app receives them.
    @Throws(IOException::class)
    fun copy(resolver: ContentResolver, uris: List<Uri>, folder: File): List<Map<String, String>> {
        return uris.map { uri ->
            val name = displayName(resolver, uri)
            var copy = File(folder, name)
            var index = 2
            while (copy.exists()) {
                copy = File(File(folder, index.toString()), name)
                index += 1
            }
            copyFile(resolver, uri, copy)
            mapOf("name" to name, "path" to copy.absolutePath)
        }
    }

    // A name that the provider leaves out, or that holds a separator, still gives a file name.
    fun displayName(resolver: ContentResolver, uri: Uri): String {
        val cursor: Cursor? = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
        val name = cursor?.use { if (it.moveToFirst()) it.getString(0) else null }
        val fallback = uri.lastPathSegment ?: "file"
        return (if (name.isNullOrEmpty()) fallback else name).replace('/', '_')
    }

    @Throws(IOException::class)
    private fun copyFile(resolver: ContentResolver, uri: Uri, copy: File) {
        val parent = copy.parentFile
        if (parent != null && !parent.isDirectory && !parent.mkdirs()) {
            throw IOException("The folder \"$parent\" cannot be created.")
        }
        val input = resolver.openInputStream(uri) ?: throw IOException("The document \"$uri\" cannot be read.")
        input.use { source -> FileOutputStream(copy).use { target -> source.copyTo(target) } }
    }

    companion object {
        const val TAG = "dialogs"
    }
}
