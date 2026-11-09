// Web part of the Motion plugin: the `devicemotion` and `deviceorientation` events of the page, which browsers fire only in secure pages and at the rate of the device. Safari asks the person first, only during a tap or a click, and keeps the answer until the page loads again, while Chromium tells the state of the accelerometer and the gyroscope, and the other browsers ask nothing. The page listens only while the sensors run and the page shows, and sends each reading to the app as the batched event `reading`, in the axes of the device in its natural orientation with the quarter turns of the screen, which the Lua API turns into the axes of the screen.
import { registerPermission, requirePermission } from "haylen-plugin:permissions";

const failure = (message, code) => Object.assign(new Error(message), { code });

const kRadiansPerDegree = Math.PI / 180;
const kGestureMessage = "The browser asks for the motion sensors only during a tap or a click, so ask from one.";

// Safari asks through `DeviceMotionEvent.requestPermission`, whose answer lasts until the page loads again.
const gated = typeof DeviceMotionEvent !== "undefined" && typeof DeviceMotionEvent.requestPermission === "function";

const queryPermission = async (name) => {
    if (!navigator.permissions || typeof navigator.permissions.query !== "function") {
        return null;
    }
    try {
        return (await navigator.permissions.query({ name })).state;
    } catch {
        return null;
    }
};

// The attitude of the angles in degrees that browsers report, which turn the device around z by alpha, then around its new x by beta, then around its new y by gamma.
const multiply = (a, b) => [
    a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
    a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
    a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
    a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2],
];

const fromAngles = (alpha, beta, gamma) => {
    const z = (alpha * kRadiansPerDegree) / 2;
    const x = (beta * kRadiansPerDegree) / 2;
    const y = (gamma * kRadiansPerDegree) / 2;
    const aroundZ = [0, 0, Math.sin(z), Math.cos(z)];
    const aroundX = [Math.sin(x), 0, 0, Math.cos(x)];
    const aroundY = [0, Math.sin(y), 0, Math.cos(y)];
    return multiply(multiply(aroundZ, aroundX), aroundY);
};

// The angle of the screen grows as the device turns counterclockwise, which older Safari reports as `window.orientation`, with -90 for a clockwise turn.
const quarterTurns = () => {
    const angle = screen.orientation ? screen.orientation.angle : Number(window.orientation) || 0;
    return ((Math.round(angle / 90) % 4) + 4) % 4;
};

// The attitude comes from the `deviceorientation` events, and the accelerometer and the gyroscope from the `devicemotion` events.
const hasEvent = (name) => (name === "attitude" ? typeof DeviceOrientationEvent !== "undefined" : typeof DeviceMotionEvent !== "undefined");

const describeList = (names) => {
    const quoted = names.map((name) => `"${name}"`);
    return quoted.length === 1 ? quoted[0] : quoted.slice(0, -1).join(", ") + " and " + quoted[quoted.length - 1];
};

export default function load(context) {
    let permission = gated ? "prompt" : "granted";
    let askedOutsideGesture = false;
    let session = 0;
    let running = [];

    const state = async () => {
        if (gated) {
            return permission;
        }
        const queried = await Promise.all([queryPermission("accelerometer"), queryPermission("gyroscope")]);
        const states = queried.filter((value) => value !== null);
        if (states.includes("denied")) {
            return "denied";
        }
        return states.every((value) => value === "granted") ? "granted" : "prompt";
    };

    // Safari shows its prompt only during a tap or a click, and a request outside one leaves the person unasked, which answers `prompt`.
    const request = async () => {
        if (!gated) {
            return state();
        }
        try {
            const answer = await DeviceMotionEvent.requestPermission();
            permission = answer === "granted" ? "granted" : "denied";
            askedOutsideGesture = false;
        } catch (error) {
            askedOutsideGesture = error && error.name === "NotAllowedError";
        }
        return permission;
    };

    registerPermission(context, {
        name: "motion",
        capability: "the motion sensors",
        needs: { secureContext: true, permissionsPolicy: ["accelerometer", "gyroscope"] },
        unavailable: () => (typeof DeviceMotionEvent === "undefined" ? "The browser reads no motion sensors." : null),
        check: state,
        request,
    });

    const send = (sensor, values) => {
        context.emit("reading", { session, sensor, x: values[0], y: values[1], z: values[2], w: values[3], turns: quarterTurns() }, { batched: true });
    };

    // Browsers measure the push that holds the device up in meters per second squared, as the Lua API reads it, and the rotation rate in degrees per second that they name alpha, beta and gamma for the x, y and z axes.
    const onMotion = (event) => {
        const acceleration = event.accelerationIncludingGravity;
        if (running.includes("accelerometer") && acceleration && acceleration.x !== null && acceleration.y !== null && acceleration.z !== null) {
            send("accelerometer", [acceleration.x, acceleration.y, acceleration.z]);
        }
        const rate = event.rotationRate;
        if (running.includes("gyroscope") && rate && rate.alpha !== null && rate.beta !== null && rate.gamma !== null) {
            send("gyroscope", [rate.alpha * kRadiansPerDegree, rate.beta * kRadiansPerDegree, rate.gamma * kRadiansPerDegree]);
        }
    };

    const onOrientation = (event) => {
        if (event.alpha !== null && event.beta !== null && event.gamma !== null) {
            send("attitude", fromAngles(event.alpha, event.beta, event.gamma));
        }
    };

    const listen = (on) => {
        const change = on ? window.addEventListener : window.removeEventListener;
        if (running.includes("accelerometer") || running.includes("gyroscope")) {
            change.call(window, "devicemotion", onMotion);
        }
        if (running.includes("attitude")) {
            change.call(window, "deviceorientation", onOrientation);
        }
    };

    const stop = () => {
        listen(false);
        running = [];
    };

    // A hidden page gets no readings, so the page stops listening until it shows again.
    document.addEventListener("visibilitychange", () => {
        if (running.length > 0) {
            listen(document.visibilityState === "visible");
        }
    });

    // The watch of a session never resolves, and it rejects once the app gives it up, which stops the sensors of the session.
    const waitForAbort = (watched, signal) => new Promise((resolve, reject) => {
        const aborted = () => {
            if (session === watched) {
                stop();
                session = 0;
            }
            reject(failure("The app stopped the motion sensors.", "cancelled"));
        };
        signal.addEventListener("abort", aborted);
    });

    // The app holds the watch of a session while its sensors run, and gives it up to stop them, which the end of the app does too.
    context.register("watch", (params, { signal }) => {
        session = params.session;
        return waitForAbort(params.session, signal);
    });

    context.register("start", async (params) => {
        const absent = params.sensors.filter((name) => !hasEvent(name));
        if (absent.length > 0) {
            throw failure(`The browser has no motion ${absent.length === 1 ? "sensor" : "sensors"} ${describeList(absent)}.`, "unsupported");
        }

        try {
            await requirePermission(context, "motion");
        } catch (error) {
            if (error.code === "denied" && askedOutsideGesture) {
                throw failure(kGestureMessage, "failed");
            }
            throw error;
        }
        if (session !== params.session) {
            throw failure("The app stopped the motion sensors before they started.", "cancelled");
        }

        stop();
        running = params.sensors.slice();
        if (document.visibilityState === "visible") {
            listen(true);
        }
        return { sensors: params.sensors };
    });
}
