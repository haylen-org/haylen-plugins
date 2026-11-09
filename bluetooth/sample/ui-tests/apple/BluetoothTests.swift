import XCTest

#if os(iOS)
// The prompt of Bluetooth answers the sample, and a scan of eight seconds runs to its end without an error, whatever devices advertise around the device. The simulators have no Bluetooth, so the test runs on a device.
class BluetoothTests: HaylenUITestCase {
    func testThePromptAndAScan() throws {
#if targetEnvironment(simulator)
        throw XCTSkip("The simulators of Apple have no Bluetooth.")
#else
        tap("Ask")
        answerAlert(.allow)
        waitFor(element("Ask: granted"))
        tap("Scan")
        let ended = element("The scan ended.")
        let failed = element(startingWith: "Scan failed")
        waitUntil("The scan of eight seconds does not end.", timeout: 30) {
            ended.exists || failed.exists
        }
        XCTAssertFalse(failed.exists, "The scan failed: \"\(failed.exists ? failed.label : "")\".")
        try saveScreenshot("bluetooth")
#endif
    }
}
#endif
