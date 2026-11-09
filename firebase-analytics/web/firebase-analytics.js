// Web part of the Firebase Analytics plugin. It logs into the default Firebase app that the web part of the plugin `firebase` initializes, which needs the `measurementId` of the web app in its `webConfig`.
import { getApp } from "https://www.gstatic.com/firebasejs/13.2.0/firebase-app.js";
import { getAnalytics, getGoogleAnalyticsClientId, logEvent, setAnalyticsCollectionEnabled, setConsent, setUserId, setUserProperties } from "https://www.gstatic.com/firebasejs/13.2.0/firebase-analytics.js";

const consentNames = { analyticsStorage: "analytics_storage", adStorage: "ad_storage", adUserData: "ad_user_data", adPersonalization: "ad_personalization" };

const failure = (message, code) => Object.assign(new Error(message), { code });

export default function load(context) {
    const analytics = getAnalytics(getApp());
    setAnalyticsCollectionEnabled(analytics, context.config.collectionEnabled);

    context.register("logEvent", (params) => {
        if (!params || !params.name) {
            throw failure('The method "logEvent" needs the name of the event.', "invalidParams");
        }
        logEvent(analytics, params.name, params.params || {});
        return null;
    });

    context.register("setUserId", (params) => {
        setUserId(analytics, params?.id ?? null);
        return null;
    });

    context.register("setUserProperty", (params) => {
        if (!params || !params.name) {
            throw failure('The method "setUserProperty" needs the name of the property.', "invalidParams");
        }
        setUserProperties(analytics, { [params.name]: params.value ?? null });
        return null;
    });

    context.register("setConsent", (params) => {
        const consent = {};
        for (const [key, value] of Object.entries(params || {})) {
            if (!consentNames[key] || (value !== "granted" && value !== "denied")) {
                throw failure(`The consent "${key}" takes "granted" or "denied", for analyticsStorage, adStorage, adUserData and adPersonalization.`, "invalidParams");
            }
            consent[consentNames[key]] = value;
        }
        setConsent(consent);
        return null;
    });

    context.register("setCollectionEnabled", (params) => {
        setAnalyticsCollectionEnabled(analytics, params.enabled);
        return { enabled: params.enabled };
    });

    // The web has no app instance, and the client ID of Google Analytics stands in for it.
    context.register("appInstanceId", async () => {
        const id = await getGoogleAnalyticsClientId(analytics);
        return { id };
    });

    context.register("resetAnalyticsData", () => {
        throw failure("The web keeps the data of Analytics in the cookies of the site, which the page clears itself.", "unsupported");
    });
}
