package com.haylen.plugins.haptics

import android.Manifest
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.HapticFeedbackConstants
import dev.haylen.HaylenBridge
import dev.haylen.HaylenPlugin
import dev.haylen.HaylenPluginContext
import dev.haylen.HaylenRequirements
import org.json.JSONObject
import kotlin.math.max
import kotlin.math.roundToLong

// Native part of the Haptics plugin on Android. The `haylen` library creates it from the `meta-data` of its manifest, and loads it when the app process starts. It vibrates the device through its vibrator, which needs the permission `VIBRATE`, and plays the haptic feedback of the system on the view of the activity, which needs none.
class HapticsPlugin : HaylenPlugin() {
    override fun onLoad(context: HaylenPluginContext) {
        // Answers `haptics.vibrate` with `true` once the vibrator took the vibration, which lasts at least a millisecond.
        context.register("vibrate") { params, reply ->
            context.requirements().require(HaylenRequirements.Requirement.permission(Manifest.permission.VIBRATE))
            val vibrator = context.application().getSystemService(Vibrator::class.java)
            if (vibrator == null || !vibrator.hasVibrator()) {
                throw HaylenBridge.Failure("This device has no vibration motor.", "unsupported", null)
            }

            val milliseconds = max(1L, ((params as JSONObject).getDouble("seconds") * 1000.0).roundToLong())
            vibrator.vibrate(VibrationEffect.createOneShot(milliseconds, VibrationEffect.DEFAULT_AMPLITUDE))
            reply.success(true)
        }

        context.register("impact") { params, reply ->
            val feedback = when (val strength = (params as JSONObject).getString("strength")) {
                "light" -> HapticFeedbackConstants.KEYBOARD_TAP
                "medium" -> HapticFeedbackConstants.VIRTUAL_KEY
                "heavy" -> HapticFeedbackConstants.LONG_PRESS
                else -> throw HaylenBridge.Failure("The strength of an impact is \"light\", \"medium\" or \"heavy\", not \"$strength\".", "invalidStrength", null)
            }
            perform(context, feedback)
            reply.success(true)
        }

        context.register("selection") { _, reply ->
            perform(context, HapticFeedbackConstants.CLOCK_TICK)
            reply.success(true)
        }

        // Android has the feedback of a confirmation and of a rejection from Android 11, and none of a warning.
        context.register("notification") { params, reply ->
            val kind = (params as JSONObject).getString("kind")
            if (kind == "warning") {
                throw HaylenBridge.Failure("Android has no haptic feedback of a warning.", "unsupported", null)
            }
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                throw HaylenBridge.Failure("Android plays the haptic feedback of a success or an error from Android 11.", "unsupported", null)
            }

            val feedback = when (kind) {
                "success" -> HapticFeedbackConstants.CONFIRM
                "error" -> HapticFeedbackConstants.REJECT
                else -> throw HaylenBridge.Failure("The kind of a notification is \"success\", \"warning\" or \"error\", not \"$kind\".", "invalidKind", null)
            }
            perform(context, feedback)
            reply.success(true)
        }
    }

    // The view of the activity plays the feedback through the system, which skips it on a device without a vibration motor or with touch feedback turned off.
    private fun perform(context: HaylenPluginContext, feedback: Int) {
        val activity = context.activity() ?: throw HaylenBridge.Failure("The haptic feedback plays only while the app has an activity.", "unsupported", null)
        if (!activity.window.decorView.performHapticFeedback(feedback)) {
            throw HaylenBridge.Failure("Android played no haptic feedback, as it does on a device without a vibration motor or with touch feedback turned off.", "unsupported", null)
        }
    }
}
