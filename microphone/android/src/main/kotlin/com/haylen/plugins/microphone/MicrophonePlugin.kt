package com.haylen.plugins.microphone

import android.Manifest
import android.annotation.SuppressLint
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import com.haylen.plugins.permissions.Permission
import com.haylen.plugins.permissions.Permissions
import dev.haylen.HaylenAudioStream
import dev.haylen.HaylenBridge
import dev.haylen.HaylenPlugin
import dev.haylen.HaylenPluginContext
import org.json.JSONObject

// Native part of the Microphone plugin on Android: `AudioRecord` as mono floats at the rate the app asks for, into an audio stream named after its rate, and the permission `microphone`. The `haylen` library creates it from the `meta-data` of its manifest, and loads it when the app process starts.
class MicrophonePlugin : HaylenPlugin() {
    private lateinit var context: HaylenPluginContext
    private var recording: Recording? = null

    override fun onLoad(context: HaylenPluginContext) {
        this.context = context
        Permissions.register(context, Permission("microphone", "the microphone", Manifest.permission.RECORD_AUDIO))

        // Every app that loads the Lua API sends `reset`, so a recording that an earlier app of the process left running stops.
        context.register("reset") { _, reply ->
            stopRecording()
            reply.success(null)
        }

        context.register("start") { params, reply ->
            val sampleRate = (params as JSONObject).getInt("sampleRate")
            if (!context.application().packageManager.hasSystemFeature(PackageManager.FEATURE_MICROPHONE)) {
                throw HaylenBridge.Failure("This device has no microphone.", "unsupported", null)
            }
            Permissions.require(context, "microphone", reply) { start(sampleRate, reply) }
        }

        context.register("stop") { _, reply ->
            stopRecording()
            reply.success(null)
        }
    }

    private fun start(sampleRate: Int, reply: HaylenBridge.Reply) {
        stopRecording()
        val record = Recording.open(sampleRate) ?: throw HaylenBridge.Failure("The microphone of this device does not record mono samples at $sampleRate Hz.", "microphoneFailed", null)
        val name = "microphone-$sampleRate"
        val stream = context.openAudioStream(name, sampleRate, 1, HaylenAudioStream.Format.FLOAT32, sampleRate)
        recording = Recording(record, stream, sampleRate) { message ->
            context.emit("stopped", JSONObject().put("message", message).put("code", "microphoneFailed"))
        }
        reply.success(JSONObject().put("sampleRate", sampleRate).put("channels", 1).put("stream", name))
    }

    private fun stopRecording() {
        recording?.stop()
        recording = null
    }

    // The recording of `AudioRecord`, whose mono floats a thread of its own reads in blocks of a hundredth of a second and pushes into the stream. A read that fails, such as when the audio system takes the input away, ends the thread and calls `failed` with the reason.
    private class Recording(private val record: AudioRecord, private val stream: HaylenAudioStream, sampleRate: Int, private val failed: (String) -> Unit) {
        @Volatile
        private var running = true

        private val thread = Thread({ read(sampleRate) }, "microphone-recording")

        init {
            thread.start()
        }

        // A read returns within a hundredth of a second, so the thread ends at once and the next recording finds the microphone free.
        fun stop() {
            running = false
            thread.join()
        }

        private fun read(sampleRate: Int) {
            val block = FloatArray(sampleRate / 100)
            record.startRecording()
            while (running) {
                val frames = record.read(block, 0, block.size, AudioRecord.READ_BLOCKING)
                if (frames < 0) {
                    val reason = "The microphone stopped with the error $frames of AudioRecord."
                    Log.w("microphone", reason)
                    failed(reason)
                    break
                }
                stream.push(block, frames)
            }
            record.stop()
            record.release()
        }

        companion object {
            // Returns a recorder of the microphone at the rate, or nothing when the device does not record at it, such as an emulator without audio input.
            @SuppressLint("MissingPermission")
            fun open(sampleRate: Int): AudioRecord? {
                val minimum = AudioRecord.getMinBufferSize(sampleRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_FLOAT)
                if (minimum <= 0) {
                    return null
                }
                val record = AudioRecord(MediaRecorder.AudioSource.MIC, sampleRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_FLOAT, maxOf(minimum, sampleRate / 5 * 4))
                if (record.state == AudioRecord.STATE_INITIALIZED) {
                    return record
                }
                record.release()
                return null
            }
        }
    }
}
