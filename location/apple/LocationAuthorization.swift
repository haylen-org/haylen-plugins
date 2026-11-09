import CoreLocation
import Foundation

#if os(iOS) && !targetEnvironment(macCatalyst)
import UIKit
#endif

// The permissions `location`, `preciseLocation` and `backgroundLocation` that the plugin owns, which Core Location reads and asks for once the `Info.plist` gives the texts of its prompts. A request waits until the authorization changes from the one it started with, and on iPhones and iPads also until the app becomes active again after the prompt, since a person who keeps the location while the app is in use leaves the authorization as it was. Apple TV and Apple Vision Pro read the location only while the app is in use, and the location of a Mac is the same in the background. It lives on the main actor, whose thread makes its manager, so Core Location calls its delegate on the main thread, and it conforms to the delegate protocol on the main actor.
@MainActor
final class LocationAuthorization: NSObject, @MainActor CLLocationManagerDelegate {
    private struct Waiting {
        let status: CLAuthorizationStatus
        let answer: () -> Void
    }

    // The purpose key of the temporary precise location in `NSLocationTemporaryUsageDescriptionDictionary`.
    static let precisePurpose = "preciseLocation"

    // iOS shows the prompt of the location in the background once, so the plugin remembers that it asked.
    private static let askedBackground = "com.haylen.plugins.location.askedBackground"

    private let manager = CLLocationManager()
    private var waiting: [Waiting] = []
    private var prompted = false
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        manager.delegate = self
        #if os(iOS) && !targetEnvironment(macCatalyst)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.notePrompt()
            }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.answerAfterPrompt()
            }
        })
        #endif
    }

    func permissions() -> [Permission] {
        [location(), preciseLocation(), backgroundLocation()]
    }

    #if os(macOS)
    private static let usage = HaylenRequirement.usageDescription("NSLocationUsageDescription")
    #else
    private static let usage = HaylenRequirement.usageDescription("NSLocationWhenInUseUsageDescription")
    #endif

    private func location() -> Permission {
        Permission(name: "location", capability: "the location", requirements: [Self.usage], state: { [unowned self] answer in
            answer(self.locationState(), nil)
        }, request: { [unowned self] answer in
            self.ask({ self.manager.requestWhenInUseAuthorization() }) {
                answer(self.locationState(), nil)
            }
        })
    }

    // A person who allowed the approximate location keeps the precise one to ask for, which iOS offers for the time the app is in use in a prompt with the text of the purpose key.
    private func preciseLocation() -> Permission {
        Permission(name: "preciseLocation", capability: "the precise location", requirements: [Self.usage], state: { [unowned self] answer in
            answer(self.preciseState(), nil)
        }, request: { [unowned self] answer in
            guard self.isAllowed(self.manager.authorizationStatus) else {
                self.ask({ self.manager.requestWhenInUseAuthorization() }) {
                    answer(self.preciseStateAfterPrompt(), nil)
                }
                return
            }
            guard Self.hasPurpose() else {
                answer(.unsupported, "The plugin \"location\" needs the key \"\(Self.precisePurpose)\" of \"NSLocationTemporaryUsageDescriptionDictionary\" in the Info.plist, which the app lacks. Give the parameter \"preciseLocationUsage\" of the plugin a text.")
                return
            }
            self.requestFullAccuracy(answer)
        })
    }

    // Core Location answers the prompt of the temporary precise location on a queue of its own, and the answer reads the accuracy on the main actor.
    private func requestFullAccuracy(_ answer: @escaping Permission.Answer) {
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: Self.precisePurpose) { @Sendable _ in
            Task { @MainActor in
                answer(self.preciseState() == .granted ? .granted : .denied, nil)
            }
        }
    }

    private func backgroundLocation() -> Permission {
        #if os(tvOS) || os(visionOS)
        return Permission(name: "backgroundLocation", capability: "the location in the background", requirements: [], state: { answer in
            answer(.unsupported, Self.foregroundOnly)
        }, request: { answer in
            answer(.unsupported, Self.foregroundOnly)
        })
        #elseif os(iOS) && !targetEnvironment(macCatalyst)
        let always = HaylenRequirement.usageDescription("NSLocationAlwaysAndWhenInUseUsageDescription")
        return Permission(name: "backgroundLocation", capability: "the location in the background", requirements: [Self.usage, always], state: { [unowned self] answer in
            answer(self.backgroundState(), nil)
        }, request: { [unowned self] answer in
            UserDefaults.standard.set(true, forKey: Self.askedBackground)
            self.ask({ self.manager.requestAlwaysAuthorization() }) {
                answer(self.backgroundState(), nil)
            }
        })
        #else
        return Permission(name: "backgroundLocation", capability: "the location in the background", requirements: [Self.usage], state: { [unowned self] answer in
            answer(self.locationState(), nil)
        }, request: { [unowned self] answer in
            self.ask({ self.manager.requestWhenInUseAuthorization() }) {
                answer(self.locationState(), nil)
            }
        })
        #endif
    }

    #if os(tvOS)
    static let foregroundOnly = "Apple TV reads the location only while the app is in use."
    #elseif os(visionOS)
    static let foregroundOnly = "Apple Vision Pro reads the location only while the app is in use."
    #endif

    private func locationState() -> Permission.State {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            return .prompt
        }
        return isAllowed(status) ? .granted : .denied
    }

    // The approximate location leaves the precise one to ask for in a prompt of its own.
    private func preciseState() -> Permission.State {
        let state = locationState()
        guard state == .granted else {
            return state
        }
        return manager.accuracyAuthorization == .fullAccuracy ? .granted : .prompt
    }

    // A person who allowed only the approximate location in the first prompt refused the precise one.
    private func preciseStateAfterPrompt() -> Permission.State {
        let state = preciseState()
        return state == .prompt ? .denied : state
    }

    #if os(iOS) && !targetEnvironment(macCatalyst)
    private func backgroundState() -> Permission.State {
        switch manager.authorizationStatus {
        case .notDetermined:
            return .prompt
        case .authorizedAlways:
            return .granted
        case .authorizedWhenInUse:
            return UserDefaults.standard.bool(forKey: Self.askedBackground) ? .denied : .prompt
        default:
            return .denied
        }
    }
    #endif

    private func isAllowed(_ status: CLAuthorizationStatus) -> Bool {
        #if os(macOS)
        return status == .authorizedAlways
        #elseif os(visionOS)
        return status == .authorizedWhenInUse
        #else
        return status == .authorizedAlways || status == .authorizedWhenInUse
        #endif
    }

    private static func hasPurpose() -> Bool {
        let purposes = Bundle.main.object(forInfoDictionaryKey: "NSLocationTemporaryUsageDescriptionDictionary") as? [String: Any]
        let text = purposes?[precisePurpose] as? String
        return text?.isEmpty == false
    }

    private func ask(_ request: () -> Void, answer: @escaping () -> Void) {
        waiting.append(Waiting(status: manager.authorizationStatus, answer: answer))
        request()
    }

    // Core Location also reports the authorization when the manager starts, which answers no request whose authorization stayed as it was.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let current = manager.authorizationStatus
        let answered = waiting.filter { $0.status != current }
        waiting.removeAll { $0.status != current }
        for entry in answered {
            entry.answer()
        }
    }

    private func notePrompt() {
        prompted = !waiting.isEmpty
    }

    private func answerAfterPrompt() {
        guard prompted else {
            return
        }
        prompted = false

        let answered = waiting
        waiting.removeAll()
        for entry in answered {
            entry.answer()
        }
    }
}
