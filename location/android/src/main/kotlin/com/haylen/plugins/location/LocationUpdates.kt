package com.haylen.plugins.location

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import androidx.core.location.LocationListenerCompat
import androidx.core.location.LocationManagerCompat
import androidx.core.location.LocationRequestCompat
import dev.haylen.HaylenBridge
import org.json.JSONObject

// One fix of `LocationManager`, or every change of the location while the app watches, sent batched as the event `changed`. The fused provider of Android 12 and later joins the GPS and the network at the accuracy that the call asks for, within the precision the app holds, and earlier versions read the GPS where the app holds the precise location and the network otherwise. Android tells the altitude above the sea from version 14 on, and only above the ellipsoid of WGS 84 before, which a place leaves out.
@SuppressLint("MissingPermission")
class LocationUpdates(private val context: Context, private val emit: (String, JSONObject) -> Unit) {
    private val locations: LocationManager = context.getSystemService(LocationManager::class.java)
    private val mainThread = Handler(Looper.getMainLooper())
    private var watcher: Watcher? = null

    // Fails the fix once the timeout passes, and with the code `locationUnknown` when the provider found none. The fused provider reads the GPS only for a request of high accuracy, so a precise fix asks for it.
    fun current(precise: Boolean, timeout: Double, reply: HaylenBridge.Reply) {
        val provider = provider(precise)
        val cancel = CancellationSignal()
        val deadline = Runnable {
            cancel.cancel()
            reply.failure("No fix of the location came within ${seconds(timeout)} seconds.", "timeout", null)
        }
        reply.onCancel { cancel.cancel() }
        mainThread.postDelayed(deadline, (timeout * 1000).toLong())

        val executor = ContextCompat.getMainExecutor(context)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val request = request(precise, 0L, 0f).toLocationRequest()
            locations.getCurrentLocation(provider, request, cancel, executor) { location -> answer(location, provider, cancel, deadline, reply) }
            return
        }
        LocationManagerCompat.getCurrentLocation(locations, provider, cancel, executor) { location -> answer(location, provider, cancel, deadline, reply) }
    }

    fun watch(precise: Boolean, distance: Float) {
        val provider = provider(precise)
        stop()
        val listener = Watcher()
        LocationManagerCompat.requestLocationUpdates(locations, provider, request(precise, 1000L, distance), ContextCompat.getMainExecutor(context), listener)
        watcher = listener
    }

    fun stop() {
        val listener = watcher ?: return
        LocationManagerCompat.removeUpdates(locations, listener)
        watcher = null
    }

    private fun answer(location: Location?, provider: String, cancel: CancellationSignal, deadline: Runnable, reply: HaylenBridge.Reply) {
        mainThread.removeCallbacks(deadline)
        if (cancel.isCanceled) {
            return
        }
        if (location == null) {
            reply.failure("The location is unknown: the provider \"$provider\" found no fix.", "locationUnknown", null)
            return
        }
        reply.success(place(location))
    }

    // The request at the precision the app asks for: high accuracy reads the GPS, and the balanced one the network where it can.
    private fun request(precise: Boolean, intervalMillis: Long, distance: Float): LocationRequestCompat {
        val quality = if (precise) LocationRequestCompat.QUALITY_HIGH_ACCURACY else LocationRequestCompat.QUALITY_BALANCED_POWER_ACCURACY
        val builder = LocationRequestCompat.Builder(intervalMillis)
        builder.setQuality(quality)
        builder.setMinUpdateDistanceMeters(distance)
        return builder.build()
    }

    // The provider that reads the location at the precision the app asks for, or the code `locationOff` when the person turned the location of the device off.
    private fun provider(precise: Boolean): String {
        if (!LocationManagerCompat.isLocationEnabled(locations)) {
            throw HaylenBridge.Failure("The location of the device is turned off. The person turns it on in the settings of the system.", "locationOff", null)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && locations.hasProvider(LocationManager.FUSED_PROVIDER)) {
            return LocationManager.FUSED_PROVIDER
        }

        val fine = LocationPermissions.holds(context, Manifest.permission.ACCESS_FINE_LOCATION)
        val candidates = if (fine) listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER) else listOf(LocationManager.NETWORK_PROVIDER)
        val ordered = if (precise || !fine) candidates else candidates.reversed()
        val enabled = ordered.firstOrNull { locations.isProviderEnabled(it) }
        if (enabled == null) {
            throw HaylenBridge.Failure("This device has no provider of the location turned on that the app may read.", "locationOff", null)
        }
        return enabled
    }

    // A provider that the person turns off ends the watch.
    private inner class Watcher : LocationListenerCompat {
        override fun onLocationChanged(location: Location) {
            emit("changed", place(location))
        }

        override fun onProviderDisabled(provider: String) {
            stop()
            val stopped = JSONObject()
            stopped.put("message", "The location of the device is turned off. The person turns it on in the settings of the system.")
            stopped.put("code", "locationOff")
            emit("stopped", stopped)
        }

        override fun onProviderEnabled(provider: String) {}
    }

    private fun place(location: Location): JSONObject {
        val place = JSONObject()
        place.put("latitude", location.latitude)
        place.put("longitude", location.longitude)
        place.put("accuracy", location.accuracy.toDouble())
        place.put("timestamp", location.time / 1000.0)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE && location.hasMslAltitude()) {
            place.put("altitude", location.mslAltitudeMeters)
        }
        if (location.hasSpeed()) {
            place.put("speed", location.speed.toDouble())
        }
        if (location.hasBearing()) {
            place.put("heading", location.bearing.toDouble())
        }
        return place
    }

    private fun seconds(value: Double): String = if (value == Math.rint(value)) value.toLong().toString() else value.toString()
}
