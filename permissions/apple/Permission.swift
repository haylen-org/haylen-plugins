import Foundation

// A permission that a plugin owns, such as `camera`, which the plugin declares in the `permissions` of its `plugin.json` and registers with `Permissions.register(_:on:)`. The handlers of the plugin then answer `<id>.permission` and `<id>.requestPermission` for it: they check the requirements first, which answer `unsupported` with what the project lacks, read the state with the `state` block, and run the `request` block only while the state is `prompt`. Both blocks run on the main actor and call their answer once, from any thread, with the sentence that says why for `unsupported`.
final class Permission {
    // The app holds the permission, asking may show the prompt of the system, the person refused it, the system tells nothing until the app tries, or the device has no such capability, which the message of the answer explains.
    enum State: Sendable {
        case granted
        case prompt
        case denied
        case unknown
        case unsupported

        var name: String {
            switch self {
            case .granted:
                return "granted"
            case .prompt:
                return "prompt"
            case .denied:
                return "denied"
            case .unknown:
                return "unknown"
            case .unsupported:
                return "unsupported"
            }
        }
    }

    typealias Answer = @Sendable (State, String?) -> Void

    // The name that the app checks and asks for, such as `camera`.
    let name: String

    // What the permission gives the app in words, such as `the camera`, for the sentences of answers.
    let capability: String

    // What the project of the app needs before the system shows the prompt, such as the usage description of the `Info.plist`.
    let requirements: [HaylenRequirement]

    let state: @MainActor (@escaping Answer) -> Void
    let request: @MainActor (@escaping Answer) -> Void

    init(name: String, capability: String, requirements: [HaylenRequirement], state: @escaping @MainActor (@escaping Answer) -> Void, request: @escaping @MainActor (@escaping Answer) -> Void) {
        self.name = name
        self.capability = capability
        self.requirements = requirements
        self.state = state
        self.request = request
    }
}
