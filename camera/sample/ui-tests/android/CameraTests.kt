package com.haylen.uitests

import java.util.regex.Pattern
import org.junit.Test

// The permission dialog of the camera answers the sample, and the cameras start, show their picture and take photos.
class CameraTests : HaylenUiTestCase() {
    @Test
    fun theDialogTheCamerasAndAPhoto() {
        tap("Ask for the camera")
        // Android 11 and later offer the permission while the app is in use, and Android 10 with a plain "Allow".
        answerPermission("permission_allow_foreground_only_button", "permission_allow_button")
        waitFor("The call \"camera.requestPermission()\" answered \"granted\".")
        tap("List the cameras")
        waitForStart("The call \"camera.cameras()\" answered [{")
        tap("Start the back camera")
        waitForStart("The call \"camera.start({facing = 'back', owner = self})\" answered {")
        tap("Take a photo")
        waitFor(Pattern.compile("The call \"camera\\.takePhoto\\(\\)\" answered a photo of [0-9]+ by [0-9]+\\."))
        saveScreenshot("back-camera")
        tap("Start the front camera")
        waitForStart("The call \"camera.start({facing = 'front', owner = self})\" answered {")
        tap("Start at 1280 by 720")
        waitForStart("The call \"camera.start({width = 1280, height = 720, owner = self})\" answered {")
        saveScreenshot("large-camera")
        tap("Stop the camera")
        waitForStart("The call \"camera.stop()\" answered ")
    }
}
