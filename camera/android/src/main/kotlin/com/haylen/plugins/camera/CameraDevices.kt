package com.haylen.plugins.camera

import android.app.Activity
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import android.util.Size
import android.view.Surface
import dev.haylen.HaylenBridge
import org.json.JSONArray
import org.json.JSONObject

// The cameras that Camera2 lists, the one that a start asks for by its id, by the way it faces, or the first camera at the back, and how its frames turn so the picture stays upright on the screen.
object CameraDevices {
    // The quarter turns from the frames of the sensor to the screen at the start, and whether the picture shows a mirror image, as the front camera does in the camera app of the system.
    class Rotation(val degrees: Int, val mirrored: Boolean) {
        fun width(size: Size): Int = if (degrees % 180 == 0) size.width else size.height

        fun height(size: Size): Int = if (degrees % 180 == 0) size.height else size.width
    }

    fun list(cameras: CameraManager): JSONArray {
        val list = JSONArray()
        for (id in cameras.cameraIdList) {
            list.put(describe(cameras, id))
        }
        return list
    }

    // Camera2 gives cameras no names, so the name tells the way the camera faces and its id.
    fun describe(cameras: CameraManager, id: String): JSONObject {
        val facing = facing(cameras, id)
        val name = facing.replaceFirstChar { it.uppercase() } + " camera " + id
        return JSONObject().put("id", id).put("name", name).put("facing", facing)
    }

    fun find(cameras: CameraManager, id: String?, facing: String?): String {
        val ids = cameras.cameraIdList
        if (id != null) {
            if (id !in ids) {
                throw HaylenBridge.Failure("This device has no camera with the id \"$id\". The function \"camera.cameras\" lists the cameras.", "noCamera", null)
            }
            return id
        }
        if (facing != null) {
            return ids.firstOrNull { facing(cameras, it) == facing } ?: throw HaylenBridge.Failure("This device has no camera that faces \"$facing\".", "noCamera", null)
        }
        return ids.firstOrNull { facing(cameras, it) == "back" } ?: ids.firstOrNull() ?: throw HaylenBridge.Failure("This device has no camera.", "noCamera", null)
    }

    // The size of the frames of the camera whose width and height are the closest to the ones the app asked for.
    fun closestSize(cameras: CameraManager, id: String, width: Int, height: Int): Size {
        val formats = cameras.getCameraCharacteristics(id).get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
        val sizes = formats?.getOutputSizes(ImageFormat.YUV_420_888)
        if (sizes.isNullOrEmpty()) {
            throw HaylenBridge.Failure("The camera \"$id\" offers no frames that the plugin reads.", "cameraFailed", null)
        }
        return sizes.minBy { Math.abs(it.width - width) + Math.abs(it.height - height) }
    }

    // The sensor of a camera sits at a quarter turn of its own, which the rotation of the screen at the start adds to, the other way round for the front camera.
    fun rotation(cameras: CameraManager, id: String, activity: Activity?): Rotation {
        val characteristics = cameras.getCameraCharacteristics(id)
        val sensor = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
        val front = characteristics.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_FRONT
        val screen = screenDegrees(activity)
        val degrees = if (front) (sensor + screen) % 360 else (sensor - screen + 360) % 360
        return Rotation(degrees, front)
    }

    private fun screenDegrees(activity: Activity?): Int {
        if (activity == null) {
            return 0
        }
        val rotation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display?.rotation ?: Surface.ROTATION_0
        } else {
            @Suppress("DEPRECATION") activity.windowManager.defaultDisplay.rotation
        }
        return when (rotation) {
            Surface.ROTATION_90 -> 90
            Surface.ROTATION_180 -> 180
            Surface.ROTATION_270 -> 270
            else -> 0
        }
    }

    private fun facing(cameras: CameraManager, id: String): String {
        return when (cameras.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING)) {
            CameraCharacteristics.LENS_FACING_FRONT -> "front"
            CameraCharacteristics.LENS_FACING_BACK -> "back"
            else -> "external"
        }
    }
}
