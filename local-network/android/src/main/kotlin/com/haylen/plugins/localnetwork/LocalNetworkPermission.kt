package com.haylen.plugins.localnetwork

import android.Manifest
import android.content.Context
import android.os.Build
import com.haylen.plugins.permissions.Permission

// The permission `localNetwork` that the plugin owns. Android 17 gates the local network of an app that targets it behind `ACCESS_LOCAL_NETWORK`, of the group of nearby devices, while earlier versions of Android and apps that target an earlier version reach the local network with `INTERNET`, so Android asks for nothing there.
class LocalNetworkPermission : Permission("localNetwork", "the local network", Manifest.permission.ACCESS_LOCAL_NETWORK) {
    override fun required(context: Context): Array<String> {
        val gated = Build.VERSION.SDK_INT >= Build.VERSION_CODES.CINNAMON_BUN && context.applicationInfo.targetSdkVersion >= Build.VERSION_CODES.CINNAMON_BUN
        return if (gated) super.required(context) else emptyArray()
    }
}
