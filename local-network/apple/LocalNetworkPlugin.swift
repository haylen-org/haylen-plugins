import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// Native part of the Local Network plugin on Apple platforms: the permission `localNetwork`, the screen `servicePicker`, whose list shows the services of one type that `NWBrowser` finds on the local network, and the advertisement of a service of the app through DNS-SD. Apple platforms tell an app nothing of the local network prompt, which the system shows once the app first reaches the local network, so the permission answers `unknown`.
@objc(LocalNetworkPlugin)
final class LocalNetworkPlugin: NSObject, HaylenPlugin {
    struct Empty: Codable {}

    struct Pick: Decodable {
        let type: String
    }

    struct Advertise: Decodable {
        let type: String
        let name: String
        let port: Int
    }

    private var advertisement: LocalNetworkAdvertisement?

    func load(with context: HaylenPluginContext) {
        Permissions.register(LocalNetworkPermission.make(), on: context)

        // Every app that loads the Lua API sends `reset`, so an advertisement that an earlier app of the process left stops.
        context.register("reset") { [unowned self] (_: Empty) async throws -> Empty? in
            self.stopAdvertising()
            return nil
        }

        context.register("advertise") { [unowned self] (params: Advertise) async throws -> LocalNetworkAdvertisement.Advertised in
            try LocalNetworkServices.require(params.type, on: context)
            try await Permissions.require("localNetwork", on: context)
            self.stopAdvertising()
            let advertisement = LocalNetworkAdvertisement(type: params.type, name: params.name, port: params.port)
            self.advertisement = advertisement
            return try await advertisement.start()
        }

        context.register("stopAdvertising") { [unowned self] (_: Empty) async throws -> Empty? in
            self.stopAdvertising()
            return nil
        }

        // The list of the picker shows over the app on iOS, iPadOS, tvOS and visionOS, in a sheet of its own on Mac Catalyst and in a sheet of the window of the app on macOS. A pick resolves the service before the screen ends, and Cancel ends it with the code `cancelled`.
        context.registerScreen("servicePicker") { (params: Pick, screen: HaylenScreen) in
            try LocalNetworkServices.require(params.type, on: context)
            let browser = LocalNetworkBrowser(type: params.type)
            let view = LocalNetworkPickerView(browser: browser) { service in
                browser.resolve(service) { result in
                    switch result {
                    case .success(let picked):
                        try? screen.finish(encoding: picked)
                    case .failure(let failure):
                        screen.fail(failure.message, code: failure.code, data: nil)
                    }
                }
            } cancelled: {
                browser.stop()
                screen.fail("The person closed the picker of services.", code: "cancelled", data: nil)
            }
            screen.cancelHandler = { browser.stop() }
            browser.start()
            #if os(macOS)
            let hosting = NSHostingController(rootView: view)
            hosting.preferredContentSize = NSSize(width: 480, height: 400)
            screen.presentSheet(hosting)
            #else
            screen.present(UIHostingController(rootView: view))
            #endif
        }
    }

    private func stopAdvertising() {
        advertisement?.stop()
        advertisement = nil
    }
}
