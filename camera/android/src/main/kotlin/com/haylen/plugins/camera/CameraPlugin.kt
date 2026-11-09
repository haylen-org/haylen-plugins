package com.haylen.plugins.camera

import android.Manifest
import android.content.pm.PackageManager
import android.hardware.camera2.CameraManager
import android.os.Handler
import android.os.Looper
import com.haylen.plugins.permissions.Permission
import com.haylen.plugins.permissions.Permissions
import dev.haylen.HaylenBridge
import dev.haylen.HaylenPlugin
import dev.haylen.HaylenPluginContext
import dev.haylen.HaylenVideoStream
import org.json.JSONObject

// Native part of the Camera plugin on Android: the cameras of Camera2 into the video stream `camera`, photos as JPEG bytes and the permission `camera`. The `haylen` library creates it from the `meta-data` of its manifest, and loads it when the app process starts.
class CameraPlugin : HaylenPlugin() {
    private lateinit var context: HaylenPluginContext
    // The handler of `takePhoto` reads the capture on a thread of the background.
    @Volatile
    private var capture: CameraCapture? = null
    // Counts the starts, stops and resets, so a start that waits for the permission or for the captures before it to close learns that a later call took its place.
    private var requests = 0
    // A capture opens only once the captures before it closed, so the start that waits for them runs once the last one did.
    private val mainThread = Handler(Looper.getMainLooper())
    private var closingCaptures = 0
    private var waitingStart: (() -> Unit)? = null

    override fun onLoad(context: HaylenPluginContext) {
        this.context = context
        Permissions.register(context, Permission("camera", "the camera", Manifest.permission.CAMERA))

        // Every app that loads the Lua API sends `reset`, so a capture that an earlier app of the process left running stops.
        context.register("reset") { _, reply ->
            requests += 1
            stopCapture()
            reply.success(null)
        }

        context.register("cameras") { _, reply ->
            val cameras = cameraManager()
            Permissions.require(context, "camera", reply) { reply.success(CameraDevices.list(cameras)) }
        }

        context.register("start") { params, reply ->
            val options = params as JSONObject
            val cameras = cameraManager()
            requests += 1
            val request = requests
            Permissions.require(context, "camera", reply) { startCurrent(request, cameras, options, reply) }
        }

        context.register("stop") { _, reply ->
            requests += 1
            stopCapture()
            reply.success(null)
        }

        context.register("takePhoto", { _, reply ->
            val running = capture ?: throw HaylenBridge.Failure("The camera is off. Call \"camera.start\" first.", "cameraOff", null)
            val photo = running.photo() ?: throw HaylenBridge.Failure("The camera has no frame yet.", "noFrame", null)
            reply.success(JSONObject().put("jpeg", photo.jpeg).put("width", photo.width).put("height", photo.height))
        }, HaylenBridge.Threading.BACKGROUND)
    }

    // A device without a camera, such as most TVs, answers `unsupported` before it asks for the permission.
    private fun cameraManager(): CameraManager {
        val application = context.application()
        if (!application.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)) {
            throw HaylenBridge.Failure("This device has no camera.", "unsupported", null)
        }
        return application.getSystemService(CameraManager::class.java)
    }

    private fun startCurrent(request: Int, cameras: CameraManager, options: JSONObject, reply: HaylenBridge.Reply) {
        if (request != requests) {
            reply.failure(kReplaced, "cancelled", null)
            return
        }

        stopCapture()
        if (closingCaptures > 0) {
            // The start that waited before this one runs now and fails, since this one took its place.
            waitingStart?.invoke()
            waitingStart = { startCurrent(request, cameras, options, reply) }
            return
        }

        start(cameras, options, reply)
    }

    private fun start(cameras: CameraManager, options: JSONObject, reply: HaylenBridge.Reply) {
        val id = if (options.isNull("camera")) null else options.getString("camera")
        val facing = if (options.isNull("facing")) null else options.getString("facing")
        val camera = CameraDevices.find(cameras, id, facing)
        val stream = context.openVideoStream("camera", 0, 0, HaylenVideoStream.Format.RGBA8)
        val rotation = CameraDevices.rotation(cameras, camera, context.activity())
        val size = CameraDevices.closestSize(cameras, camera, options.getInt("width"), options.getInt("height"))

        capture = CameraCapture(context.application(), camera, size, rotation, stream, { failure ->
            if (failure == null) {
                val started = CameraDevices.describe(cameras, camera)
                reply.success(started.put("width", rotation.width(size)).put("height", rotation.height(size)))
            } else {
                reply.failure(failure)
            }
        }, { message ->
            context.emit("stopped", JSONObject().put("message", message).put("code", "cameraFailed"))
        })
    }

    private fun stopCapture() {
        val running = capture ?: return
        capture = null
        closingCaptures += 1
        running.stop { mainThread.post { captureClosed() } }
    }

    private fun captureClosed() {
        closingCaptures -= 1
        if (closingCaptures > 0) {
            return
        }

        val next = waitingStart
        waitingStart = null
        next?.invoke()
    }

    companion object {
        const val kReplaced = "The camera stopped or started again before this start ended."
    }
}
