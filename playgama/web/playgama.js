// Web part of the Playgama Bridge plugin. It loads the script of the bridge and initializes it before the app starts, so the app finds the platform, the player and the storage at once. Interstitial and rewarded ads are screens, which the engine covers the app for, and they end when the bridge reports that the ad closed.
const kMessages = {
    gameReady: "game_ready",
    gameplayStarted: "gameplay_started",
    gameplayStopped: "gameplay_stopped",
    levelStarted: "level_started",
    levelCompleted: "level_completed",
    levelFailed: "level_failed",
    levelPaused: "level_paused",
    levelResumed: "level_resumed",
    inGameLoadingStarted: "in_game_loading_started",
    inGameLoadingStopped: "in_game_loading_stopped",
};

const kBannerPositions = new Set(["top", "bottom"]);

function failure(message, code) {
    return Object.assign(new Error(message), { code });
}

// The bridge rejects some promises without a reason, so the message of a failure names one only when there is one.
function reasonOf(error) {
    return error && error.message ? " " + error.message : "";
}

function loadScript(source) {
    return new Promise((resolve, reject) => {
        const script = document.createElement("script");
        script.src = source;
        script.onload = resolve;
        script.onerror = () => reject(failure(`The script of Playgama Bridge did not load from "${source}".`, "unavailable"));
        document.head.appendChild(script);
    });
}

// The interstitial and rewarded ads that the app shows, one at a time. The bridge reports each ad as states, loading, opened, rewarded for a rewarded ad, and then closed or failed, which end the screen of the ad.
class AdScreens {
    constructor(bridge) {
        this.bridge = bridge;
        this.showing = null;
        bridge.advertisement.on(bridge.EVENT_NAME.INTERSTITIAL_STATE_CHANGED, (state) => this.changed("interstitial", state));
        bridge.advertisement.on(bridge.EVENT_NAME.REWARDED_STATE_CHANGED, (state) => this.changed("rewarded", state));
    }

    // The bridge ignores an ad while another one is in progress, such as one that the platform shows on its own, so the screen fails at once instead of waiting for states that never come.
    open(kind, params, screen) {
        const advertisement = this.bridge.advertisement;
        const busy = [advertisement.interstitialState, advertisement.rewardedState].some((state) => state === "loading" || state === "opened");
        if (busy) {
            screen.reject(failure("The platform shows another ad.", "busy"));
            return;
        }

        this.showing = { kind, screen, rewarded: false };
        screen.signal.addEventListener("abort", () => this.abandon(screen));
        if (kind === "interstitial") {
            advertisement.showInterstitial(params.placement);
            return;
        }
        advertisement.showRewarded(params.placement);
    }

    abandon(screen) {
        if (this.showing && this.showing.screen === screen) {
            this.showing = null;
        }
    }

    changed(kind, state) {
        const showing = this.showing;
        if (!showing || showing.kind !== kind) {
            return;
        }

        if (state === "rewarded") {
            showing.rewarded = true;
            return;
        }

        if (state === "closed") {
            this.showing = null;
            showing.screen.resolve({ shown: true, rewarded: showing.rewarded });
            return;
        }

        if (state === "failed") {
            this.showing = null;
            showing.screen.reject(failure("The platform showed no ad.", "showFailed"));
        }
    }
}

function describePlatform(bridge) {
    return {
        id: bridge.platform.id,
        language: bridge.platform.language,
        tld: bridge.platform.tld,
        payload: bridge.platform.payload,
        audioEnabled: bridge.platform.isAudioEnabled,
        paused: bridge.platform.isPaused,
        deviceType: bridge.device.type,
        interstitialSupported: bridge.advertisement.isInterstitialSupported,
        rewardedSupported: bridge.advertisement.isRewardedSupported,
        bannerSupported: bridge.advertisement.isBannerSupported,
    };
}

function describePlayer(bridge) {
    return {
        authorizationSupported: bridge.player.isAuthorizationSupported,
        authorized: bridge.player.isAuthorized,
        guest: bridge.player.isGuest,
        id: bridge.player.id,
        name: bridge.player.name,
        photos: bridge.player.photos,
    };
}

async function sendMessage(bridge, params) {
    const message = kMessages[params.name];
    if (!message) {
        throw failure(`The message "${params.name}" is not one of ${Object.keys(kMessages).join(", ")}.`, "invalidParams");
    }

    try {
        await bridge.platform.sendMessage(message);
    } catch (error) {
        throw failure(`The platform refused the message "${params.name}".${reasonOf(error)}`, "refused");
    }
    return null;
}

async function authorizePlayer(bridge) {
    try {
        await bridge.player.authorize();
    } catch (error) {
        throw failure(`The platform did not sign the player in.${reasonOf(error)}`, "authorizationFailed");
    }
    return describePlayer(bridge);
}

function showBanner(bridge, params) {
    if (!kBannerPositions.has(params.position)) {
        throw failure(`The position "${params.position}" of a banner is "top" or "bottom".`, "invalidParams");
    }

    bridge.advertisement.showBanner(params.position, params.placement);
    return null;
}

async function storageGet(bridge, params) {
    const value = await bridge.storage.get(params.key, false);
    return { value: value ?? null };
}

async function storageSet(bridge, params) {
    await bridge.storage.set(params.key, params.value);
    return null;
}

async function storageDelete(bridge, params) {
    await bridge.storage.delete(params.key);
    return null;
}

export default async function load(context) {
    await loadScript(context.config.bridgeUrl);
    const bridge = window.bridge;
    await bridge.initialize();

    bridge.platform.on(bridge.EVENT_NAME.PAUSE_STATE_CHANGED, (paused) => context.emit("pauseChanged", { paused }));
    bridge.platform.on(bridge.EVENT_NAME.AUDIO_STATE_CHANGED, (enabled) => context.emit("audioChanged", { enabled }));
    bridge.advertisement.on(bridge.EVENT_NAME.BANNER_STATE_CHANGED, (state) => context.emit("bannerChanged", { state }));

    context.register("platform", () => describePlatform(bridge));
    context.register("player", () => describePlayer(bridge));
    context.register("authorizePlayer", () => authorizePlayer(bridge));
    context.register("sendMessage", (params) => sendMessage(bridge, params));
    context.register("showBanner", (params) => showBanner(bridge, params));
    context.register("hideBanner", () => {
        bridge.advertisement.hideBanner();
        return null;
    });
    context.register("storageGet", (params) => storageGet(bridge, params));
    context.register("storageSet", (params) => storageSet(bridge, params));
    context.register("storageDelete", (params) => storageDelete(bridge, params));

    const ads = new AdScreens(bridge);
    context.registerScreen("interstitial", (params, screen) => ads.open("interstitial", params, screen));
    context.registerScreen("rewarded", (params, screen) => ads.open("rewarded", params, screen));
}
