import XCTest

#if os(iOS)
// The dialogs of the sample show on the simulator, and what the person picks in them reaches the app.
class DialogsTests: HaylenUITestCase {
    func testAMessageAnswersTheButtonThePersonPressed() throws {
        tap("Show a message")
        waitFor(app.alerts.buttons["Discard"])
        try saveScreenshot("message")
        app.alerts.buttons["Discard"].tap()
        waitFor(element("The person pressed button 2."))
    }

    func testASavedFileOpensAgain() throws {
        tap("Save a file")
        waitFor(app.navigationBars.buttons["Save"])
        try saveScreenshot("save")
        app.navigationBars.buttons["Save"].tap()
        let replace = app.buttons["Replace"]
        if replace.waitForExistence(timeout: 3) {
            replace.tap()
        }
        waitFor(element(matching: "The report went to \".*dialogs-report.json\"\\."))

        tap("Open files")
        let file = waitFor(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'dialogs-report'")).firstMatch)
        try saveScreenshot("open")
        file.tap()
        let open = app.navigationBars.buttons["Open"]
        if open.waitForExistence(timeout: 3) {
            open.tap()
        }
        waitFor(element(matching: "The person picked \"dialogs-report.json\" with [0-9]+ bytes\\."))
        try saveScreenshot("opened")
    }

    func testAPickedPhotoReachesTheApp() throws {
        tap("Pick photos")
        let photo = waitFor(app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo,'")).firstMatch)
        try saveScreenshot("photos")
        photo.tap()
        let done = app.buttons["Done"]
        waitUntil("The photo picker kept its button Done disabled after a photo was picked.") { done.isEnabled }
        done.tap()
        waitFor(element(matching: "The person picked \".+\" with [0-9]+ bytes\\."))
        try saveScreenshot("photo-picked")
    }
}
#endif
