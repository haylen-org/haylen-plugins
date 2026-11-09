import XCTest

#if os(iOS)
// What the sample shows reaches the now-playing info center of MediaPlayer, which the plugin reads back for the line of the log that these tests read, and leaves it when the app leaves the controls.
class MediaSessionTests: HaylenUITestCase {
    func testTheLoopReachesTheInfoCenterWithItsArtwork() throws {
        tap("Read the controls")
        waitFor(element(matching: "Controls: \"Harbor at dawn\" by \"The island band\" from \"Tides\", 8 seconds, playing, with artwork\\."))
        try saveScreenshot("shown")
    }

    func testAPauseReachesTheInfoCenter() throws {
        tap("Play or pause")
        tap("Read the controls")
        waitFor(element(matching: "Controls: \"Harbor at dawn\" .*, paused, with artwork\\."))
    }

    func testLeavingTheControlsEmptiesTheInfoCenter() throws {
        tap("Leave the controls")
        waitFor(element("The app left the controls."))
        tap("Read the controls")
        waitFor(element("Controls: nothing."))

        tap("Show again")
        tap("Read the controls")
        waitFor(element(matching: "Controls: \"Harbor at dawn\" .*, with artwork\\."))
    }
}
#endif
