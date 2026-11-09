// Web part of the Google Analytics plugin. It loads gtag.js with the measurement ID of the app before the app starts and sends the events of the app to the property of that data stream.
const kConsentNames = { analyticsStorage: "analytics_storage", adStorage: "ad_storage", adUserData: "ad_user_data", adPersonalization: "ad_personalization" };

const kConsentStates = new Set(["granted", "denied"]);

function failure(message, code) {
    return Object.assign(new Error(message), { code });
}

// The queue of gtag.js, which keeps the commands that come before the script loads and runs them once it does.
function gtag() {
    window.dataLayer.push(arguments);
}

// Resolves once gtag.js loaded, and rejects when the page cannot load it, such as behind a blocker of trackers, so every call fails with the code `unavailable` instead of keeping events that never leave the page.
function loadScript(id) {
    return new Promise((resolve, reject) => {
        const script = document.createElement("script");
        script.async = true;
        script.src = "https://www.googletagmanager.com/gtag/js?id=" + encodeURIComponent(id);
        script.onload = resolve;
        script.onerror = () => reject(failure("The page could not load gtag.js of Google Analytics, so it sends no events.", "unavailable"));
        document.head.appendChild(script);
    });
}

function consentOf(params) {
    const consent = {};
    for (const [key, value] of Object.entries(params || {})) {
        if (!kConsentNames[key] || !kConsentStates.has(value)) {
            throw failure(`The consent "${key}" takes "granted" or "denied", for analyticsStorage, adStorage, adUserData and adPersonalization.`, "invalidParams");
        }
        consent[kConsentNames[key]] = value;
    }
    return consent;
}

function clientId(id) {
    return new Promise((resolve) => gtag("get", id, "client_id", (value) => resolve({ id: value || null })));
}

export default function load(context) {
    const id = context.config.measurementId;
    const initial = context.config.consentDefault;
    if (!kConsentStates.has(initial)) {
        throw new Error(`The parameter "consentDefault" of the plugin "google-analytics" is "granted" or "denied", not "${initial}".`);
    }

    window.dataLayer = window.dataLayer || [];
    gtag("consent", "default", { analytics_storage: initial, ad_storage: initial, ad_user_data: initial, ad_personalization: initial });
    gtag("js", new Date());
    gtag("config", id);
    const loaded = loadScript(id);
    loaded.catch((error) => console.warn(error.message));

    context.register("logEvent", async (params) => {
        if (!params.name) {
            throw failure('The method "logEvent" needs the name of the event.', "invalidParams");
        }
        await loaded;
        gtag("event", params.name, params.params || {});
        return null;
    });
    context.register("setUserId", async (params) => {
        await loaded;
        gtag("set", { user_id: params.id || null });
        return null;
    });
    context.register("setUserProperties", async (params) => {
        await loaded;
        gtag("set", "user_properties", params);
        return null;
    });
    context.register("setConsent", async (params) => {
        const consent = consentOf(params);
        await loaded;
        gtag("consent", "update", consent);
        return null;
    });
    context.register("clientId", async () => {
        await loaded;
        return clientId(id);
    });
}
