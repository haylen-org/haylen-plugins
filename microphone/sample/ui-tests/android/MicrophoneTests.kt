package com.haylen.uitests

import java.util.regex.Pattern
import org.junit.Test

// The permission dialog of the microphone answers the sample, the microphone records at both rates, its level follows the sound around the device and the recording plays back while it records. The emulator records silence, so only a device shows a level above zero.
class MicrophoneTests : HaylenUiTestCase() {
    @Test
    fun theDialogTheRecordingAndThePlayback() {
        tap("Ask for the microphone")
        // Android 11 and later offer the permission while the app is in use, and Android 10 with a plain "Allow".
        answerPermission("permission_allow_foreground_only_button", "permission_allow_button")
        waitFor("The call \"microphone.requestPermission()\" answered \"granted\".")
        tap("Start at 16000 Hz")
        waitForStart("The call \"microphone.start({sampleRate = 16000, owner = self})\" answered {")
        tap("Start at 48000 Hz")
        waitForStart("The call \"microphone.start({owner = self})\" answered {")
        if (!isEmulator()) {
            waitUntil("The level of the microphone stays at zero.") {
                val level = labelOf(elementStartingWith("Level "))
                level != null && level != "Level 0.000"
            }
        }
        tap("Play it back")
        waitFor(Pattern.compile("The recording of [0-9]+ Hz plays back\\."))
        saveScreenshot("microphone")
        tap("Stop playing it back")
        tap("Stop the microphone")
        waitForStart("The call \"microphone.stop()\" answered ")
    }
}
