package com.haylen.plugins.mediasession

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.util.Log
import android.view.KeyEvent
import androidx.core.content.ContextCompat
import dev.haylen.HaylenPluginContext
import org.json.JSONObject
import kotlin.math.roundToLong

// The now-playing controls of Android: a media session, which headsets, Bluetooth devices and TV remotes send their media buttons to, and the media notification that shows it in the shade and on the lock screen, where Android 13 and later draw its controls from the playback state. Notifications of a media session need no permission. While what plays shows as playing, `MediaSessionService` keeps the app in the foreground with the same notification, so Android neither freezes nor ends it in the background. The controls live on the main thread.
internal class MediaSessionControls private constructor(private val activity: Activity, private val pluginContext: HaylenPluginContext) : MediaSession.Callback() {
    companion object {
        const val NOTIFICATION = 0x4d454449
        private const val TAG = "media-session"
        private const val CHANNEL = "media-session"

        // The actions of the playback state for the names of the commands that the app offers.
        private val ACTIONS = mapOf(
            "play" to PlaybackState.ACTION_PLAY,
            "pause" to PlaybackState.ACTION_PAUSE,
            "togglePlayPause" to PlaybackState.ACTION_PLAY_PAUSE,
            "stop" to PlaybackState.ACTION_STOP,
            "next" to PlaybackState.ACTION_SKIP_TO_NEXT,
            "previous" to PlaybackState.ACTION_SKIP_TO_PREVIOUS,
            "seek" to PlaybackState.ACTION_SEEK_TO,
        )

        private var current: MediaSessionControls? = null

        // The notification shown last, which the service shows while it runs.
        var notification: Notification? = null
            private set

        // Whether the controls show what plays as playing, and whether the service keeps the app in the foreground, which it no longer should once the app paused or left the controls before the service started.
        private var playing = false
        var foreground = false
            private set

        // Whether the controls show what the app plays.
        val isShowing: Boolean
            get() = current != null

        // Shows what plays, `{title, artist, album, duration, position, playing, artwork, commands}` with the bytes of the artwork, in the controls of the activity.
        fun show(activity: Activity, pluginContext: HaylenPluginContext, track: JSONObject) {
            var controls = current
            if (controls == null || controls.activity != activity) {
                release()
                controls = MediaSessionControls(activity, pluginContext)
                current = controls
            }
            controls.show(track)
        }

        // Leaves the controls when the app takes itself out of them.
        fun release() {
            val controls = current ?: return
            playing = false
            controls.follow()
            controls.activity.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION)
            controls.session.release()
            current = null
        }

        // Leaves the controls of an activity that ends.
        fun release(activity: Activity) {
            if (current?.activity == activity) {
                release()
            }
        }

