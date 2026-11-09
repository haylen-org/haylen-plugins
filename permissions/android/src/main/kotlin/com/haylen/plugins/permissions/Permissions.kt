package com.haylen.plugins.permissions

import android.content.Context
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import dev.haylen.HaylenActivity
import dev.haylen.HaylenBridge
import dev.haylen.HaylenPluginContext
import dev.haylen.HaylenRequirements
import org.json.JSONObject

// Reads and asks for the permissions that the native parts of plugins register, by plugin. The first permission that a plugin registers gives its context the handlers `permission` and `requestPermission`, which answer `{name}` with the name of the state, or fail with the code `unsupported`, the reason and `data.missing`. The prompts of the system show through one launcher of the Activity Result API, which `PermissionsPlugin` registers under the key `haylen.permissions.request` before every activity starts, and requests wait in a queue and show one at a time. A permission that the app does not hold counts as denied once a request asked for it and Android no longer shows its prompt, which Android tells by no longer asking for a rationale, and the plugin remembers which permissions it asked for across launches.
object Permissions {
    // What a check or a request answers: the name of the state, the sentence of an unsupported answer and the requirements the project lacks, each `{kind, name, file, snippet}`.
    fun interface Answer {
        fun answer(state: String, message: String, missing: List<Map<*, *>>)
    }

    // A request that waits for its prompt, with the permissions of the manifest it asks for and the context of the app that reads its answer.
    private class Request(val permission: Permission, val asked: Array<String>, val answer: Answer, val application: Context)

    private const val LAUNCHER_KEY = "haylen.permissions.request"
    private const val PREFERENCES = "com.haylen.plugins.permissions"

    private val registered = HashMap<String, HashMap<String, Permission>>()
    private var launcher: ActivityResultLauncher<Array<String>>? = null
    private val queue = PermissionQueue(object : PermissionQueue.Prompts<Request> {
        override fun show(request: Request): Boolean = showPrompt(request)

        // The person may grant less than the prompt asked for, such as the approximate location for a request of the precise one, so the answer reads what the app holds.
        override fun answerPrompted(request: Request) {
            val state = if (request.permission.isGranted(request.application)) "granted" else "denied"
            request.answer.answer(state, "", emptyList())
        }

        override fun answerWithoutPrompt(request: Request) {
            answerState(request.permission, request.application, request.answer)
        }
    })

    // Registers a permission that the plugin of the context declares in the `permissions` of its `plugin.json`, so the handlers `<id>.permission` and `<id>.requestPermission` answer for it. Throws an `IllegalArgumentException` for a name that the plugin registered before.
    fun register(context: HaylenPluginContext, permission: Permission) {
        val first = synchronized(registered) {
            val permissions = registered.getOrPut(context.id()) { HashMap() }
            if (permissions.containsKey(permission.name)) {
                throw IllegalArgumentException("The plugin \"${context.id()}\" registered the permission \"${permission.name}\" twice.")
            }
            permissions[permission.name] = permission
            permissions.size == 1
        }

        if (first) {
            context.register("permission") { params, reply -> answerPermission(context, params, reply, false) }
            context.register("requestPermission") { params, reply -> answerPermission(context, params, reply, true) }
        }
    }

    // Runs `granted` on the main thread once the app holds the permission `name` that the plugin registered, such as `camera`, after it asked the person where the app does not hold it yet. A permission that the person refused, or whose request ended without the prompt of the system, fails the call with the code `denied` and the sentence that says so and how to ask again, a manifest that lacks it fails the call with the code `unsupported` and the missing lines in `data.missing`, and a `granted` that throws, a `HaylenBridge.Failure` among them, fails the call with its error. A request that shows no prompt because no activity exists answers `unknown`, which runs `granted` too. Throws an `IllegalArgumentException` for a name that the plugin did not register.
    fun require(context: HaylenPluginContext, name: String, reply: HaylenBridge.Reply, granted: Runnable) {
        val plugin = context.id()
        val permission = find(plugin, name) ?: throw IllegalArgumentException("The plugin \"$plugin\" requires the permission \"$name\", which it did not register with \"Permissions.register\".")

        context.runOnMainThread {
            ask(permission, context.application(), context.requirements()) { state, message, missing ->
                when (state) {
                    "granted", "unknown" -> runGranted(granted, reply)
                    "unsupported" -> failUnsupported(reply, message, missing)
                    else -> reply.failure(refusal(plugin, permission, state), "denied", null)
                }
            }
        }
    }

    // The sentence of a use of the capability that a request did not allow, the same on every platform: after `prompt`, where the system did not show its prompt, it says that the app may ask again later, and after `denied` it names how to ask for it again.
    fun refusal(plugin: String, permission: Permission, answered: String): String {
        val call = "$plugin.requestPermission('${permission.name}')"
        if (answered == "prompt") {
            return "The system did not show its prompt for ${permission.capability}, so the app does not hold it yet. Ask for it again later with \"$call\"."
        }
        return "The person has not allowed ${permission.capability}. Ask for it with \"$call\", which shows the prompt of the system while the system still asks, or the person allows it in the settings of the system."
    }

    // Called by `PermissionsPlugin` before every activity starts. A request that showed while the activity was recreated answers through the launcher of the new one. An activity that starts anew follows one that finished for good, whose prompt Android never answers, so the waiting requests answer the state that the app holds, without a prompt.
    internal fun activityCreated(activity: HaylenActivity, savedInstanceState: Bundle?) {
        launcher = activity.activityResultRegistry.register(LAUNCHER_KEY, activity, ActivityResultContracts.RequestMultiplePermissions()) { queue.answered() }

        if (savedInstanceState == null) {
            queue.answerWithoutPrompts()
        }
    }

