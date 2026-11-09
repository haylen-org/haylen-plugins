import XCTest

#if os(iOS)
// The prompt of notifications answers the sample, and a tap on a notification reaches the app while it shows, from the Home Screen and after the system ended it. The lists follow what waits and what showed, and a cancel removes what waits. A run installs the app anew, so the first test that asks shows the prompt.
class NotificationTests: HaylenUITestCase {
    static let banner = "Tap to open the sample."

    func testATapWhileTheAppShows() throws {
        allowNotifications()
        schedule()
        tapNotification(containing: Self.banner)
        waitFor(element(matching: "Opened: .*\"id\":\"soon\".*"))
        try saveScreenshot("opened-in-front")
    }

    func testATapFromTheHomeScreen() throws {
        allowNotifications()
        schedule()
        goHome()
        tapNotification(containing: Self.banner)
        waitFor(element(matching: "Opened: .*\"id\":\"soon\".*"))
        try saveScreenshot("opened-from-background")
    }

    func testATapThatLaunchesTheAppReachesItsFirstListener() throws {
        allowNotifications()
        schedule()
        app.terminate()
        tapNotification(containing: Self.banner)
        waitFor(element(matching: "Opened: .*\"id\":\"soon\".*"))
        try saveScreenshot("opened-at-launch")
    }

    func testTheListsFollowWhatWaitsAndWhatShowed() throws {
        allowNotifications()
        tap("In a minute, silent")
        waitFor(element(matching: "In a minute: .*\"id\":\"minute\".*"))
        tap("Pending")
        waitFor(element(matching: "Pending: .*\"id\":\"minute\".*"))
        tap("Cancel the minute")
        waitFor(element(startingWith: "Cancel: "))
        tap("Pending")
        waitFor(element(matching: "Pending: (\\[\\]|\\{\\})"))
        tap("Delivered")
        waitFor(element(startingWith: "Delivered: "))
        tap("Cancel all")
        waitFor(element(startingWith: "Cancel all: "))
        try saveScreenshot("lists")
    }

    // Reads the permission, and asks for it with the prompt of the system while the system still asks.
    func allowNotifications() {
        tap("Permission")
        let state = element(startingWith: "Permission: ")
        waitFor(state)
        let asks = state.label.hasPrefix("Permission: prompt")
        tap("Ask")
        if asks {
            answerAlert(.allow)
        }
        waitFor(element("Ask: granted"))
    }

    func schedule() {
        tap("In 5 seconds")
        waitFor(element(matching: "In 5 seconds: .*\"id\":\"soon\".*"))
    }
}
#endif
