package com.haylen.plugins.permissions

import android.os.Bundle
import dev.haylen.HaylenActivity
import dev.haylen.HaylenPlugin

// Native part of the Permissions plugin on Android. The `haylen` library creates it from the `meta-data` of its manifest when the app process starts, and it registers the launcher of the prompts of the permissions with every activity before the activity starts.
class PermissionsPlugin : HaylenPlugin() {
    override fun onActivityCreated(activity: HaylenActivity, savedInstanceState: Bundle?) {
        Permissions.activityCreated(activity, savedInstanceState)
    }
}