    private fun find(plugin: String, name: String): Permission? {
        return synchronized(registered) { registered[plugin]?.get(name) }
    }

    private fun failUnsupported(reply: HaylenBridge.Reply, message: String, missing: List<Map<*, *>>) {
        reply.failure(message, "unsupported", if (missing.isEmpty()) null else mapOf("missing" to missing))
    }

    private fun runGranted(granted: Runnable, reply: HaylenBridge.Reply) {
        try {
            granted.run()
        } catch (error: Exception) {
            reply.failure(error)
        }
    }

    // A state of `unsupported` fails the call as `require` does, and a name that the plugin did not register on this platform fails it the same way.
    private fun answerPermission(context: HaylenPluginContext, params: Any?, reply: HaylenBridge.Reply, asking: Boolean) {
        val name = (params as? JSONObject)?.optString("name").orEmpty()
        val permission = find(context.id(), name)
        if (permission == null) {
            reply.failure("The plugin \"${context.id()}\" registers no permission \"$name\" on this platform.", "unsupported", null)
            return
        }

        val answer = Answer { state, message, missing ->
            if (state == "unsupported") {
                failUnsupported(reply, message, missing)
            } else {
                reply.success(state)
            }
        }
        if (asking) {
            ask(permission, context.application(), context.requirements(), answer)
        } else {
            check(permission, context.application(), context.requirements(), answer)
        }
    }

    // Runs on the main thread. A permission that the project or the device cannot serve answers `unsupported` with the reason, and one that needs no prompt on this version of Android answers its state at once.
    private fun check(permission: Permission, context: Context, requirements: HaylenRequirements, answer: Answer) {
        if (reportUnsupported(permission, context, requirements, answer)) {
            return
        }

        answerState(permission, context, answer)
    }

    // Runs on the main thread. A permission with a prerequisite that the app does not hold asks for the prerequisite first, which Android shows in a prompt of its own.
    private fun ask(permission: Permission, context: Context, requirements: HaylenRequirements, answer: Answer) {
        if (reportUnsupported(permission, context, requirements, answer)) {
            return
        }

        if (permission.required(context).isEmpty() || permission.isGranted(context)) {
            answerState(permission, context, answer)
            return
        }

        val prerequisite = permission.prerequisite()
        if (prerequisite != null && !prerequisite.isGranted(context)) {
            ask(prerequisite, context, requirements) { state, message, missing -> afterPrerequisite(permission, context, requirements, answer, state, message, missing) }
            return
        }

        queue.add(Request(permission, permission.requested(context, requirements), answer, context.applicationContext))
    }

    private fun answerState(permission: Permission, context: Context, answer: Answer) {
        val required = permission.required(context)
        if (required.isEmpty()) {
            answer.answer(permission.stateWithoutPrompt(context), "", emptyList())
            return
        }

        if (permission.isGranted(context)) {
            answer.answer("granted", "", emptyList())
            return
        }

        answer.answer(if (isRefused(permission, required, context)) "denied" else "prompt", "", emptyList())
    }

    // A manifest that lacks a permission comes first, since the developer fixes it on every device, and then a device without the capability.
    private fun reportUnsupported(permission: Permission, context: Context, requirements: HaylenRequirements, answer: Answer): Boolean {
        if (reportMissing(permission, context, requirements, answer)) {
            return true
        }

        val reason = permission.unsupportedReason(context) ?: return false
        answer.answer("unsupported", reason, emptyList())
        return true
    }

    // A permission that the manifest does not declare is refused without a prompt, so the answer names the lines that declare it, which the log tells once.
    private fun reportMissing(permission: Permission, context: Context, requirements: HaylenRequirements, answer: Answer): Boolean {
        val needed = permission.required(context).map { HaylenRequirements.Requirement.permission(it) }
        try {
            requirements.require(*needed.toTypedArray())
            return false
        } catch (failure: HaylenBridge.Failure) {
            val missing = ((failure.data() as? Map<*, *>)?.get("missing") as? List<*>).orEmpty().filterIsInstance<Map<*, *>>()
            answer.answer("unsupported", failure.message.orEmpty(), missing)
            return true
        }
    }

    private fun afterPrerequisite(permission: Permission, context: Context, requirements: HaylenRequirements, answer: Answer, state: String, message: String, missing: List<Map<*, *>>) {
        if (state == "granted") {
            ask(permission, context, requirements, answer)
            return
        }

        answer.answer(if (state == "unsupported") state else "denied", message, missing)
    }

    // Without an activity no prompt shows, and the request answers that its state is unknown.
    private fun showPrompt(request: Request): Boolean {
        val activity = HaylenBridge.activity()
        val prompts = launcher
        if (activity == null || prompts == null) {
            request.answer.answer("unknown", "", emptyList())
            return false
        }

        activity.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit().putBoolean(request.permission.name, true).apply()
        prompts.launch(request.asked)
        return true
    }

    // Only an activity tells whether Android still shows the prompt, so without one a permission that a request asked for counts as refused.
    private fun isRefused(permission: Permission, required: Array<String>, context: Context): Boolean {
        if (!context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).getBoolean(permission.name, false)) {
            return false
        }

        val activity = HaylenBridge.activity()
        return required.any { name ->
            context.checkSelfPermission(name) != PackageManager.PERMISSION_GRANTED && (activity == null || !activity.shouldShowRequestPermissionRationale(name))
        }
    }
}
