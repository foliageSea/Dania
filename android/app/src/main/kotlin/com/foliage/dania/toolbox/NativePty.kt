package com.foliage.dania.toolbox

import android.os.ParcelFileDescriptor
import java.io.File
import java.util.concurrent.CompletableFuture
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

object NativePty {
    private var loaded = false
    @Synchronized fun load(path: String) {
        if (loaded) return
        val file = File(path).canonicalFile
        require(file.isAbsolute && file.name == "libdania_pty.so" && file.isFile) { "PTY library is unavailable" }
        try { System.load(file.absolutePath) }
        catch (error: LinkageError) { throw IllegalStateException("Cannot load PTY library", error) }
        loaded = true
    }
    external fun spawn(columns: Int, rows: Int): IntArray
    external fun resize(fd: Int, columns: Int, rows: Int)
    external fun waitFor(pid: Int): Int
    external fun terminate(fd: Int, pid: Int)
}

class LocalPty(columns: Int, rows: Int) {
    private val process = NativePty.spawn(columns, rows)
    private val descriptor = ParcelFileDescriptor.adoptFd(process[0])
    private val alive = AtomicBoolean(true)
    private val closed = AtomicBoolean()
    private val exit = CompletableFuture<Int>()
    init {
        thread(name = "dania-pty-wait") {
            try {
                val status = NativePty.waitFor(process[1])
                alive.set(false)
                exit.complete(status)
            } catch (error: Throwable) {
                alive.set(false)
                exit.completeExceptionally(error)
            }
        }
    }
    @Synchronized fun duplicate(): ParcelFileDescriptor {
        check(!closed.get()) { "Terminal is closed" }
        return ParcelFileDescriptor.dup(descriptor.fileDescriptor)
    }
    @Synchronized fun resize(columns: Int, rows: Int) {
        check(!closed.get()) { "Terminal is closed" }
        NativePty.resize(descriptor.fd, columns, rows)
    }
    fun waitFor(): Int = exit.get()
    @Synchronized fun close() {
        if (!closed.compareAndSet(false, true)) return
        try { NativePty.terminate(descriptor.fd, if (alive.get()) process[1] else 0) }
        finally { descriptor.close() }
    }
}
