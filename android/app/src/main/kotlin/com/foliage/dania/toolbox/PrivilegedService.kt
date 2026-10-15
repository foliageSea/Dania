package com.foliage.dania.toolbox

import android.os.ParcelFileDescriptor
import android.system.Os
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import kotlin.concurrent.thread

// This Binder runs as shell/root in a Shizuku UserService, not in the app process.
class PrivilegedService : IPrivilegedService.Stub() {
    private val processes = ConcurrentHashMap<String, Process>()
    private val terminals = ConcurrentHashMap<String, LocalPty>()

    override fun startCommand(id: String, command: String): ParcelFileDescriptor {
        require(command.length <= 32768 && !command.contains('\u0000'))
        val pipe = ParcelFileDescriptor.createPipe()
        try {
            val process = ProcessBuilder("/system/bin/sh", "-c", command)
                .redirectErrorStream(true).start()
            process.outputStream.close()
            processes[id] = process
            thread(name = "shizuku-output") {
                try {
                    ParcelFileDescriptor.AutoCloseOutputStream(pipe[1]).use { output ->
                        process.inputStream.use { it.copyTo(output) }
                    }
                } catch (_: Exception) {
                    process.destroy()
                    runCatching { pipe[1].close() }
                }
            }
            return pipe[0]
        } catch (error: Exception) {
            pipe.forEach { it.close() }
            throw error
        }
    }

    override fun waitForCommand(id: String): Int {
        val process = processes[id] ?: return -1
        return try { process.waitFor() } finally { processes.remove(id) }
    }

    override fun cancelCommand(id: String) {
        processes[id]?.destroyForcibly()
    }

    override fun openTerminal(id: String, columns: Int, rows: Int, libraryPath: String): ParcelFileDescriptor {
        require(id.length in 1..128 && columns in 2..1000 && rows in 1..1000)
        NativePty.load(libraryPath)
        val terminal = LocalPty(columns, rows)
        if (terminals.putIfAbsent(id, terminal) != null) {
            terminal.close()
            throw IllegalStateException("Terminal already exists")
        }
        try { return terminal.duplicate() }
        catch (error: Exception) { terminals.remove(id, terminal); terminal.close(); throw error }
    }

    override fun resizeTerminal(id: String, columns: Int, rows: Int) {
        require(columns in 2..1000 && rows in 1..1000)
        (terminals[id] ?: throw IllegalStateException("Terminal is closed")).resize(columns, rows)
    }

    override fun waitForTerminal(id: String): Int {
        val terminal = terminals[id] ?: return -1
        return try { terminal.waitFor() } finally {
            terminals.remove(id, terminal)
            terminal.close()
        }
    }

    override fun closeTerminal(id: String) { terminals.remove(id)?.close() }

    override fun listFiles(path: String): String {
        require(path.startsWith('/') && !path.contains('\u0000'))
        val files = File(path).listFiles() ?: throw IllegalStateException("Cannot read directory")
        require(files.size <= 5000) { "Directory has too many entries" }
        val entries = JSONArray()
        files.forEach { file ->
            val stat = Os.lstat(file.absolutePath)
            entries.put(JSONObject().put("name", file.name).put("mode", stat.st_mode)
                .put("size", stat.st_size).put("modified", stat.st_mtime))
        }
        return entries.toString().also { require(it.toByteArray().size <= 500000) }
    }

    override fun openFile(path: String, write: Boolean): ParcelFileDescriptor {
        require(path.startsWith('/') && !path.contains('\u0000'))
        return ParcelFileDescriptor.open(File(path), if (write)
            ParcelFileDescriptor.MODE_WRITE_ONLY or ParcelFileDescriptor.MODE_CREATE or ParcelFileDescriptor.MODE_TRUNCATE
        else ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun destroy() {
        terminals.values.forEach { runCatching { it.close() } }
        terminals.clear()
        processes.values.forEach { it.destroyForcibly() }
        processes.clear()
        kotlin.system.exitProcess(0)
    }
}
