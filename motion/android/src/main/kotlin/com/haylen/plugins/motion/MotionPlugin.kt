package com.haylen.plugins.motion

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import com.haylen.plugins.permissions.Permission
import com.haylen.plugins.permissions.Permissions
import dev.haylen.HaylenActivity
import dev.haylen.HaylenPlugin
import dev.haylen.HaylenPluginContext
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sqrt

// Native part of the Motion plugin on Android: the accelerometer, the gyroscope and the game rotation vector of the sensor manager, which fuses them into an attitude whose z points up. Android asks the person for none of them, and gives an app at most 200 readings per second without the permission `HIGH_SAMPLING_RATE_SENSORS`, which the Lua API never asks beyond. The sensors deliver on the main thread and stop while the activity is paused. Each reading goes to the app as the batched event `reading`, in the axes of the device in its natural orientation with the quarter turns of the display, which the Lua API turns into the axes of the screen.
class MotionPlugin : HaylenPlugin() {
    private lateinit var context: HaylenPluginContext
    private var session = 0
    private var running = emptyList<String>()
    private var periodMicroseconds = 0
    private var paused = false

    private val listener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            send(event)
        }

        override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {}
    }

    override fun onLoad(context: HaylenPluginContext) {
        this.context = context
        Permissions.register(context, MotionPermission())

        // The app holds the watch of a session while its sensors run, and gives it up to stop them, which the end of the app does too.
        context.register("watch") { params, reply ->
            val watched = (params as JSONObject).getInt("session")
            session = watched
            reply.onCancel { endWatch(watched) }
        }

        context.register("start") { params, reply ->
            val start = params as JSONObject
            val requested = names(start.getJSONArray("sensors"))
            val absent = requested.filter { find(it) == null }
            if (absent.isNotEmpty()) {
                reply.failure(describeAbsent(absent), "unsupported", null)
                return@register
            }

            Permissions.require(context, "motion", reply) {
                if (session != start.getInt("session")) {
                    reply.failure("The app stopped the motion sensors before they started.", "cancelled", null)
                    return@require
                }

                stopSensors()
                running = requested
                periodMicroseconds = (1_000_000.0 / start.getDouble("rate")).roundToInt()

                if (!paused) {
                    runSensors()
                }
                reply.success(JSONObject().put("sensors", start.getJSONArray("sensors")))
            }
        }
    }

    override fun onActivityPaused(activity: HaylenActivity) {
        paused = true
        stopSensors()
    }

    override fun onActivityResumed(activity: HaylenActivity) {
        paused = false
        if (session != 0 && running.isNotEmpty()) {
            runSensors()
        }
    }

    // The app gave the watch of a session up, on any thread, so the sensors of that session stop on the main thread.
    private fun endWatch(watched: Int) {
        context.runOnMainThread { stopSession(watched) }
    }

    private fun stopSession(watched: Int) {
        if (session != watched) {
            return
        }
        stopSensors()
        session = 0
        running = emptyList()
    }

    private fun names(list: JSONArray): List<String> = List(list.length()) { index -> list.getString(index) }

    private fun manager(): SensorManager? = context.application().getSystemService(SensorManager::class.java)

    private fun find(name: String): Sensor? = manager()?.getDefaultSensor(sensorType(name))

    private fun runSensors() {
        val sensors = manager() ?: return
        for (name in running) {
            val sensor = sensors.getDefaultSensor(sensorType(name)) ?: continue
            sensors.registerListener(listener, sensor, max(periodMicroseconds, sensor.minDelay))
        }
    }

    private fun stopSensors() {
        manager()?.unregisterListener(listener)
    }

    // Android measures the push that holds the device up in meters per second squared and the rotation in radians per second, as the Lua API reads them, and the rotation vector gives the quaternion of the attitude, whose w it leaves out on some devices.
    private fun send(event: SensorEvent) {
        val reading = JSONObject()
        reading.put("session", session)
        reading.put("turns", quarterTurns())

        val values = event.values
        when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> reading.put("sensor", "accelerometer")
            Sensor.TYPE_GYROSCOPE -> reading.put("sensor", "gyroscope")
            Sensor.TYPE_GAME_ROTATION_VECTOR -> {
                val w = if (values.size > 3) values[3] else sqrt(max(0f, 1f - values[0] * values[0] - values[1] * values[1] - values[2] * values[2]))
                reading.put("sensor", "attitude")
                reading.put("w", w.toDouble())
            }
            else -> return
        }
        reading.put("x", values[0].toDouble())
        reading.put("y", values[1].toDouble())
        reading.put("z", values[2].toDouble())
        context.emit("reading", reading, false, true)
    }

    // The quarter turns counterclockwise of the display that shows the activity from its natural orientation.
    @Suppress("DEPRECATION")
    private fun quarterTurns(): Int {
        val activity = context.activity() ?: return 0
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return activity.windowManager.defaultDisplay.rotation
        }
        val display = activity.display ?: return 0
        return display.rotation
    }

    private fun describeAbsent(absent: List<String>): String {
        val sensors = manager()
        if (sensors == null || SENSORS.all { sensors.getDefaultSensor(it.second) == null }) {
            return NO_SENSORS
        }
        val quoted = absent.map { "\"$it\"" }
        val list = if (quoted.size == 1) quoted[0] else quoted.dropLast(1).joinToString(", ") + " and " + quoted.last()
        return "The device has no motion ${if (quoted.size == 1) "sensor" else "sensors"} $list."
    }

    // The permission `motion`, which Android grants every app, on a device that has a motion sensor.
    private inner class MotionPermission : Permission("motion", "the motion sensors") {
        override fun unsupportedReason(context: Context): String? {
            val sensors = context.getSystemService(SensorManager::class.java)
            val any = sensors != null && SENSORS.any { sensors.getDefaultSensor(it.second) != null }
            return if (any) null else NO_SENSORS
        }
    }

    private companion object {
        const val NO_SENSORS = "This device has no motion sensors."

        val SENSORS = listOf("accelerometer" to Sensor.TYPE_ACCELEROMETER, "gyroscope" to Sensor.TYPE_GYROSCOPE, "attitude" to Sensor.TYPE_GAME_ROTATION_VECTOR)

        fun sensorType(name: String): Int = SENSORS.first { it.first == name }.second
    }
}
