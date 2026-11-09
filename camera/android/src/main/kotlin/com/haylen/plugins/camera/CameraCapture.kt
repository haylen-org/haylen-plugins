package com.haylen.plugins.camera

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.params.OutputConfiguration
import android.hardware.camera2.params.SessionConfiguration
import android.media.Image
import android.media.ImageReader
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.Size
import dev.haylen.HaylenBridge
import dev.haylen.HaylenVideoStream
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

// The capture of one camera through Camera2, whose YUV frames arrive on a thread of their own, which turns them into upright RGBA pixels, pushes them into the stream and keeps the newest one for a photo. It calls `started` once, with nothing once the capture runs or with the failure of the start, such as a stop that came first, and `stopped` with the reason when the camera goes away while it runs, such as when another app takes it. A stop calls back once the system released the camera, since many devices keep one camera open at a time and refuse the next one until then.
@SuppressLint("MissingPermission")
class CameraCapture(context: Context, private val id: String, private val size: Size, private val rotation: CameraDevices.Rotation, private val stream: HaylenVideoStream, private val started: (HaylenBridge.Failure?) -> Unit, private val stopped: (String) -> Unit) {
    class Photo(val jpeg: ByteArray, val width: Int, val height: Int)

    private val thread = HandlerThread("camera-capture").apply { start() }
    private val handler = Handler(thread.looper)
    private val reader = ImageReader.newInstance(size.width, size.height, ImageFormat.YUV_420_888, 2)
    private val width = rotation.width(size)
    private val height = rotation.height(size)
    private val pixels = ByteArray(width * height * 4)
    private val newest = ByteArray(width * height * 4)
    private var planes = arrayOf(ByteArray(0), ByteArray(0), ByteArray(0))
    private var hasFrame = false
    private var running = false
    private var answered = false
    // A stop that comes while Camera2 still opens the camera keeps the thread until the camera opens or fails, so the camera closes on it and the system releases it.
    private var stopping = false
    private var released = false
    private var closed: (() -> Unit)? = null
    private var device: CameraDevice? = null
    private val opened = System.nanoTime()

    init {
        reader.setOnImageAvailableListener({ source -> receive(source) }, handler)
        context.getSystemService(CameraManager::class.java).openCamera(id, Opening(), handler)
    }

    // Closes the camera, even one that still opens, and calls `then` on the thread of the capture once the system released it. The stop runs before the frames that wait for the thread, which a slow device piles up, so the system releases the camera at once.
    fun stop(then: () -> Unit) {
        handler.postAtFrontOfQueue {
            stopping = true
            closed = then
            running = false
            answer(HaylenBridge.Failure(CameraPlugin.kReplaced, "cancelled", null))
            if (released) {
                release(then)
                return@postAtFrontOfQueue
            }

            val current = device
            device = null
            current?.close()
        }
    }

    // Takes the newest frame, which frees the buffer of the reader, and converts it while the capture is not stopping.
    private fun receive(source: ImageReader) {
        val image = source.acquireLatestImage() ?: return
        image.use {
            if (!stopping) {
                convert(it)
            }
        }
    }

    private fun release(then: () -> Unit) {
        reader.close()
        thread.quitSafely()
        then()
    }

    // Encodes the newest frame as a JPEG file, or returns null before the first frame.
    fun photo(): Photo? {
        val copy = synchronized(newest) { if (hasFrame) newest.copyOf() else null } ?: return null
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        bitmap.copyPixelsFromBuffer(ByteBuffer.wrap(copy))
        val jpeg = ByteArrayOutputStream()
        val encoded = bitmap.compress(Bitmap.CompressFormat.JPEG, 85, jpeg)
        bitmap.recycle()

        if (!encoded) {
            throw HaylenBridge.Failure("The frame of the camera did not encode as a JPEG file.", "cameraFailed", null)
        }
        return Photo(jpeg.toByteArray(), width, height)
    }

    private inner class Opening : CameraDevice.StateCallback() {
        override fun onOpened(camera: CameraDevice) {
            if (stopping) {
                camera.close()
                return
            }

            device = camera
            val configured = Configuring(camera)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val outputs = listOf(OutputConfiguration(reader.surface))
                val session = SessionConfiguration(SessionConfiguration.SESSION_REGULAR, outputs, { handler.post(it) }, configured)
                camera.createCaptureSession(session)
            } else {
                @Suppress("DEPRECATION")
                camera.createCaptureSession(listOf(reader.surface), configured, handler)
            }
        }

