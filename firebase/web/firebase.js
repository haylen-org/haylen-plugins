// Web part of the Firebase plugin. It initializes the default Firebase app from the parameter `webConfig` before the runtime starts, so the web parts of the other Firebase plugins, which load after it, find the app with `getApp()` of the same module.
import { getApp, initializeApp, setLogLevel } from "https://www.gstatic.com/firebasejs/13.2.0/firebase-app.js";

const failure = (message, code) => Object.assign(new Error(message), { code });

export default function load(context) {
    const config = context.config.webConfig;
    if (!config.apiKey || !config.appId) {
        throw failure('The plugin "firebase" needs the parameter "webConfig" with the configuration object of the web app of the Firebase project, which holds "apiKey" and "appId".', "notConfigured");
    }
    initializeApp(config);
    setLogLevel("warn");

    context.register("app", () => {
        const app = getApp();
        const options = app.options;
        return { name: app.name, projectId: options.projectId, appId: options.appId, senderId: options.messagingSenderId, dataCollection: app.automaticDataCollectionEnabled };
    });

    context.register("setDataCollection", (params) => {
        getApp().automaticDataCollectionEnabled = params.enabled;
        return { enabled: params.enabled };
    });
}
