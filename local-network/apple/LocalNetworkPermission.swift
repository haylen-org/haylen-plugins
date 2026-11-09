import Foundation

// The permission `localNetwork` that the plugin owns. Apple platforms have no API that reads or asks for it: the system shows its prompt, with the text of `NSLocalNetworkUsageDescription`, the first time the app reaches the local network, and tells the app nothing of the answer, so the state is `unknown` and a request goes on without a prompt.
enum LocalNetworkPermission {
    static func make() -> Permission {
        Permission(name: "localNetwork", capability: "the local network", requirements: [.usageDescription("NSLocalNetworkUsageDescription")], state: { answer in
            answer(.unknown, nil)
        }, request: { answer in
            answer(.unknown, nil)
        })
    }
}
