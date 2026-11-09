package com.haylen.uitests

import kotlin.math.abs
import kotlin.math.sqrt
import org.junit.Assert.assertTrue
import org.junit.Test

// The motion sensors deliver readings without a dialog, since Android asks for none, and the device at rest reads the gravity of the Earth. A rate above the limit raises before it reaches the platform.
class MotionTests : HaylenUiTestCase() {
    companion object {
        const val GRAVITY = 9.81
        // How far from the gravity of the Earth a device at rest may read, for the noise of its sensor and the tilt of the surface it rests on.
        const val GRAVITY_TOLERANCE = 1.0
        const val ALL = "motion.start({sensors = {'accelerometer', 'gyroscope', 'attitude'}, rate = 100, owner = self})"
        const val SLOW = "motion.start({sensors = {'accelerometer', 'gyroscope', 'attitude'}, rate = 10, owner = self})"
        val NUMBER = Regex("-?[0-9]+\\.[0-9]+")
    }

    @Test
    fun theSensorsAnswerAndReadTheGravityAtRest() {
        tap("Check the permission")
        waitFor("The call \"motion.permission()\" answered \"granted\".")
        tap("Start every sensor")
        waitFor("The call \"$ALL\" runs accelerometer, gyroscope, attitude.")
        expectGravity()
        tap("Start every sensor at 10 per second")
        waitFor("The call \"$SLOW\" runs accelerometer, gyroscope, attitude.")
        expectGravity()
        tap("Take this angle as level")
        waitForStart("The call \"motion.calibrateTilt()\" answered ")
        saveScreenshot("motion")
        tap("Stop the sensors")
        tap("Start at 500 per second")
        waitForStart("The call \"motion.start({rate = 500})\" raised: ")
    }

    // Waits until the acceleration that the sample shows has the length of the gravity of the Earth, as a device at rest reads.
    private fun expectGravity() {
        var reading = ""
        val atRest = poll {
            reading = labelOf(elementStartingWith("Acceleration ")) ?: ""
            val numbers = NUMBER.findAll(reading).map { it.value.toDouble() }.toList()
            numbers.size >= 3 && abs(sqrt(numbers[0] * numbers[0] + numbers[1] * numbers[1] + numbers[2] * numbers[2]) - GRAVITY) < GRAVITY_TOLERANCE
        }
        assertTrue("The acceleration never reads the gravity of a device at rest. It reads \"$reading\".", atRest)
    }
}
