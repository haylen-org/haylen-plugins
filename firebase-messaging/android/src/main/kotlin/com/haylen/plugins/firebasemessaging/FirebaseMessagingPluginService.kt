package com.haylen.plugins.firebasemessaging

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

// Receives the messages that reach the app while it runs and the registrations of the app instance, and hands them to the plugin, which the provider of the `haylen-plugins` library loaded when the process started.
class FirebaseMessagingPluginService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        FirebaseMessagingPlugin.instance?.receive(message)
    }

    override fun onRegistered(installationId: String) {
        FirebaseMessagingPlugin.instance?.register(installationId)
    }
}
