package com.haylen.uitests

import android.Manifest.permission.ACCESS_LOCAL_NETWORK
import androidx.test.uiautomator.By
import java.util.regex.Pattern
import org.junit.Test

// The sample asks for the local network before it advertises its own service, the picker of the system shows that service, and the pick hands the app its address and port, where the sample connects and its own service answers. The test takes the permission back before it starts, so the prompt shows on Android 17.
class LocalNetworkTests : HaylenUiTestCase() {
    companion object {
        const val SERVICE = "Haylen Sample"
        val ALLOW = arrayOf("permission_allow_button")

        // The picker is an activity of the resources of the connectivity module, whose package devices with Google services name with a prefix of their own.
        val PICKER: Pattern = Pattern.compile("(com\\.google\\.android|com\\.android)\\.connectivity\\.resources")
    }

    override val revokedPermissions = listOf(ACCESS_LOCAL_NETWORK)

    @Test
    fun thePickerOfTheSystemHandsTheAppTheServiceOfTheSample() {
        tap("Advertise the sample")
        answerPermission(*ALLOW)
        waitFor(Pattern.compile("Advertised \"Haylen Sample.*\" of the type \"_haylen-sample\\._tcp\" on the port \\d+\\."))

        tap("Pick a service")
        waitFor(By.text(SERVICE), "the service \"$SERVICE\" in the picker of the system").click()
        waitFor(Pattern.compile("Connected to \"Haylen Sample\", which answered \"Hello from the sample, android\"\\."))
        saveScreenshot("connected")
    }

    @Test
    fun theBackButtonEndsThePickerWithoutAService() {
        tap("Pick a service")
        waitFor(By.pkg(PICKER), "the picker of services of the system")
        device.pressBack()
        waitFor("The picker failed with \"cancelled\": The person closed the picker of services.")
    }
}
