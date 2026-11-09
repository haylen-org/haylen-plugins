// Web part of the Location plugin: one fix of `navigator.geolocation`, or every change while the app watches, sent batched as the event `changed`, and the permissions `location`, `preciseLocation` and `backgroundLocation`, which the browser offers only to secure pages. The page imports this module before the runtime starts and calls its `load` function with the context of the plugin, after the module of the Permissions plugin, which registers and asks for the permissions.
import { registerPermission, requirePermission } from "haylen-plugin:permissions";

const failure = (message, code) => Object.assign(new Error(message), { code });

const kRequestMilliseconds = 30000;
const kForegroundOnly = "A page reads the location only while it shows.";
const kRefusal = "The person has not allowed the location. Ask for it with \"location.requestPermission('location')\", which shows the prompt of the system while the system still asks, or the person allows it in the settings of the system.";

// Browsers measure the altitude above the ellipsoid of WGS 84 and not above the sea, so a place leaves it out.
const place = (position) => {
    const { coords } = position;
    const answer = { latitude: coords.latitude, longitude: coords.longitude, accuracy: coords.accuracy, timestamp: position.timestamp / 1000 };
    if (coords.speed !== null && !Number.isNaN(coords.speed)) {
        answer.speed = coords.speed;
    }
    if (coords.heading !== null && !Number.isNaN(coords.heading)) {
        answer.heading = coords.heading;
    }
    return answer;
};

const failed = (error) => {
    if (error.code === error.PERMISSION_DENIED) {
        return failure(kRefusal, "denied");
    }
    return failure(`The location is unknown: ${error.message}`, "locationUnknown");
};

// A fix that may come from the cache asks the person, and a fix that does not come in time leaves the state unknown, since the person may still answer.
const requestLocation = () => new Promise((resolve) => {
    const allowed = () => resolve("granted");
    const refused = (error) => resolve(error.code === error.PERMISSION_DENIED ? "denied" : "unknown");
    navigator.geolocation.getCurrentPosition(allowed, refused, { maximumAge: Infinity, timeout: kRequestMilliseconds });
});

// Reads one fix, which fails with the code `timeout` once the seconds of the call pass without one.
const currentPlace = (precise, timeout) => new Promise((resolve, reject) => {
    const located = (position) => resolve(place(position));
    const missed = (error) => reject(error.code === error.TIMEOUT ? failure(`No fix of the location came within ${timeout} seconds.`, "timeout") : failed(error));
    navigator.geolocation.getCurrentPosition(located, missed, { enableHighAccuracy: precise, timeout: timeout * 1000 });
});

// The distance in meters along the surface of the Earth, with the formula of the haversine.
const distanceBetween = (from, to) => {
    const kEarthRadius = 6371000;
    const radians = Math.PI / 180;
    const latitude = (to.latitude - from.latitude) * radians;
    const longitude = (to.longitude - from.longitude) * radians;
    const haversine = Math.sin(latitude / 2) ** 2 + Math.cos(from.latitude * radians) * Math.cos(to.latitude * radians) * Math.sin(longitude / 2) ** 2;
    return 2 * kEarthRadius * Math.asin(Math.sqrt(haversine));
};

export default function load(context) {
    const needs = { secureContext: true, api: "navigator.geolocation", permissionsPolicy: "geolocation" };

    registerPermission(context, { name: "location", capability: "the location", needs, query: "geolocation", request: requestLocation });
    // A browser offers one location, whose precision it decides, so the precise location is the location.
    registerPermission(context, { name: "preciseLocation", capability: "the precise location", needs, query: "geolocation", request: requestLocation });
    registerPermission(context, {
        name: "backgroundLocation",
        capability: "the location in the background",
        check: () => ({ state: "unsupported", message: kForegroundOnly }),
        request: () => ({ state: "unsupported", message: kForegroundOnly }),
    });

    let watch = null;

    const stop = () => {
        if (watch !== null) {
            navigator.geolocation.clearWatch(watch);
            watch = null;
        }
    };

    // Every app that loads the Lua API sends `reset`, so updates that an earlier app of the page left running stop.
    context.register("reset", () => {
        stop();
        return null;
    });

    context.register("current", async (params) => {
        await requirePermission(context, params.precise ? "preciseLocation" : "location");
        return currentPlace(params.precise, params.timeout);
    });

    // The browser has no distance between updates, so the page sends a place only once it lies the distance away from the last one it sent.
    context.register("watch", async (params) => {
        if (params.background) {
            throw failure(kForegroundOnly, "unsupported");
        }

        await requirePermission(context, params.precise ? "preciseLocation" : "location");
        stop();

        let last = null;
        const changed = (position) => {
            const next = place(position);
            if (last && distanceBetween(last, next) < params.distance) {
                return;
            }
            last = next;
            context.emit("changed", next, { batched: true });
        };

        const ended = (error) => {
            if (error.code !== error.PERMISSION_DENIED) {
                return;
            }
            stop();
            context.emit("stopped", { message: kRefusal, code: "denied" });
        };

        watch = navigator.geolocation.watchPosition(changed, ended, { enableHighAccuracy: params.precise });
        return null;
    });

    context.register("stop", () => {
        stop();
        return null;
    });
}
