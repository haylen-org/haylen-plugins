import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// Native part of the Links plugin on Apple platforms. The runtime creates it by the class name that `plugin.json` gives, and loads it while the app launches.
@objc(LinksPlugin)
final class LinksPlugin: NSObject, HaylenPlugin {
    struct Link: Decodable {
        let url: String
    }

    func load(with context: HaylenPluginContext) {
        // Answers `links.open` with `true` once an app took the url, and fails with the code `unsupported` when no app on the device opens it.
        context.register("open") { (params: Link) async throws -> Bool in
            guard let address = URL(string: params.url) else {
                throw HaylenFailure("The text \"\(params.url)\" is not a url.", code: "unsupported")
            }
            guard await Self.open(address) else {
                throw HaylenFailure("No app on this device opens \"\(params.url)\".", code: "unsupported")
            }
            return true
        }
    }

    // A Mac opens the url through the workspace, and the other devices through the application, which answers once the app that takes the url is known.
    @MainActor
    private static func open(_ address: URL) async -> Bool {
        #if os(macOS)
        return NSWorkspace.shared.open(address)
        #else
        return await UIApplication.shared.open(address)
        #endif
    }
}
