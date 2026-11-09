import XCTest

#if os(iOS)
// The sample advertises its own service, the list of the picker shows it, and a tap on it hands the app its address and port, where the sample connects and its own service answers.
class LocalNetworkTests: HaylenUITestCase {
    func testThePickerFindsTheServiceOfTheSampleAndTheSampleConnectsToIt() throws {
        tap("Advertise the sample")
        waitFor(element(matching: "Advertised \"Haylen Sample.*\" of the type \"_haylen-sample\\._tcp\" on the port \\d+\\."))

        tap("Pick a service")
        let service = app.buttons["Haylen Sample"]
        XCTAssertTrue(service.waitForExistence(timeout: 30), "The picker shows no service \"Haylen Sample\".")
        try saveScreenshot("picker")
        service.tap()

        waitFor(element(matching: "Connected to \"Haylen Sample\", which answered \"Hello from the sample, ios\"\\."))
        try saveScreenshot("connected")
    }

    func testCancelEndsThePickerWithoutAService() throws {
        tap("Pick a service")
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 30), "The picker shows no Cancel button.")
        cancel.tap()
        waitFor(element("The picker failed with \"cancelled\": The person closed the picker of services."))
    }

    func testThePermissionIsUnknownOnApplePlatforms() throws {
        tap("Check the permission")
        waitFor(element("The permission \"localNetwork\" is \"unknown\"."))
    }
}
#endif