        // What the media session holds, read back from its controller, or `null` while the controls show nothing of the app.
        fun describe(): JSONObject? {
            val controller = current?.session?.controller ?: return null
            val metadata = controller.metadata
            val duration = metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L
            return JSONObject()
                .put("title", metadata?.getString(MediaMetadata.METADATA_KEY_TITLE) ?: "")
                .put("artist", metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: "")
                .put("album", metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: "")
                .put("duration", duration / 1000.0)
                .put("playing", controller.playbackState?.state == PlaybackState.STATE_PLAYING)
                .put("artwork", metadata?.getBitmap(MediaMetadata.METADATA_KEY_ART) != null)
        }
    }

    private val session = MediaSession(activity, "media-session")
    private val shownArtwork = MediaSessionArtwork()

    init {
        session.setCallback(this)
    }

    private fun show(track: JSONObject) {
        val metadata = MediaMetadata.Builder()
        metadata.putString(MediaMetadata.METADATA_KEY_TITLE, track.optString("title"))
        metadata.putString(MediaMetadata.METADATA_KEY_ARTIST, track.optString("artist"))
        metadata.putString(MediaMetadata.METADATA_KEY_ALBUM, track.optString("album"))
        val duration = (track.optDouble("duration", 0.0) * 1000.0).roundToLong()
        if (duration > 0) {
            metadata.putLong(MediaMetadata.METADATA_KEY_DURATION, duration)
        }

        val art = shownArtwork.decode(track.opt("artwork") as? ByteArray)
        if (art != null) {
            metadata.putBitmap(MediaMetadata.METADATA_KEY_ART, art)
        }

        session.setMetadata(metadata.build())

        val commands = track.optJSONObject("commands") ?: JSONObject()
        var actions = 0L
        for ((name, action) in ACTIONS) {
            if (commands.has(name)) {
                actions = actions or action
            }
        }

        val isPlaying = track.optBoolean("playing")
        val position = (track.optDouble("position", 0.0) * 1000.0).roundToLong()
        val state = PlaybackState.Builder()
        state.setActions(actions)
        state.setState(if (isPlaying) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED, position, if (isPlaying) 1.0f else 0.0f)
        session.setPlaybackState(state.build())
        session.isActive = true
        notifyShade(track, art)
    }

    // The notification opens the activity of the app when tapped, and stays while the session lives.
    private fun notifyShade(track: JSONObject, art: Bitmap?) {
        val manager = activity.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL) == null) {
            val channel = NotificationChannel(CHANNEL, pluginContext.config().optString("channelName"), NotificationManager.IMPORTANCE_LOW)
            channel.setShowBadge(false)
            manager.createNotificationChannel(channel)
        }

        val open = Intent(activity, activity.javaClass).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val content = PendingIntent.getActivity(activity, 0, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val style = Notification.MediaStyle()
        style.setMediaSession(session.sessionToken)

        val builder = Notification.Builder(activity, CHANNEL)
        builder.setSmallIcon(activity.applicationInfo.icon)
        builder.setContentTitle(track.optString("title"))
        builder.setContentText(track.optString("artist"))
        builder.setContentIntent(content)
        builder.setVisibility(Notification.VISIBILITY_PUBLIC)
        builder.setOngoing(track.optBoolean("playing"))
        builder.setStyle(style)
        if (art != null) {
            builder.setLargeIcon(art)
        }

        val shown = builder.build()
        notification = shown
        playing = track.optBoolean("playing")
        manager.notify(NOTIFICATION, shown)
        follow()
    }

    // Starts the service when what plays starts playing, and stops it when it pauses, which leaves the notification in the shade. Android lets an app start it only from the foreground or right after a command of its media session, and a refusal leaves the sound to stop once Android freezes the app in the background.
    private fun follow() {
        if (playing == foreground) {
            return
        }

        foreground = playing
        val service = Intent(activity, MediaSessionService::class.java)
        if (!playing) {
            activity.stopService(service)
            return
        }

        try {
            ContextCompat.startForegroundService(activity, service)
        } catch (refused: IllegalStateException) {
            foreground = false
            Log.w(TAG, "Android did not let the app keep its sound playing in the background, because it started playing while the app was in the background: ${refused.message}")
        }
    }

    private fun send(command: String, position: Double? = null) {
        val payload = JSONObject().put("command", command)
        if (position != null) {
            payload.put("position", position)
        }
        pluginContext.emit("command", payload)
    }

    override fun onPlay() {
        send("play")
    }

    override fun onPause() {
        send("pause")
    }

    override fun onStop() {
        send("stop")
    }

    override fun onSkipToNext() {
        send("next")
    }

    override fun onSkipToPrevious() {
        send("previous")
    }

    override fun onSeekTo(position: Long) {
        send("seek", position / 1000.0)
    }

    // A headset button that toggles arrives as one key, which Android hands to `onPlay` or `onPause` only when the app offers them, so it goes to the toggle of the app here.
    override fun onMediaButtonEvent(intent: Intent): Boolean {
        val key = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT, KeyEvent::class.java) else keyBeforeTiramisu(intent)
        if (key != null && key.action == KeyEvent.ACTION_DOWN && (key.keyCode == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE || key.keyCode == KeyEvent.KEYCODE_HEADSETHOOK)) {
            send("togglePlayPause")
            return true
        }

        return super.onMediaButtonEvent(intent)
    }

    @Suppress("DEPRECATION")
    private fun keyBeforeTiramisu(intent: Intent): KeyEvent? = intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT)
}
