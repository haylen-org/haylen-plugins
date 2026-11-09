package com.haylen.uitests

import android.os.Build
import org.junit.Assert.assertTrue
import org.junit.Test

// The permission dialog of the location answers the sample, the location in the background follows the page of the settings or the dialog where Android asks for it, and the place that the runner simulates reaches one fix and the updates.
class LocationTests : HaylenUiTestCase() {
    companion object {
        const val LATITUDE = 48.85837
        const val LONGITUDE = 2.29448
    }

    @Test
    fun theDialogsTheFixAndTheUpdates() {
        simulateLocation(LATITUDE, LONGITUDE)
        tap("Ask for the location")
        answerPermission("permission_allow_foreground_only_button")
        waitFor("The call \"location.requestPermission('location')\" answered \"granted\".")
        tap("Read the location")
        val fix = waitForStart("The call \"location.current()\" answered {")
        assertTrue("The fix \"$fix\" is not the simulated place.", fix.contains("48.858") && fix.contains("2.294"))

        // Android 11 and later ask for the location in the background on a page of the settings, which the back button leaves, and Android 10 in a dialog.
        tap("Ask for the location in the background")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            waitFor(permissionControl("allow_always_radio_button"), "the choice \"Allow all the time\" of the settings").click()
            device.pressBack()
            waitForApp()
        } else {
            answerPermission("permission_allow_button")
        }
        waitFor("The call \"location.requestPermission('backgroundLocation')\" answered \"granted\".")
        tap("Watch in the background too")
        waitForStart("The call \"location.watch({background = true, owner = self})\" answered ")
        saveScreenshot("location")
        tap("Stop watching")
        waitForStart("The call \"location.stop()\" answered ")
    }
}
