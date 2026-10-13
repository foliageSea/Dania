package com.foliage.dania.toolbox

import android.content.Context
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.os.Build
import android.os.Handler
import io.flutter.view.TextureRegistry
import io.github.muntashirakon.adb.AdbStream
import java.io.Closeable
import java.io.DataInputStream
import java.util.UUID
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

class ScrcpySession(
    val mirrorId: String,
    private val context: Context,
    private val adb: AdbBackend,
    private val producer: TextureRegistry.SurfaceProducer,
    private val main: Handler,
    private val emit: (Map<String, Any?>) -> Unit,
) : Closeable {
    private val stopped = AtomicBoolean(false)
    private val streams = java.util.concurrent.CopyOnWriteArrayList<AdbStream>()
    private val controls = Executors.newSingleThreadExecutor()
    private val codecLock = Any()
    private var codec: MediaCodec? = null
    private var video: AdbStream? = null
    private var control: AdbStream? = null
    private var controlOutput: java.io.OutputStream? = null
    private var decoderThread: Thread? = null
    private var drainThread: Thread? = null
    private var width = 0
    private var height = 0
    private var rendered = false
    private val remoteJar = "/data/local/tmp/dania-scrcpy-${UUID.randomUUID()}.jar"

    private fun remember(stream: AdbStream): AdbStream {
        streams.add(stream)
        if (stopped.get()) { stream.close(); throw IllegalStateException("Mirroring stopped") }
        return stream
    }

    fun start(maxSize: Int, bitRate: Int): Map<String, Any> {
        require(maxSize in 320..2560 && bitRate in 500000..20000000)
        check(!stopped.get())
        AdbSync(remember(adb.openStream("sync:"))).use { sync ->
            context.assets.open("scrcpy-server-v5.0.1").use { sync.push(remoteJar, it) {} }
        }
        val scid = Protocols.scrcpyId(java.security.SecureRandom().nextInt(Int.MAX_VALUE))
        val socket = "scrcpy_$scid"
        val process = remember(adb.command(
            "CLASSPATH=${Protocols.quote(remoteJar)} app_process / com.genymobile.scrcpy.Server 5.0.1 " +
                "scid=$scid tunnel_forward=true audio=false control=true video_codec=h264 " +
                "max_size=$maxSize video_bit_rate=$bitRate max_fps=60 clipboard_autosync=false cleanup=true"))
        thread(name = "scrcpy-server") {
            runCatching { Protocols.readShell(process.openInputStream()) { _, _ -> } }
        }
        video = connect(socket)
        val input = DataInputStream(video!!.openInputStream())
        // The server waits for both sockets before sending the device metadata.
        control = connect(socket)
        controlOutput = control!!.openOutputStream()
        check(input.readUnsignedByte() == 0) { "Invalid scrcpy handshake" }
        val name = String(Protocols.readExactly(input, 64), Charsets.UTF_8).trimEnd('\u0000')
        check(input.readInt() == 0x68323634) { "H.264 stream unavailable" }
        val session = Protocols.videoPacket(input)
        check(session.width > 0) { "Missing scrcpy session header" }
        configure(session.width, session.height)

        drainThread = thread(name = "scrcpy-render") {
            val info = MediaCodec.BufferInfo()
            try {
                while (!stopped.get()) {
                    val available = synchronized(codecLock) {
                        codec?.let { decoder ->
                            val drained = VideoOutput.drain(
                                { decoder.dequeueOutputBuffer(info, 0) },
                                { index, render -> decoder.releaseOutputBuffer(index, render) },
                            )
                            if (drained) {
                                if (!rendered) {
                                    rendered = true
                                    emit(mapOf("type" to "mirror", "state" to "playing"))
                                }
                            }
                            drained
                        } ?: false
                    }
                    if (!available) Thread.sleep(1)
                }
            } catch (e: Exception) { fail(e) }
        }
        decoderThread = thread(name = "scrcpy-decode") {
            try {
                while (!stopped.get()) {
                    val packet = Protocols.videoPacket(input)
                    if (packet.width > 0) configure(packet.width, packet.height)
                    else feed(packet)
                }
            } catch (e: Exception) { fail(e) }
        }
        thread(name = "scrcpy-device-messages") {
            runCatching { control!!.openInputStream().use { stream ->
                val discard = ByteArray(4096)
                while (!stopped.get() && stream.read(discard) >= 0) { }
            } }
        }
        return mapOf("textureId" to producer.id(), "width" to width, "height" to height, "name" to name)
    }

    private fun connect(socket: String): AdbStream {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(15)
        var last: Exception? = null
        while (!stopped.get() && System.nanoTime() < deadline) {
            try { return remember(adb.openStream("localabstract:$socket")) }
            catch (e: Exception) { last = e; Thread.sleep(100) }
        }
        throw IllegalStateException("scrcpy server connection timed out", last)
    }

    private fun configure(w: Int, h: Int) {
        check(!stopped.get())
        val surface = CompletableFuture<android.view.Surface>()
        main.post {
            if (stopped.get()) surface.completeExceptionally(IllegalStateException("Mirroring stopped"))
            else runCatching { producer.setSize(w, h); producer.surface }
                .onSuccess { surface.complete(it) }.onFailure { surface.completeExceptionally(it) }
        }
        val target = surface.get(5, TimeUnit.SECONDS)
        synchronized(codecLock) {
            check(!stopped.get())
            codec?.let { runCatching { it.stop() }; it.release() }
            codec = null
            val decoder = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            try {
                val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, w, h)
                format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 4 * 1024 * 1024)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && runCatching {
                    decoder.codecInfo.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC)
                        .isFeatureSupported(MediaCodecInfo.CodecCapabilities.FEATURE_LowLatency)
                }.getOrDefault(false)) {
                    format.setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
                }
                decoder.configure(format, target, null, 0)
                decoder.start()
                codec = decoder
                width = w
                height = h
            } catch (e: Exception) { decoder.release(); throw e }
        }
        emit(mapOf("type" to "mirror", "state" to "size", "width" to w, "height" to h))
    }

    private fun feed(packet: Protocols.VideoPacket) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
        while (!stopped.get() && System.nanoTime() < deadline) {
            var queued = false
            synchronized(codecLock) {
                val decoder = codec ?: throw IllegalStateException("Decoder unavailable")
                val index = decoder.dequeueInputBuffer(0)
                if (index >= 0) {
                    val buffer = decoder.getInputBuffer(index) ?: throw IllegalStateException("Decoder buffer unavailable")
                    check(packet.payload.size <= buffer.capacity()) { "Video frame exceeds decoder buffer" }
                    buffer.clear()
                    buffer.put(packet.payload)
                    decoder.queueInputBuffer(index, 0, packet.payload.size, packet.pts,
                        if (packet.config) MediaCodec.BUFFER_FLAG_CODEC_CONFIG else 0)
                    queued = true
                }
            }
            if (queued) return
            Thread.sleep(1)
        }
        if (!stopped.get()) throw IllegalStateException("Video decoder timed out")
    }

    fun touch(action: Int, pointer: Long, x: Int, y: Int, w: Int, h: Int) {
        send(Protocols.touch(action, pointer, x, y, w, h))
    }

    fun key(code: Int) {
        require(code in setOf(3, 4, 26, 24, 25, 187))
        send(Protocols.key(0, code))
        send(Protocols.key(1, code))
    }

    private fun send(bytes: ByteArray) {
        if (stopped.get()) return
        controls.execute {
            if (!stopped.get()) try { controlOutput?.write(bytes); controlOutput?.flush() }
            catch (e: Exception) { fail(e) }
        }
    }

    private fun fail(error: Exception) {
        if (!stopped.get()) {
            emit(mapOf("type" to "mirror", "state" to "error", "error" to (error.message ?: "Mirroring failed")))
            close()
        }
    }

    fun timeout() { fail(IllegalStateException("Screen control startup timed out")) }

    override fun close() {
        if (!stopped.compareAndSet(false, true)) return
        streams.forEach { runCatching { it.close() } }
        controls.shutdownNow()
        synchronized(codecLock) {
            codec?.let { runCatching { it.stop() }; runCatching { it.release() } }
            codec = null
        }
        main.post { producer.release() }
        // cleanup=true removes the jar once the server finishes; also clean up failed starts.
        thread(name = "scrcpy-cleanup") {
            runCatching { adb.command("rm -f -- ${Protocols.quote(remoteJar)}").use {
                Protocols.readShell(it.openInputStream()) { _, _ -> }
            } }
        }
        emit(mapOf("type" to "mirror", "state" to "stopped"))
    }
}
