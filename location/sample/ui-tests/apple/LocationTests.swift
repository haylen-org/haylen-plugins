import CoreLocation
import XCTest

#if os(iOS)
// The prompts of the location answer the sample, the location while in use and then always, which iOS asks for in a second prompt, and the place that the test simulates reaches one fix and the updates.
class LocationTests: HaylenUITestCase {
    static let place = CLLocation(latitude: 48.85837, longitude: 2.29448)

    func testThePromptsTheFixAndTheUpdates() throws {
        simulateLocation(Self.place)
        tap("Ask for the location")
        answerAlert(.allowWhileUsing)
        waitFor(element("The call \"location.requestPermission('location')\" answered \"granted\"."))
        tap("Read the location")
        waitFor(element(startingWith: "The call \"location.current()\" answered {"))
        let fix = element(startingWith: "The call \"location.current()\" answered {").label
        XCTAssertTrue(fix.contains("48.858") && fix.contains("2.294"), "The fix \"\(fix)\" is not the simulated place.")

        tap("Ask for the location in the background")
        answerAlert(.allow)
        waitFor(element("The call \"location.requestPermission('backgroundLocation')\" answered \"granted\"."))
        tap("Watch in the background too")
        waitFor(element(startingWith: "The call \"location.watch({background = true, owner = self})\" answered "))
        try saveScreenshot("location")
        tap("Stop watching")
        waitFor(element(startingWith: "The call \"location.stop()\" answered "))
    }
}
#endif
