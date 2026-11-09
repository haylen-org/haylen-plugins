package com.haylen.uitests

import androidx.test.uiautomator.By
import java.util.regex.Pattern
import org.junit.Test

// The loop of the sample shows in the media notification of the shade with its title and artist, its pause button reaches the app as a command, and the notification goes once the app leaves the controls. Android 13 and later draw the buttons of the notification from the playback state, so the test of the button needs one of them.
class MediaSessionTests : HaylenUiTestCase() {
    companion object {
        const val TITLE = "Harbor at dawn"
        const val ARTIST = "The island band"
        const val SYSTEM_UI = "com.android.systemui"
    }

    @Test
    fun theMediaNotificationShowsTheLoop() {
        waitFor("The loop plays and shows in the controls of the system.")
        device.openNotification()
        waitFor(By.pkg(SYSTEM_UI).text(TITLE), "the media notification of \"$TITLE\"")
        waitFor(By.pkg(SYSTEM_UI).text(ARTIST), "the artist \"$ARTIST\" in the media notification")
        device.pressBack()
        saveScreenshot("notification")
    }

    @Test
    fun thePauseButtonOfTheNotificationReachesTheApp() {
        waitFor("The loop plays and shows in the controls of the system.")
        device.openNotification()
        waitFor(By.pkg(SYSTEM_UI).text(TITLE), "the media notification of \"$TITLE\"")
        waitFor(By.pkg(SYSTEM_UI).desc("Pause"), "the pause button of the media notification").click()
        device.pressBack()
        waitFor(Pattern.compile("Command: (pause|togglePlayPause)\\."))
    }

    @Test
    fun theNotificationGoesWhenTheAppLeavesTheControls() {
        waitFor("The loop plays and shows in the controls of the system.")
        tap("Leave the controls")
        waitFor("The app left the controls.")
        device.openNotification()
        waitUntil("The media notification stayed after the app left the controls.") {
            !device.hasObject(By.pkg(SYSTEM_UI).text(TITLE))
        }
        device.pressBack()
    }
}
