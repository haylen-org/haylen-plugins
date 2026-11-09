import CoreHaptics
import XCTest

#if os(iOS)
// Every feedback of the sample answers, which is all that the haptic engine tells an app: an iPhone plays each one, an iPad and the simulator answer that they have no haptic engine, and a vibration of 0 seconds raises before it reaches the platform. The runner reads whether the device has a haptic engine from Core Haptics, as the plugin does.
class HapticsTests: HaylenUITestCase {
    static let calls = [
        ("Vibrate for 80 ms", "haptics.vibrate(0.08)"),
        ("Vibrate for 1 second", "haptics.vibrate(1)"),
        ("Light impact", "haptics.impact('light')"),
        ("Medium impact", "haptics.impact('medium')"),
        ("Heavy impact", "haptics.impact('heavy')"),
        ("Selection tick", "haptics.selection()"),
        ("Success", "haptics.notification('success')"),
        ("Warning", "haptics.notification('warning')"),
        ("Error", "haptics.notification('error')"),
    ]

    func testEveryFeedbackAnswers() throws {
        let hasEngine = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        for (button, code) in Self.calls {
            tap(button)
            if hasEngine {
                waitFor(element("The call \"\(code)\" played."))
            } else {
                waitFor(element(startingWith: "The call \"\(code)\" failed with \"unsupported\": This device has no haptic engine."))
            }
        }
        tap("Vibrate for 0 seconds")
        waitFor(element(startingWith: "The call \"haptics.vibrate(0)\" raised: "))
        try saveScreenshot("haptics")
    }
}
#endif
