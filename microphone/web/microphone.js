// Web part of the Microphone plugin: `getUserMedia` through an audio worklet as mono samples at the rate the app asks for, into an audio stream named after its rate, and the permission `microphone`, which the browser offers only to secure pages. The page imports this module before the runtime starts and calls its `load` function with the context of the plugin.
import { registerPermission, requirePermission } from "haylen-plugin:permissions";

const failure = (message, code) => Object.assign(new Error(message), { code });

// The page asks for the microphone by opening it, and closes it at once.
const requestMicrophone = async () => {
    try {
        const media = await navigator.mediaDevices.getUserMedia({ audio: true });
        media.getTracks().forEach((track) => track.stop());
        return "granted";
    } catch (error) {
        if (error.name === "NotAllowedError") {
            return "denied";
        }
        if (error.name === "NotFoundError" || error.name === "OverconstrainedError") {
            return { state: "unsupported", message: "This device has no microphone." };
        }
        return "unknown";
    }
};

export default function load(context) {
    registerPermission(context, {
        name: "microphone",
        capability: "the microphone",
        needs: { secureContext: true, api: "navigator.mediaDevices.getUserMedia", permissionsPolicy: "microphone" },
        query: "microphone",
        request: requestMicrophone,
    });

    let recording = null;

    const stop = () => {
        if (!recording) {
            return;
        }
        recording.media.getTracks().forEach((track) => track.stop());
        recording.audio.close();
        recording = null;
    };

    // Every app that loads the Lua API sends `reset`, so a recording that an earlier app of the page left running stops.
    context.register("reset", () => {
        stop();
        return null;
    });

    // The audio context records at the rate of the stream, which the browser converts the input of the device to.
    context.register("start", async (params) => {
        context.require({ api: "AudioWorkletNode" });
        await requirePermission(context, "microphone");
        stop();

        let media;
        try {
            media = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1, echoCancellation: false, noiseSuppression: false, autoGainControl: false } });
        } catch (error) {
            if (error.name === "NotFoundError" || error.name === "OverconstrainedError") {
                throw failure("This device has no microphone.", "unsupported");
            }
            throw failure(`The microphone did not start: ${error.message}`, "microphoneFailed");
        }

        const audio = new AudioContext({ sampleRate: params.sampleRate });
        await audio.audioWorklet.addModule(new URL("./microphone-worklet.js", import.meta.url));
        const name = `microphone-${params.sampleRate}`;
        const stream = context.audioStream(name, { sampleRate: params.sampleRate, channels: 1 });
        const node = new AudioWorkletNode(audio, "microphone-recording");
        node.port.onmessage = (event) => stream.push(event.data);
        audio.createMediaStreamSource(media).connect(node);
        // A browser starts an audio context only after a gesture of the person, such as the tap that started the recording, and keeps it suspended until then.
        audio.resume();

        const running = { media, audio };
        media.getAudioTracks()[0].addEventListener("ended", () => {
            if (recording === running) {
                stop();
                context.emit("stopped", { message: "The microphone went away, such as when the person unplugged it or turned it off in the browser.", code: "microphoneFailed" });
            }
        });
        recording = running;
        return { sampleRate: params.sampleRate, channels: 1, stream: name };
    });

    context.register("stop", () => {
        stop();
        return null;
    });
}
