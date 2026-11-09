package com.haylen.uitests

import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// The permission dialog of nearby devices, or of the location before Android 12, answers the sample, and a scan of eight seconds runs to its end without an error, whatever devices advertise around the device.
class BluetoothTests : HaylenUiTestCase() {
    @Test
    fun theDialogAndAScan() {
        tap("Ask")
        // Android 12 and later ask for nearby devices, and Android 11 and earlier for the location while the app is in use, which a scan needs there.
        answerPermission("permission_allow_button", "permission_allow_foreground_only_button")
        waitFor("Ask: granted")
        tap("Scan")
        val ended = poll(30_000L) { element("The scan ended.") != null || elementStartingWith("Scan failed") != null }
        val failure = labelOf(elementStartingWith("Scan failed"))
        assertTrue("The scan of eight seconds does not end.", ended)
        assertNull("The scan failed: \"$failure\".", failure)
        saveScreenshot("bluetooth")
    }
}
