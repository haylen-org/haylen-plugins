import Foundation

// The service types that the `Info.plist` of the app lists in `NSBonjourServices`, the only types that Apple platforms let the app find and advertise.
enum LocalNetworkServices {
    // Throws a `HaylenFailure` with the code `unsupported` when the app lacks the text of the local network prompt or does not list the type, before the plugin calls the system.
    static func require(_ type: String, on context: HaylenPluginContext) throws {
        try context.require(.usageDescription("NSLocalNetworkUsageDescription"))

        let listed = Bundle.main.object(forInfoDictionaryKey: "NSBonjourServices") as? [String] ?? []
        guard listed.contains(type) else {
            throw HaylenFailure("The app lists no service type \"\(type)\" in \"NSBonjourServices\" of its Info.plist, so Apple platforms neither find nor advertise it. Add it to the parameter \"bonjourServices\" of the plugin \"local-network\" in haylen.json.", code: "unsupported")
        }
    }
}
