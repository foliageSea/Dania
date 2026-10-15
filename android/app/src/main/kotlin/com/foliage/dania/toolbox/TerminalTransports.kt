package com.foliage.dania.toolbox

import android.os.ParcelFileDescriptor
import io.github.muntashirakon.adb.AdbStream
import java.util.concurrent.atomic.AtomicBoolean

class AdbTerminalTransport(private val stream: AdbStream) : TerminalTransport {
    private val input = stream.openInputStream()
    private val output = stream.openOutputStream()
    override fun write(bytes: ByteArray) = Protocols.writeShell(output, 0, bytes)
    override fun resize(columns: Int, rows: Int) =
        Protocols.writeShell(output, 5, Protocols.terminalSize(columns, rows))
    override fun read(output: (ByteArray) -> Unit): Int =
        Protocols.readShell(input) { _, bytes -> output(bytes) }
    override fun close() { stream.close() }
}

class LocalTerminalTransport(
    private val service: IPrivilegedService,
    private val id: String,
    descriptor: ParcelFileDescriptor,
) : TerminalTransport {
    private val closed = AtomicBoolean()
    private val readDescriptor = descriptor
    private val writeDescriptor = try { ParcelFileDescriptor.dup(descriptor.fileDescriptor) }
        catch (error: Exception) { descriptor.close(); service.closeTerminal(id); throw error }
    private val input = ParcelFileDescriptor.AutoCloseInputStream(readDescriptor)
    private val output = ParcelFileDescriptor.AutoCloseOutputStream(writeDescriptor)
    override fun write(bytes: ByteArray) { output.write(bytes); output.flush() }
    override fun resize(columns: Int, rows: Int) = service.resizeTerminal(id, columns, rows)
    override fun read(output: (ByteArray) -> Unit): Int {
        val bytes = ByteArray(8192)
        while (!closed.get()) {
            val count = try { input.read(bytes) } catch (error: java.io.IOException) {
                // A PTY master can return EIO when the last slave closes.
                if (error.cause is android.system.ErrnoException &&
                    (error.cause as android.system.ErrnoException).errno == android.system.OsConstants.EIO) break
                throw error
            }
            if (count < 0) break
            if (count > 0) output(bytes.copyOf(count))
        }
        return service.waitForTerminal(id)
    }
    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        runCatching { service.closeTerminal(id) }
        runCatching { input.close() }
        runCatching { output.close() }
    }
}
