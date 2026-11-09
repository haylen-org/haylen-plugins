package com.haylen.uitests

import java.util.regex.Pattern
import org.junit.Test

// The permission dialog of notifications answers the sample, and a tap on a notification reaches the app while it shows, from the home screen and after it left the recent apps. The lists follow what waits and what showed, and a cancel removes what waits. A run installs the app anew, so the first test that asks shows the dialog.
class NotificationTests : HaylenUiTestCase() {
    companion object {
        const val TEXT = "Tap to open the sample."
        val OPENED: Pattern = Pattern.compile("Opened: .*\"id\":\"soon\".*")
    }

    @Test
    fun aTapWhileTheAppShows() {
        allowNotifications()
        schedule()
        tapNotification(TEXT)
        waitFor(OPENED)
        saveScreenshot("opened-in-front")
    }

    @Test
    fun aTapFromTheHomeScreen() {
        allowNotifications()
        schedule()
        goHome()
        tapNotification(TEXT)
        waitFor(OPENED)
        saveScreenshot("opened-from-background")
    }

    @Test
    fun aTapThatLaunchesTheAppAfterItLeftTheRecentApps() {
        allowNotifications()
        schedule()
        // The notification wakes the process of the app as it posts, so the app ends only once the notification is there.
        waitForNotification(TEXT)
        removeFromRecents()
        tapNotification(TEXT)
        waitFor(OPENED)
        saveScreenshot("opened-at-launch")
    }

    @Test
    fun theListsFollowWhatWaitsAndWhatShowed() {
        allowNotifications()
        tap("In a minute, silent")
        waitFor(Pattern.compile("In a minute: .*\"id\":\"minute\".*"))
        tap("Pending")
        waitFor(Pattern.compile("Pending: .*\"id\":\"minute\".*"))
        tap("Cancel the minute")
        waitForStart("Cancel: ")
        tap("Pending")
        waitFor(Pattern.compile("Pending: (\\[\\]|\\{\\})"))
        tap("Delivered")
        waitForStart("Delivered: ")
        tap("Cancel all")
        waitForStart("Cancel all: ")
        saveScreenshot("lists")
    }

    // Reads the permission, and asks for it with the dialog of the system while the system still asks.
    private fun allowNotifications() {
        tap("Permission")
        val asks = waitForStart("Permission: ").startsWith("Permission: prompt")
        tap("Ask")
        if (asks) {
            answerPermission("permission_allow_button")
        }
        waitFor("Ask: granted")
    }

    private fun schedule() {
        tap("In 5 seconds")
        waitFor(Pattern.compile("In 5 seconds: .*\"id\":\"soon\".*"))
    }
}
