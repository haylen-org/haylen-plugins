package com.haylen.plugins.firebasemessaging

import android.app.PendingIntent
import android.content.Intent
import android.os.Bundle
import android.util.Log
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.android.gms.tasks.Task
import com.google.firebase.FirebaseApp
import com.google.firebase.installations.FirebaseInstallations
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.RemoteMessage
import dev.haylen.HaylenActivity
import dev.haylen.HaylenBridge
import dev.haylen.HaylenLinkActivity
import dev.haylen.HaylenPlugin
import dev.haylen.HaylenPluginContext
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicInteger

// Native part of the Firebase Cloud Messaging plugin on Android. It registers the app instance with Cloud Messaging by its Firebase installation ID, which the meta-data `firebase_messaging_installation_id_enabled` of the manifest turns on. Messages reach the app as messageReceived, the taps on notifications as messageOpened, retained so the tap that launched the app waits for the first listener, and every registration of the app instance as registered. The plugin `notifications` owns the permission that the notifications need, which the app asks for with `notifications.requestPermission()` of that plugin.
class FirebaseMessagingPlugin : HaylenPlugin() {
    companion object {
        @Volatile var instance: FirebaseMessagingPlugin? = null
        private const val ACTION_OPEN = "com.haylen.plugins.firebasemessaging.OPEN"
        private const val MESSAGE_ID = "google.message_id"
        private const val TITLE = "gcm.notification.title"
        private const val BODY = "gcm.notification.body"
        private const val NOTIFICATION_TAG = "firebase-messaging"
    }

    private lateinit var context: HaylenPluginContext
    private val notifications = AtomicInteger()

    override fun onLoad(context: HaylenPluginContext) {
        this.context = context
        instance = this
        createChannel()
        registerInstance()
        registerTopics()
    }

    override fun onActivityCreated(activity: HaylenActivity, savedInstanceState: Bundle?) {
        openFrom(activity.intent)
    }

    override fun onNewIntent(intent: Intent) {
        openFrom(intent)
    }

    private fun registerInstance() {
        context.register("register") { _, reply ->
            val registering = messaging().register()
            val identified = registering.onSuccessTask { FirebaseInstallations.getInstance().id }
            answerRegistration(identified, identified, reply, "Firebase Cloud Messaging did not register the app instance: ")
        }

        // The installation ID stays the same after the app instance leaves Cloud Messaging, so the plugin reads it first.
        context.register("unregister") { _, reply ->
            val messaging = messaging()
            val identified = FirebaseInstallations.getInstance().id
            val unregistering = identified.onSuccessTask { messaging.unregister() }
            answerRegistration(unregistering, identified, reply, "Firebase Cloud Messaging did not unregister the app instance: ")
        }

        context.register("setAutoInitEnabled") { params, reply ->
            val enabled = (params as JSONObject).getBoolean("enabled")
            messaging().isAutoInitEnabled = enabled
            reply.success(JSONObject().put("enabled", enabled))
        }
    }

    private fun registerTopics() {
        context.register("subscribe") { params, reply ->
            val topic = (params as JSONObject).getString("topic")
            val subscribing = messaging().subscribeToTopic(topic)
            answer(subscribing, reply, JSONObject().put("topic", topic))
        }

        context.register("unsubscribe") { params, reply ->
            val topic = (params as JSONObject).getString("topic")
            val unsubscribing = messaging().unsubscribeFromTopic(topic)
            answer(unsubscribing, reply, JSONObject().put("topic", topic))
        }
    }

    // A tap on a notification that Firebase shows starts the app with the message in the extras, and a tap on one that the plugin posted comes through the activity of `haylen-links` with the same extras.
    private fun openFrom(intent: Intent?) {
        val extras = intent?.extras ?: return
        if (!extras.containsKey(MESSAGE_ID)) {
            return
        }

        val data = JSONObject()
        for (key in extras.keySet()) {
            if (!key.startsWith("google.") && !key.startsWith("gcm.") && key != "from" && key != "collapse_key") {
                data.put(key, extras.getString(key))
            }
        }

        val message = JSONObject().put("messageId", extras.getString(MESSAGE_ID)).put("data", data)
        extras.getString(TITLE)?.let { message.put("title", it) }
        extras.getString(BODY)?.let { message.put("body", it) }
        context.emitRetained("messageOpened", message)
        intent.removeExtra(MESSAGE_ID)
    }

