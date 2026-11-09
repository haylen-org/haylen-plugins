// Web part of the Firebase Cloud Messaging plugin. It registers the app instance with Cloud Messaging by its Firebase installation ID, and the service worker next to this module, which shows the notifications of messages that arrive in the background, and hands the messages that arrive while the page is in front to the app as messageReceived. The web push certificate of the Firebase project, the parameter `vapidKey`, signs the subscriptions of the page. The plugin `notifications` owns the permission that the registration needs, so the app asks for it with `notifications.requestPermission()` of that plugin.
import { getApp } from "https://www.gstatic.com/firebasejs/13.2.0/firebase-app.js";
import { getMessaging, isSupported, onMessage, onRegistered, onUnregistered, register, unregister } from "https://www.gstatic.com/firebasejs/13.2.0/firebase-messaging.js";

const failure = (message, code) => Object.assign(new Error(message), { code });

const describe = (payload) => ({ messageId: payload.messageId, title: payload.notification?.title, body: payload.notification?.body, data: payload.data || {} });

// A page that cannot register the worker, such as one without a secure context, runs the app without messages, and the calls tell why.
async function start(context) {
    if (!(await isSupported())) {
        return null;
    }

    try {
        const worker = new URL("firebase-messaging-sw.js", import.meta.url);
        worker.searchParams.set("config", JSON.stringify(getApp().options));
        const scope = new URL("./", import.meta.url).pathname;
        const registration = await navigator.serviceWorker.register(worker.href, { scope });
        const messaging = getMessaging(getApp());
        onMessage(messaging, (payload) => context.emit("messageReceived", describe(payload)));
        return { messaging, registration };
    } catch (error) {
        console.warn('The plugin "firebase-messaging" could not register its service worker, so the app receives no messages: ' + error.message);
        return null;
    }
}

export default async function load(context) {
    const started = await start(context);

    const requireMessaging = () => {
        context.require({ secureContext: true, api: ["Notification", "navigator.serviceWorker", "PushManager"] });
        if (!started) {
            throw failure("This browser cannot receive the messages of Firebase Cloud Messaging.", "unsupported");
        }
        return started;
    };

    // The SDK hands the installation ID of each registration and unregistration to its handlers before the call ends.
    let installationId = null;
    if (started) {
        onRegistered(started.messaging, (id) => {
            installationId = id;
            context.emit("registered", { installationId: id }, { retain: true });
        });
        onUnregistered(started.messaging, (id) => {
            installationId = id;
        });
    }

    // The registration of the web needs the permission of notifications, and the SDK would show the prompt itself, so the plugin asks the app to ask first.
    context.register("register", async () => {
        const { messaging, registration } = requireMessaging();
        if (Notification.permission !== "granted") {
            throw failure("The person has not allowed notifications, which the registration of the web needs. Ask for them with \"notifications.requestPermission('notifications')\", which shows the prompt of the browser while the browser still asks, or the person allows them in the settings of the site.", "denied");
        }

        try {
            await register(messaging, { vapidKey: context.config.vapidKey, serviceWorkerRegistration: registration });
            return { installationId };
        } catch (error) {
            throw failure("Firebase Cloud Messaging did not register the app instance: " + error.message, "unavailable");
        }
    });

    context.register("unregister", async () => {
        const { messaging } = requireMessaging();
        try {
            await unregister(messaging);
            return { installationId };
        } catch (error) {
            throw failure("Firebase Cloud Messaging did not unregister the app instance: " + error.message, "unavailable");
        }
    });

    // The web SDK of Firebase offers no topics, so the server of the app subscribes the app instance with the Admin SDK of Firebase.
    for (const method of ["subscribe", "unsubscribe"]) {
        context.register(method, () => {
            throw failure("The web subscribes the app instance to topics from the server of the app, with the Admin SDK of Firebase.", "unsupported");
        });
    }

    // The web SDK registers only when the app asks, so it has no registration that it makes on its own.
    context.register("setAutoInitEnabled", () => {
        throw failure("The web registers the app instance only when the app calls \"register\", so it has no registration that it makes on its own.", "unsupported");
    });
}
