import XCTest

#if os(iOS)
// The motion sensors of an iPhone answer the prompt of the system and deliver readings, and the device at rest reads the gravity of the Earth. The simulator has no motion sensors, so its calls fail with "unsupported". A rate above the limit raises before it reaches the platform.
class MotionTests: HaylenUITestCase {
    static let gravity = 9.81
    // How far from the gravity of the Earth a device at rest may read, for the noise of its sensor and the tilt of the surface it rests on.
    static let gravityTolerance = 1.0
    static let all = "motion.start({sensors = {'accelerometer', 'gyroscope', 'attitude'}, rate = 100, owner = self})"
    static let slow = "motion.start({sensors = {'accelerometer', 'gyroscope', 'attitude'}, rate = 10, owner = self})"

    func testTheSensorsAnswerAndReadTheGravityAtRest() throws {
#if targetEnvironment(simulator)
        tap("Check the permission")
        waitFor(element(startingWith: "The call \"motion.permission()\" failed with \"unsupported\": "))
        tap("Start every sensor")
        waitFor(element(startingWith: "The call \"\(Self.all)\" failed with \"unsupported\": "))
#else
        // The system shows its prompt only while the person has not decided, so the test answers it only while the state is "prompt".
        tap("Check the permission")
        let state = waitFor(element(startingWith: "The call \"motion.permission()\" answered ")).label
        tap("Ask for the permission")
        if state.hasSuffix("answered \"prompt\".") {
            answerAlert(.allow)
        }
        waitFor(element("The call \"motion.requestPermission()\" answered \"granted\"."))
        tap("Start every sensor")
        waitFor(element("The call \"\(Self.all)\" runs accelerometer, gyroscope, attitude."))
        expectGravity()
        tap("Start every sensor at 10 per second")
        waitFor(element("The call \"\(Self.slow)\" runs accelerometer, gyroscope, attitude."))
        expectGravity()
        tap("Take this angle as level")
        waitFor(element("The call \"motion.calibrateTilt()\" answered true."))
        try saveScreenshot("motion")
        tap("Stop the sensors")
#endif
        tap("Start at 500 per second")
        waitFor(element(startingWith: "The call \"motion.start({rate = 500})\" raised: "))
    }

    // Waits until the acceleration that the sample shows has the length of the gravity of the Earth, as a device at rest reads.
    func expectGravity() {
        let label = element(startingWith: "Acceleration ")
        waitUntil("The acceleration never reads the gravity of a device at rest. It reads \"\(label.label)\".") {
            let numbers = label.label.split(whereSeparator: { !"-0123456789.".contains($0) }).compactMap { Double($0) }
            guard numbers.count >= 3 else {
                return false
            }

            let length = (numbers[0] * numbers[0] + numbers[1] * numbers[1] + numbers[2] * numbers[2]).squareRoot()
            return abs(length - Self.gravity) < Self.gravityTolerance
        }
    }
}
#endif
