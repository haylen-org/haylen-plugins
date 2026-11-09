import Foundation
import os

// The permissions that the native parts of plugins register on Apple platforms, by plugin. The first permission that a plugin registers gives its context the handlers `permission` and `requestPermission`, which answer `{name}` with the name of the state, or fail with the code `unsupported`, the reason and `data.missing`, and `require` asks for a permission before the plugin uses the capability. The permissions live on the main actor, where plugins register them as they load and where their handlers run, and the answers of their blocks reach it from any thread.
@MainActor
enum Permissions {
    // What a check or a request answers: the state, the sentence of an unsupported answer and the requirements that the project lacks, each `{kind, name, file, snippet}`.
    struct Reply {
        let state: Permission.State
        let message: String
        let missing: [[String: String]]

        // Answers a call of the handlers: the name of the state, or the failure of a state of `unsupported`, as `require` throws it.
        func send(_ reply: @escaping HaylenReply) {
            guard state == .unsupported else {
                reply(true, state.name)
                return
            }
            var failure: [String: Any] = ["message": message, "code": "unsupported"]
            if !missing.isEmpty {
                failure["data"] = ["missing": missing]
            }
            reply(false, failure)
        }
    }

    private enum Registration {
        case first
        case next
        case twice
    }

    private static var registered: [String: [String: Permission]] = [:]

    // Registers a permission that the plugin of the context declares in the `permissions` of its `plugin.json`, so the handlers `<id>.permission` and `<id>.requestPermission` answer for it. A name that the plugin registered before keeps its first permission, and the log names the mistake.
    static func register(_ permission: Permission, on context: HaylenPluginContext) {
        switch add(permission, plugin: context.identifier) {
        case .twice:
            NSLog("The plugin \"%@\" registered the permission \"%@\" twice, and the first one stays.", context.identifier, permission.name)
        case .first:
            registerHandler("permission", asking: false, on: context)
            registerHandler("requestPermission", asking: true, on: context)
        case .next:
            return
        }
    }

    // Asks for the permission `name` that the plugin registered, such as "camera", where the app does not hold it yet, before the plugin uses the capability. Returns once the app holds it or the system tells nothing until the app tries. Throws a `HaylenFailure` with the code `denied` when the person refused it or the system did not show its prompt, or `unsupported` with the reason, whose data lists in `missing` what the project lacks. A name that the plugin did not register throws `unsupported` too.
    static func require(_ name: String, on context: HaylenPluginContext) async throws {
        let plugin = context.identifier
        guard let permission = find(name, plugin: plugin) else {
            throw HaylenFailure("The plugin \"\(plugin)\" requires the permission \"\(name)\", which it did not register with \"Permissions.register\".", code: "unsupported")
        }

        let requirements = context.requirements
        let reply = await withCheckedContinuation { (continuation: CheckedContinuation<Reply, Never>) in
            answer(permission, asking: true, requirements: requirements) { reply in continuation.resume(returning: reply) }
        }

        if let failure = failure(of: reply, permission: permission, plugin: plugin) {
            throw failure
        }
    }

    // The sentence of a use of the capability that a request did not allow, the same on every platform: after `prompt`, where the system did not show its prompt, it says that the app may ask again later, and after `denied` it names how to ask for it again.
    static func refusal(_ answered: Permission.State, permission: Permission, plugin: String) -> String {
        let call = "\(plugin).requestPermission('\(permission.name)')"
        if answered == .prompt {
            return "The system did not show its prompt for \(permission.capability), so the app does not hold it yet. Ask for it again later with \"\(call)\"."
        }
        return "The person has not allowed \(permission.capability). Ask for it with \"\(call)\", which shows the prompt of the system while the system still asks, or the person allows it in the settings of the system."
    }

    private static func add(_ permission: Permission, plugin: String) -> Registration {
        var permissions = registered[plugin] ?? [:]
        if permissions[permission.name] != nil {
            return .twice
        }
        permissions[permission.name] = permission
        registered[plugin] = permissions
        return permissions.count == 1 ? .first : .next
    }

    private static func find(_ name: String, plugin: String) -> Permission? {
        return registered[plugin]?[name]
    }

    // The handlers answer `{"name": ...}` with the answer of the permission, and a name that the plugin did not register on this platform fails with the code `unsupported`.
    private static func registerHandler(_ method: String, asking: Bool, on context: HaylenPluginContext) {
        let plugin = context.identifier
        let requirements = context.requirements
        context.registerHandler(method) { params, reply in
            let name = (params as? [String: Any])?["name"] as? String ?? ""
            guard let permission = find(name, plugin: plugin) else {
                reply(false, ["message": "The plugin \"\(plugin)\" registers no permission \"\(name)\" on this platform.", "code": "unsupported"])
                return
            }
            answer(permission, asking: asking, requirements: requirements) { answered in answered.send(reply) }
        }
    }

    // A project that lacks a requirement answers `unsupported` with what it lacks before the blocks of the permission run.
    private static func answer(_ permission: Permission, asking: Bool, requirements: HaylenRequirements, completion: @escaping @MainActor (Reply) -> Void) {
        do {
            try requirements.require(permission.requirements)
        } catch {
            let failure = (error as NSError).userInfo
            let data = failure["data"] as? [String: Any]
            completion(Reply(state: .unsupported, message: failure["message"] as? String ?? error.localizedDescription, missing: data?["missing"] as? [[String: String]] ?? []))
            return
        }

        let finish = once(permission.name) { state, message in
            onMainActor {
                completion(Reply(state: state, message: state == .unsupported ? message ?? "" : "", missing: []))
            }
        }
        let afterState = asking ? once(permission.name, promptWhenAsked(permission, answer: finish)) : finish
        permission.state(afterState)
    }

    // A state other than `prompt` answers the request without showing the prompt.
    private static func promptWhenAsked(_ permission: Permission, answer: @escaping Permission.Answer) -> Permission.Answer {
        let request = permission.request
        return { state, message in
            if state != .prompt {
                answer(state, message)
                return
            }
            onMainActor {
                request(answer)
            }
        }
    }

    // A block of the plugin that answers twice is a mistake of the plugin, which the log names, while the first answer stands.
    private nonisolated static func once(_ name: String, _ answer: @escaping Permission.Answer) -> Permission.Answer {
        let answered = OSAllocatedUnfairLock(initialState: false)
        return { state, message in
            let first = answered.withLock { answered in
                defer { answered = true }
                return !answered
            }
            guard first else {
                NSLog("The permission \"%@\" answered more than once, while its blocks answer once.", name)
                return
            }
            answer(state, message)
        }
    }

    // A permission that the system tells nothing of until the app tries lets the plugin go on.
    private static func failure(of reply: Reply, permission: Permission, plugin: String) -> HaylenFailure? {
        switch reply.state {
        case .granted, .unknown:
            return nil
        case .prompt, .denied:
            return HaylenFailure(refusal(reply.state, permission: permission, plugin: plugin), code: "denied")
        case .unsupported:
            return HaylenFailure(reply.message, code: "unsupported", data: reply.missing.isEmpty ? nil : ["missing": reply.missing])
        }
    }

    // An answer that arrives on the main thread goes on at once, and one from another thread goes on in a task on the main actor.
    private nonisolated static func onMainActor(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(work)
            return
        }
        Task { @MainActor in
            work()
        }
    }
}
