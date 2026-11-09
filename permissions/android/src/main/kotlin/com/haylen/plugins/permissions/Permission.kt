package com.haylen.plugins.permissions

import android.content.Context
import android.content.pm.PackageManager
import dev.haylen.HaylenRequirements

// A permission that a plugin owns, such as `camera`, as a set of permissions of the manifest that the prompt of the system asks the person for. A plugin declares the permission in the `permissions` of its `plugin.json`, registers it with `Permissions.register` and overrides what differs from the default: why the device lacks the capability, the permissions of the manifest it needs on the Android that runs, what its prompt asks for, whether the app holds it, its state where Android asks for nothing and a permission the person must grant first.
open class Permission(
    // The name that the app checks and asks for, such as `camera`.
    val name: String,
    // What the permission gives the app in words, such as `the camera`, for the sentences of answers.
    val capability: String,
    // The permissions of the manifest that it needs, such as `android.permission.CAMERA`.
    vararg required: String,
) {
    private val permissions: Array<String> = arrayOf(*required)

    // The sentence that says why the device lacks the capability, such as `The device has no motion sensors.`, or `null` where it has it. A permission with a reason answers `unsupported` with it and never shows a prompt.
    open fun unsupportedReason(context: Context): String? = null

    // The permissions of the manifest that it needs on the Android that runs, empty where Android asks for nothing.
    open fun required(context: Context): Array<String> = permissions.copyOf()

    // What the prompt asks for, such as the precise location next to the approximate one where the manifest declares it, so the prompt offers the choice.
    open fun requested(context: Context, requirements: HaylenRequirements): Array<String> = required(context)

    open fun isGranted(context: Context): Boolean {
        return required(context).all { context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
    }

    // The state where `required` is empty, `granted` or `denied`, such as notifications before Android 13, which the person may turn off in the settings. A device without the capability answers through `unsupportedReason` instead.
    open fun stateWithoutPrompt(context: Context): String = "granted"

    // A permission the person must grant first, which Android asks for in a prompt of its own, such as the location before the location in the background, or `null`.
    open fun prerequisite(): Permission? = null
}
