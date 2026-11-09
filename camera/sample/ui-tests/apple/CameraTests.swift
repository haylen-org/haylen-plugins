import XCTest

#if os(iOS)
// The prompt of the camera answers the sample. On a device the cameras start, show their picture and take photos, while the simulator, which has no camera, lists none and answers a start with "noCamera".
class CameraTests: HaylenUITestCase {
    func testThePromptTheCamerasAndAPhoto() throws {
        tap("Ask for the camera")
        answerAlert(.allow)
        waitFor(element("The call \"camera.requestPermission()\" answered \"granted\"."))
        tap("List the cameras")
#if targetEnvironment(simulator)
        waitFor(element("The call \"camera.cameras()\" answered []."))
        tap("Start the back camera")
        waitFor(element(startingWith: "The call \"camera.start({facing = 'back', owner = self})\" failed with \"noCamera\": "))
#else
        waitFor(element(startingWith: "The call \"camera.cameras()\" answered [{"))
        tap("Start the back camera")
        waitFor(element(startingWith: "The call \"camera.start({facing = 'back', owner = self})\" answered {"))
        tap("Take a photo")
        waitFor(element(matching: "The call \"camera.takePhoto\\(\\)\" answered a photo of [0-9]+ by [0-9]+\\."))
        try saveScreenshot("back-camera")
        tap("Start the front camera")
        waitFor(element(startingWith: "The call \"camera.start({facing = 'front', owner = self})\" answered {"))
        tap("Start at 1280 by 720")
        waitFor(element(startingWith: "The call \"camera.start({width = 1280, height = 720, owner = self})\" answered {"))
        try saveScreenshot("large-camera")
        tap("Stop the camera")
        waitFor(element("The call \"camera.stop()\" answered null."))
#endif
    }
}
#endif