        override fun onDisconnected(camera: CameraDevice) {
            closed(camera, "The camera \"$id\" went away, such as to another app.")
        }

        override fun onError(camera: CameraDevice, error: Int) {
            closed(camera, "The camera \"$id\" failed with the error $error of Camera2.")
        }

        override fun onClosed(camera: CameraDevice) {
            released = true
            closed?.let { release(it) }
        }

        private fun closed(camera: CameraDevice, reason: String) {
            camera.close()
            if (stopping) {
                return
            }
            end(reason)
        }
    }

    private inner class Configuring(private val camera: CameraDevice) : CameraCaptureSession.StateCallback() {
        override fun onConfigured(session: CameraCaptureSession) {
            if (stopping) {
                return
            }

            val request = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
            request.addTarget(reader.surface)
            session.setRepeatingRequest(request.build(), null, handler)
            running = true
            answer(null)
        }

        override fun onConfigureFailed(session: CameraCaptureSession) {
            camera.close()
            if (stopping) {
                return
            }
            end("The camera \"$id\" refused the capture session.")
        }
    }

    // A failure before the capture ran fails the start, and one after it stops the capture.
    private fun end(reason: String) {
        device = null
        if (running) {
            running = false
            Log.w("camera", reason)
            stopped(reason)
            return
        }
        answer(HaylenBridge.Failure(reason, "cameraFailed", null))
    }

    private fun answer(failure: HaylenBridge.Failure?) {
        if (answered) {
            return
        }
        answered = true
        started(failure)
    }

    // Turns the planes of a YUV frame into RGBA pixels with the coefficients of BT.601. Each pixel of the turned picture reads the pixel of the sensor that the rotation and the mirror bring to it, so the walk over the sensor starts at one corner and steps by the same amounts for every column and every row.
    private fun convert(image: Image) {
        val (luma, blue, red) = image.planes
        readPlane(0, luma.buffer)
        readPlane(1, blue.buffer)
        readPlane(2, red.buffer)

        val lastX = size.width - 1
        val lastY = size.height - 1
        var (startX, startY, columnX, columnY, rowX, rowY) = when (rotation.degrees) {
            90 -> Walk(0, lastY, 0, -1, 1, 0)
            180 -> Walk(lastX, lastY, -1, 0, 0, -1)
            270 -> Walk(lastX, 0, 0, 1, -1, 0)
            else -> Walk(0, 0, 1, 0, 0, 1)
        }
        if (rotation.mirrored) {
            startX += columnX * (width - 1)
            startY += columnY * (width - 1)
            columnX = -columnX
            columnY = -columnY
        }

        val lumaBytes = planes[0]
        val blueBytes = planes[1]
        val redBytes = planes[2]
        var target = 0
        for (row in 0 until height) {
            var x = startX + rowX * row
            var y = startY + rowY * row
            for (column in 0 until width) {
                val brightness = (lumaBytes[y * luma.rowStride + x * luma.pixelStride].toInt() and 0xFF) - 16
                val chroma = (y / 2) * blue.rowStride + (x / 2) * blue.pixelStride
                val u = (blueBytes[chroma].toInt() and 0xFF) - 128
                val v = (redBytes[(y / 2) * red.rowStride + (x / 2) * red.pixelStride].toInt() and 0xFF) - 128
                val scaled = 1.164f * brightness
                pixels[target] = clamp(scaled + 1.596f * v)
                pixels[target + 1] = clamp(scaled - 0.392f * u - 0.813f * v)
                pixels[target + 2] = clamp(scaled + 2.017f * u)
                pixels[target + 3] = 255.toByte()
                target += 4
                x += columnX
                y += columnY
            }
        }

        synchronized(newest) {
            pixels.copyInto(newest)
            hasFrame = true
        }
        stream.push(ByteBuffer.wrap(pixels), width, height, width * 4, (System.nanoTime() - opened) / 1e9)
    }

    private fun readPlane(index: Int, buffer: ByteBuffer) {
        if (planes[index].size < buffer.remaining()) {
            planes[index] = ByteArray(buffer.remaining())
        }
        buffer.get(planes[index], 0, buffer.remaining())
    }

    private fun clamp(value: Float): Byte = value.toInt().coerceIn(0, 255).toByte()

    private data class Walk(val startX: Int, val startY: Int, val columnX: Int, val columnY: Int, val rowX: Int, val rowY: Int)
}