    fun receive(message: RemoteMessage) {
        val data = JSONObject()
        for ((key, value) in message.data) {
            data.put(key, value)
        }

        val described = JSONObject().put("messageId", message.messageId).put("data", data)
        message.notification?.title?.let { described.put("title", it) }
        message.notification?.body?.let { described.put("body", it) }
        context.emit("messageReceived", described)

        // Android shows no notification of a message that arrives while the app is in front, so the plugin shows it when the app asks for that and the person allows notifications.
        val notification = message.notification ?: return
        val allowed = NotificationManagerCompat.from(context.application()).areNotificationsEnabled()
        if (context.config().getBoolean("showInForeground") && allowed) {
            show(notification.title, notification.body, message)
        }
    }

    fun register(installationId: String) {
        context.emitRetained("registered", JSONObject().put("installationId", installationId))
    }

    private fun show(title: String?, body: String?, message: RemoteMessage) {
        val application = context.application()
        val open = Intent(application, HaylenLinkActivity::class.java).setAction(ACTION_OPEN).putExtra(MESSAGE_ID, message.messageId).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        title?.let { open.putExtra(TITLE, it) }
        body?.let { open.putExtra(BODY, it) }
        for ((key, value) in message.data) {
            open.putExtra(key, value)
        }

        val id = notifications.incrementAndGet()
        val tap = PendingIntent.getActivity(application, id, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val channel = context.config().getString("notificationChannel")
        val builder = NotificationCompat.Builder(application, channel)
            .setSmallIcon(application.applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setContentIntent(tap)

        // A permission that the person takes back between the check and the post drops the notification, which the log tells.
        try {
            NotificationManagerCompat.from(application).notify(NOTIFICATION_TAG, id, builder.build())
        } catch (denied: SecurityException) {
            Log.w("firebase-messaging", "The notification of the message \"${message.messageId}\" was dropped, because the app lacks the permission \"android.permission.POST_NOTIFICATIONS\".", denied)
        }
    }

    private fun createChannel() {
        val channel = NotificationChannelCompat.Builder(context.config().getString("notificationChannel"), NotificationManagerCompat.IMPORTANCE_DEFAULT).setName("Messages").build()
        NotificationManagerCompat.from(context.application()).createNotificationChannel(channel)
    }

    // Cloud Messaging needs the default Firebase app, which a missing or invalid `google-services.json` leaves out.
    private fun messaging(): FirebaseMessaging {
        if (FirebaseApp.getApps(context.application()).none { it.name == FirebaseApp.DEFAULT_APP_NAME }) {
            throw HaylenBridge.Failure("Firebase is not configured, so Cloud Messaging receives nothing. Give the plugin \"firebase\" a valid \"servicesJson\".", "notConfigured", null)
        }
        return FirebaseMessaging.getInstance()
    }

    private fun answerRegistration(task: Task<*>, installationId: Task<String>, reply: HaylenBridge.Reply, failure: String) {
        task.addOnCompleteListener { completed ->
            if (!completed.isSuccessful) {
                reply.failure(failure + (completed.exception?.message ?: "no reason"), "unavailable", null)
                return@addOnCompleteListener
            }
            reply.success(JSONObject().put("installationId", installationId.result))
        }
    }

    private fun answer(task: Task<*>, reply: HaylenBridge.Reply, value: JSONObject) {
        task.addOnCompleteListener { completed ->
            if (!completed.isSuccessful) {
                reply.failure("Firebase Cloud Messaging failed: " + (completed.exception?.message ?: "no reason"), "unavailable", null)
                return@addOnCompleteListener
            }
            reply.success(value)
        }
    }
}
