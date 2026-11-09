import XCTest

#if os(iOS)
// On a device the prompt of the microphone answers the sample, the microphone records at both rates, its level follows the sound of the room, and the recording plays back while it records. The simulator records through the microphone of the Mac, which the Mac guards with a prompt of its own that no test answers, so the test runs on a device.
class MicrophoneTests: HaylenUITestCase {
    func testThePromptTheRecordingAndThePlayback() throws {
#if targetEnvironment(simulator)
        throw XCTSkip("The simulator records through the microphone of the Mac, which the Mac guards with a prompt that no test answers.")
#else
        tap("Ask for the microphone")
        answerAlert(.allow)
        waitFor(element("The call \"microphone.requestPermission()\" answered \"granted\"."))
        tap("Start at 16000 Hz")
        waitFor(element(startingWith: "The call \"microphone.start({sampleRate = 16000, owner = self})\" answered {"))
        tap("Start at 48000 Hz")
        waitFor(element(startingWith: "The call \"microphone.start({owner = self})\" answered {"))
        // A room is never silent to a microphone, so the level rises above zero.
        let level = element(startingWith: "Level ")
        waitUntil("The level of the microphone stays at zero. It reads \"\(level.label)\".") {
            level.exists && level.label != "Level 0.000"
        }
        tap("Play it back")
        waitFor(element(matching: "The recording of [0-9]+ Hz plays back\\."))
        try saveScreenshot("microphone")
        tap("Stop playing it back")
        tap("Stop the microphone")
        waitFor(element(startingWith: "The call \"microphone.stop()\" answered "))
#endif
    }
}
#endif
