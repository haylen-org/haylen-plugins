import XCTest

#if os(iOS)
// The share sheet of the sample shows over the app, as a popover over its button on an iPad, and the answer of the person reaches the app.
class ShareTests: HaylenUITestCase {
    func testAnActivityThatCompletesAnswersShared() throws {
        tap("Text")
        let copy = waitFor(app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Copy'")).firstMatch)
        try saveScreenshot("sheet-text")
        copy.tap()
        waitFor(element(matching: "Text: (?=.*\"shared\":true)(?=.*CopyToPasteboard).*"))
        try saveScreenshot("shared")
    }

    func testASheetThatClosesAnswersNotShared() throws {
        tap("Two files")
        let copy = waitFor(app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Copy'")).firstMatch)
        try saveScreenshot("sheet-files")
        // A sheet closes with a swipe down on a phone, and a popover with a tap outside it on an iPad.
        if isPad {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
        } else {
            copy.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.0)))
        }
        waitFor(element(matching: "Two files: .*\"shared\":false.*"))
        try saveScreenshot("closed")
    }
}
#endif
