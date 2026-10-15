package com.foliage.dania.toolbox

import java.io.Closeable
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Semaphore
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

interface TerminalTransport : Closeable {
    fun write(bytes: ByteArray)
    fun resize(columns: Int, rows: Int)
    fun read(output: (ByteArray) -> Unit): Int
}

/** An independently cancellable PTY, including the period before transport attachment. */
class TerminalConnection(
    val device: String,
    val id: String,
    private val emit: (Map<String, Any?>) -> Unit,
    private val ended: () -> Unit,
) {
    private val lock = Any()
    @Volatile private var finished = false
    @Volatile private var transport: TerminalTransport? = null
    private val credits = Semaphore(8)
    private val pending = ConcurrentHashMap.newKeySet<Int>()
    private val sequence = AtomicInteger()
    private val writer = ThreadPoolExecutor(1, 1, 0, TimeUnit.MILLISECONDS,
        ArrayBlockingQueue<Runnable>(32))

    fun attach(value: TerminalTransport) {
        synchronized(lock) {
            if (!finished) { transport = value; return }
        }
        value.close()
        throw IllegalStateException("Terminal was closed during startup")
    }

    fun output(bytes: ByteArray) {
        // Credits are returned only after Dart has consumed the packet, not when
        // the Android main thread has merely queued it onto the engine.
        for (offset in bytes.indices step 16384) {
            while (!credits.tryAcquire(100, TimeUnit.MILLISECONDS)) {
                check(!finished) { "Terminal closed" }
            }
            synchronized(lock) {
                if (finished) { credits.release(); return }
                val token = sequence.incrementAndGet()
                pending.add(token)
                emit(mapOf("type" to "terminal", "deviceId" to device, "sessionId" to id,
                    "sequence" to token, "bytes" to bytes.copyOfRange(offset, minOf(offset + 16384, bytes.size))))
            }
        }
    }

    fun acknowledge(token: Int) { if (pending.remove(token)) credits.release() }

    fun enqueue(action: (TerminalTransport) -> Unit, result: (Exception?) -> Unit) {
        if (finished) { result(IllegalStateException("Terminal is closed")); return }
        try {
            writer.execute {
                try {
                    check(!finished) { "Terminal is closed" }
                    action(transport ?: throw IllegalStateException("Terminal is not ready"))
                    result(null)
                } catch (error: Exception) { result(error); finish("failed", error = error.message) }
            }
        } catch (error: Exception) { result(error); finish("failed", error = error.message) }
    }

    fun read(): Int = (transport ?: throw IllegalStateException("Terminal is not ready")).read(::output)

    fun finish(reason: String, exit: Int? = null, error: String? = null) {
        val resource: TerminalTransport?
        synchronized(lock) {
            if (finished) return
            finished = true
            resource = transport
            transport = null
            emit(mapOf("type" to "terminal", "deviceId" to device, "sessionId" to id,
                "ended" to true, "reason" to reason, "exitCode" to exit, "error" to error))
        }
        // Keep accepted tasks running so each platform method receives a reply.
        writer.shutdown()
        credits.release(8)
        pending.clear()
        runCatching { resource?.close() }
        ended()
    }
}
