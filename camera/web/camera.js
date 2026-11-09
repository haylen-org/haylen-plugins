// Web part of the Camera plugin: `getUserMedia` into the video stream `camera`, photos as JPEG bytes and the permission `camera`, which the browser offers only to secure pages. The page imports this module before the runtime starts and calls its `load` function with the context of the plugin.
import { registerPermission, requirePermission } from "haylen-plugin:permissions";

const failure = (message, code) => Object.assign(new Error(message), { code });

const kFacingModes = { front: "user", back: "environment" };

// The page asks for the camera by opening it, and closes it at once.
const requestCamera = async () => {
    try {
        const media = await navigator.mediaDevices.getUserMedia({ video: true });
        media.getTracks().forEach((track) => track.stop());
        return "granted";
    } catch (error) {
        if (error.name === "NotAllowedError") {
            return "denied";
        }
        if (error.name === "NotFoundError" || error.name === "OverconstrainedError") {
            return { state: "unsupported", message: "This device has no camera." };
        }
        return "unknown";
    }
};

// Browsers tell the way a camera faces through the capabilities of its device where they know it, and a camera that faces neither way counts as external.
const facingOf = (device) => {
    const modes = typeof device.getCapabilities === "function" ? device.getCapabilities().facingMode || [] : [];
    if (modes.includes("user")) {
        return "front";
    }
    if (modes.includes("environment")) {
        return "back";
    }
    return "external";
};

// The browser names the cameras only once the page holds the permission, which the plugin asks for first.
const listCameras = async () => {
    const devices = await navigator.mediaDevices.enumerateDevices();
    const cameras = devices.filter((device) => device.kind === "videoinput");
    return cameras.map((device) => ({ id: device.deviceId, name: device.label, facing: facingOf(device) }));
};

// The constraints of the camera that the app asks for by its id, by the way it faces or the default camera of the browser, at the size closest to the one it asks for.
const constraintsFor = async (params) => {
    const video = { width: { ideal: params.width }, height: { ideal: params.height } };
    if (params.camera) {
        return { ...video, deviceId: { exact: params.camera } };
    }
    if (params.facing === "external") {
        const external = (await listCameras()).find((camera) => camera.facing === "external");
        if (!external) {
            throw failure('This device has no camera that faces "external".', "noCamera");
        }
        return { ...video, deviceId: { exact: external.id } };
    }
    if (params.facing) {
        return { ...video, facingMode: { exact: kFacingModes[params.facing] } };
    }
    return video;
};

const describeMissing = (params) => {
    if (params.camera) {
        return `This device has no camera with the id "${params.camera}". The function "camera.cameras" lists the cameras.`;
    }
    return params.facing ? `This device has no camera that faces "${params.facing}".` : "This device has no camera.";
};

// Draws the frame of the front camera mirrored, like the camera apps of phones show it.
const mirrored = (running) => {
    const { video } = running;
    if (!running.canvas || running.canvas.width !== video.videoWidth || running.canvas.height !== video.videoHeight) {
        running.canvas = new OffscreenCanvas(video.videoWidth, video.videoHeight);
        running.drawing = running.canvas.getContext("2d");
    }
    running.drawing.setTransform(-1, 0, 0, 1, video.videoWidth, 0);
    running.drawing.drawImage(video, 0, 0);
    return running.canvas;
};

// Pushes the frame of the video into the stream and waits for the next one, while the capture runs.
const pushFrames = (stream, running) => {
    if (!running.running) {
        return;
    }
    if (running.video.readyState >= running.video.HAVE_CURRENT_DATA) {
        stream.push(running.mirror ? mirrored(running) : running.video);
    }
    const next = () => pushFrames(stream, running);
    if (typeof running.video.requestVideoFrameCallback === "function") {
        running.video.requestVideoFrameCallback(next);
    } else {
        requestAnimationFrame(next);
    }
};

export default function load(context) {
    registerPermission(context, {
        name: "camera",
        capability: "the camera",
        needs: { secureContext: true, api: "navigator.mediaDevices.getUserMedia", permissionsPolicy: "camera" },
        query: "camera",
        request: requestCamera,
    });

    const stream = context.videoStream("camera");
    let capture = null;
    // Counts the starts, stops and resets, so a start that awaits the permission or the camera learns that a later call took its place.
    let requests = 0;

    const requireCurrent = (request, media) => {
        if (request === requests) {
            return;
        }
        if (media) {
            media.getTracks().forEach((track) => track.stop());
        }
        throw failure("The camera stopped or started again before this start ended.", "cancelled");
    };

    const stop = () => {
        if (!capture) {
            return;
        }
        capture.running = false;
        capture.media.getTracks().forEach((track) => track.stop());
        capture = null;
    };

    // Every app that loads the Lua API sends `reset`, so a capture that an earlier app of the page left running stops.
    context.register("reset", () => {
        requests += 1;
        stop();
        return null;
    });

    context.register("cameras", async () => {
        await requirePermission(context, "camera");
        return listCameras();
    });

    context.register("start", async (params) => {
        requests += 1;
        const request = requests;
        await requirePermission(context, "camera");
        const constraints = await constraintsFor(params);
        requireCurrent(request, null);
        stop();

        let media;
        try {
            media = await navigator.mediaDevices.getUserMedia({ video: constraints });
        } catch (error) {
            if (error.name === "OverconstrainedError" || error.name === "NotFoundError") {
                throw failure(describeMissing(params), "noCamera");
            }
            throw failure(`The camera did not start: ${error.message}`, "cameraFailed");
        }

        const track = media.getVideoTracks()[0];
        const settings = track.getSettings();
        const video = document.createElement("video");
        video.muted = true;
        video.playsInline = true;
        video.srcObject = media;
        await video.play();
        requireCurrent(request, media);

        const running = { media, video, running: true, mirror: settings.facingMode === "user", canvas: null, drawing: null };
        track.addEventListener("ended", () => {
            if (capture === running) {
                stop();
                context.emit("stopped", { message: "The camera went away, such as when the person unplugged it or turned it off in the browser.", code: "cameraFailed" });
            }
        });
        capture = running;
        pushFrames(stream, running);
        const device = (await listCameras()).find((camera) => camera.id === settings.deviceId);
        return { id: settings.deviceId || "", name: track.label, facing: device ? device.facing : "external", width: video.videoWidth, height: video.videoHeight };
    });

    context.register("stop", () => {
        requests += 1;
        stop();
        return null;
    });

    context.register("takePhoto", async () => {
        if (!capture) {
            throw failure('The camera is off. Call "camera.start" first.', "cameraOff");
        }
        const { video } = capture;
        if (video.videoWidth === 0) {
            throw failure("The camera has no frame yet.", "noFrame");
        }
        const canvas = new OffscreenCanvas(video.videoWidth, video.videoHeight);
        canvas.getContext("2d").drawImage(capture.mirror ? mirrored(capture) : video, 0, 0);
        const blob = await canvas.convertToBlob({ type: "image/jpeg", quality: 0.85 });
        return { jpeg: new Uint8Array(await blob.arrayBuffer()), width: canvas.width, height: canvas.height };
    });
}
