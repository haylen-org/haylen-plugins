package com.haylen.plugins.location

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import com.haylen.plugins.permissions.Permission
import dev.haylen.HaylenRequirements

// The permissions that the plugin owns on Android: the location at the precision the person allows, the precise location of the GPS, and the location in the background, which Android asks for only after the location while the app is in use.
object LocationPermissions {
    val location: Permission = Location()
    val preciseLocation: Permission = PreciseLocation()
    val backgroundLocation: Permission = BackgroundLocation()

    fun holds(context: Context, permission: String): Boolean = context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    // The prompt offers the precise location next to the approximate one where the manifest declares it, and either one counts as granted.
    private class Location : Permission("location", "the location", Manifest.permission.ACCESS_COARSE_LOCATION) {
        override fun requested(context: Context, requirements: HaylenRequirements): Array<String> {
            val precise = requirements.hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)
            return if (precise) arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION) else required(context)
        }

        override fun isGranted(context: Context): Boolean {
            return holds(context, Manifest.permission.ACCESS_COARSE_LOCATION) || holds(context, Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }

    // Android 12 and later ask for the precise location together with the approximate one, and a person who allowed the approximate one sees a prompt that offers the precise one.
    private class PreciseLocation : Permission("preciseLocation", "the precise location", Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION) {
        override fun isGranted(context: Context): Boolean = holds(context, Manifest.permission.ACCESS_FINE_LOCATION)
    }

    // Android 10 and later ask for the location in the background in a prompt of its own, which Android 11 and later turn into a page of the settings, after the location while the app is in use. Android 9 gives the location in the background with the location.
    private class BackgroundLocation : Permission("backgroundLocation", "the location in the background", Manifest.permission.ACCESS_BACKGROUND_LOCATION) {
        override fun required(context: Context): Array<String> {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) super.required(context) else arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION)
        }

        override fun prerequisite(): Permission = location
    }
}
