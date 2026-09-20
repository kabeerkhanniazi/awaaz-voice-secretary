package com.awaaz.app.awaaz_app

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/**
 * Plays the caller's voice during Patch In: PCM16 mono chunks arriving over the
 * network. Uses the voice-communication usage so Android's echo canceller treats
 * it as the far end of a call. Writes happen on a background thread because
 * AudioTrack.write blocks.
 */
class CallAudioPlayer(sampleRate: Int) {
    private val queue = LinkedBlockingQueue<ByteArray>()
    @Volatile private var running = true

    // Beyond this many queued chunks (~1 s of network backlog) the oldest audio
    // is dropped so the conversation doesn't fall behind
    private val maxQueuedChunks = 20

    private val track: AudioTrack = AudioTrack.Builder()
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
        )
        .setAudioFormat(
            AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(sampleRate)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build()
        )
        .setTransferMode(AudioTrack.MODE_STREAM)
        .setBufferSizeInBytes(
            maxOf(
                AudioTrack.getMinBufferSize(sampleRate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT),
                sampleRate * 2 / 5, // 200 ms
            )
        )
        .build()

    private val writer = Thread({
        track.play()
        while (running) {
            val chunk = queue.poll(200, TimeUnit.MILLISECONDS) ?: continue
            track.write(chunk, 0, chunk.size)
        }
    }, "awaaz-call-audio").apply { start() }

    fun feed(pcm: ByteArray) {
        if (!running) return
        while (queue.size >= maxQueuedChunks) queue.poll()
        queue.offer(pcm)
    }

    /** Drops everything not yet handed to AudioTrack (at most ~200 ms more plays). */
    fun flush() {
        queue.clear()
    }

    fun release() {
        running = false
        writer.join(500)
        try {
            track.stop()
        } catch (_: IllegalStateException) {
        }
        track.release()
    }
}
