// The service worker of the Firebase Cloud Messaging plugin, which shows the notifications of the messages that arrive while no page of the site is in front. The page registers it with the configuration of the Firebase web app in its address.
importScripts("https://www.gstatic.com/firebasejs/13.2.0/firebase-app-compat.js", "https://www.gstatic.com/firebasejs/13.2.0/firebase-messaging-compat.js");

const config = JSON.parse(new URL(self.location.href).searchParams.get("config"));
firebase.initializeApp(config);
firebase.messaging();
