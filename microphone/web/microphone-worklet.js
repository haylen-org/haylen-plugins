// Hands every block of the first channel of the microphone to the page, which pushes it into the audio stream of the Microphone plugin.
class MicrophoneRecording extends AudioWorkletProcessor {
    process(inputs) {
        const channel = inputs[0][0];
        if (channel) {
            this.port.postMessage(channel.slice());
        }
        return true;
    }
}

registerProcessor("microphone-recording", MicrophoneRecording);
