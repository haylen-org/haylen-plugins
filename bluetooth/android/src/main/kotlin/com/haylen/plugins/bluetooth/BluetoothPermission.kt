package com.haylen.plugins.bluetooth

import android.Manifest
import android.content.Context
import android.os.Build
import com.haylen.plugins.permissions.Permission

// The permission `bluetooth`: the nearby devices of Android 12 and later, which scanning and connecting need, and before Android 12 the precise location, without which a scan finds nothing. The manifest of the plugin declares the scan with `neverForLocation`, so Android 12 and later never derive a location from it.
class BluetoothPermission : Permission("bluetooth", "Bluetooth") {
    override fun required(context: Context): Array<String> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        }
        return arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
    }
}
