import XCTest

#if os(iOS)
// The sample checks, asks for and uses a permission of every state of its local plugin "permission-states" through the Permissions plugin, and logs each answer. The permission "asked" is the authorization of notifications. The system answers the notifications of an app that installs again within a day the way the person answered them before, so their prompt shows only on the first run of a day, and later runs find the answer that the run before left in the Settings app.
class PermissionsTests: HaylenUITestCase {
    static let refused = "The call \"states.requestPermission('asked')\" answered \"denied\"."

    func testEveryFixedStateAnswersTheSameToACheckARequestAndAUse() throws {
        for (name, state) in [("held", "granted"), ("refused", "denied"), ("untold", "unknown")] {
            tap("Check \(name)")
            expectLine("The call \"states.permission('\(name)')\" answered \"\(state)\".")
            tap("Ask for \(name)")
            expectLine("The call \"states.requestPermission('\(name)')\" answered \"\(state)\".")
        }

        // A permission that the system tells nothing of until the app tries counts as allowed, so only the refused one fails its use.
        tap("Use held")
        expectLine("The call \"states.use('held')\" answered: The plugin used the permission \"held\".")
        tap("Use untold")
        expectLine("The call \"states.use('untold')\" answered: The plugin used the permission \"untold\".")
        tap("Use refused")
        waitFor(element(startingWith: "The call \"states.use('refused')\" failed with \"denied\": The person has not allowed the permission \"refused\" of the sample."))

        let absent = "failed with \"unsupported\": The sample has the permission \"absent\" on no device."
        tap("Check absent")
        expectLine("The call \"states.permission('absent')\" \(absent)")
        tap("Ask for absent")
        expectLine("The call \"states.requestPermission('absent')\" \(absent)")
        tap("Use absent")
        expectLine("The call \"states.use('absent')\" \(absent)")

        tap("Check permissions.state('nobody')")
        waitFor(element(matching: "The call \"permissions\\.state\\('nobody'\\)\" raised: .*The permission \"nobody\" belongs to no plugin that the app loaded\\..*"))
        try saveScreenshot("fixed-states")
    }

    func testAskedIsRefusedAndThenAllowedInTheSettings() throws {
        tap("Check permissions.state('asked')")
        let first = element(matching: "The call \"permissions\\.state\\('asked'\\)\" answered \"(prompt|denied|granted)\"\\.")
        waitFor(first)

        // The first run of a day refuses the prompt, and a later run turns off in the Settings app what the run before allowed.
        if first.label.contains("\"prompt\"") {
            tap("Ask for asked")
            answerAlert(.deny)
            expectLine(Self.refused)
        } else if first.label.contains("\"granted\"") {
            setNotificationsInSettings(allowed: false)
            app.activate()
        }

        tap("Check asked")
        expectLine("The call \"states.permission('asked')\" answered \"denied\".")
        tap("Use asked")
        waitFor(element(startingWith: "The call \"states.use('asked')\" failed with \"denied\": The person has not allowed notifications."))

        // The system shows its prompt once, so a request after a refusal answers it at once.
        let refusals = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", Self.refused)).count
        tap("Ask for asked")
        expectLine(Self.refused, count: refusals + 1)
        XCTAssertFalse(Self.system.alerts.firstMatch.exists, "The system shows its prompt again after the person refused it.")

        setNotificationsInSettings(allowed: true)
        app.activate()
        tap("Check asked")
        expectLine("The call \"states.permission('asked')\" answered \"granted\".")
        tap("Use asked")
        expectLine("The call \"states.use('asked')\" answered: The plugin used the permission \"asked\".")
        try saveScreenshot("asked-allowed")
    }

    // Waits until the log holds the line as many times as the count, since the same call answers the same line again.
    func expectLine(_ line: String, count: Int = 1, file: StaticString = #filePath, line number: UInt = #line) {
        let lines = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", line))
        waitUntil("The log holds \"\(line)\" \(lines.count) times instead of \(count).", file: file, line: number) {
            lines.count >= count
        }
    }

    // Turns the notifications of the app on or off in the Settings app, where the person changes what they answered in the prompt.
    func setNotificationsInSettings(allowed: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let settings = Self.settings
        settings.terminate()
        settings.launch()
        let apps = settings.cells.staticTexts["Apps"]
        scrollUntilVisible(apps, named: "Apps", in: settings, file: file, line: line)
        apps.tap()

        let name = settings.staticTexts["Permissions Sample"]
        scrollUntilVisible(name, named: "Permissions Sample", in: settings, file: file, line: line)
        name.tap()

        waitFor(settings.staticTexts["Notifications"], file: file, line: line).tap()
        let allow = settings.switches["Allow Notifications"]
        waitFor(allow, file: file, line: line)
        let wanted = allowed ? "1" : "0"

        // The row of the setting is a switch that holds the control itself as a switch of its own, which takes the tap, while a tap in the middle of the row lands on its title.
        if allow.value as? String != wanted {
            let control = allow.switches.firstMatch
            control.exists ? control.tap() : allow.tap()
        }
        waitUntil("The switch \"Allow Notifications\" does not turn \(allowed ? "on" : "off").", file: file, line: line) {
            allow.value as? String == wanted
        }
        settings.terminate()
    }

    // Swipes the list of an app up until the element is on the screen.
    func scrollUntilVisible(_ element: XCUIElement, named name: String, in application: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < 12 {
            application.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.exists && element.isHittable, "The settings show no \"\(name)\".", file: file, line: line)
    }
}
#endif
