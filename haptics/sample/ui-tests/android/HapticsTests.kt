package com.haylen.uitests

import android.os.Build
import org.junit.Test

// Every feedback of the sample answers, which is all that the vibrator tells an app: a device plays each one but the warning, which Android has no feedback of, and the success and the error, which Android plays from Android 11, and a vibration of 0 seconds raises before it reaches the platform.
class HapticsTests : HaylenUiTestCase() {
    companion object {
        val PLAYED = listOf(
            "Vibrate for 80 ms" to "haptics.vibrate(0.08)",
            "Vibrate for 1 second" to "haptics.vibrate(1)",
            "Light impact" to "haptics.impact('light')",
            "Medium impact" to "haptics.impact('medium')",
            "Heavy impact" to "haptics.impact('heavy')",
            "Selection tick" to "haptics.selection()",
        )
        val NOTIFICATIONS = listOf(
            "Success" to "haptics.notification('success')",
            "Error" to "haptics.notification('error')",
        )
        const val BEFORE_ANDROID_11 = "Android plays the haptic feedback of a success or an error from Android 11."
    }

    @Test
    fun everyFeedbackAnswers() {
        for ((button, code) in PLAYED) {
            tap(button)
            waitFor("The call \"$code\" played.")
        }
        for ((button, code) in NOTIFICATIONS) {
            tap(button)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                waitFor("The call \"$code\" played.")
            } else {
                waitFor("The call \"$code\" failed with \"unsupported\": $BEFORE_ANDROID_11")
            }
        }
        tap("Warning")
        waitFor("The call \"haptics.notification('warning')\" failed with \"unsupported\": Android has no haptic feedback of a warning.")
        tap("Vibrate for 0 seconds")
        waitForStart("The call \"haptics.vibrate(0)\" raised: ")
        saveScreenshot("haptics")
    }
}
