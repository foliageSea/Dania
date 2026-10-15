package com.foliage.dania.toolbox

import android.os.Build
import android.util.Base64
import io.github.muntashirakon.adb.AbsAdbConnectionManager
import io.github.muntashirakon.adb.AdbStream
import java.io.Closeable
import java.io.InputStream
import java.io.OutputStream
import java.security.PrivateKey
import java.security.cert.Certificate
import java.util.concurrent.TimeUnit

class AdbBackend(identity: AdbIdentity) : AbsAdbConnectionManager() {
    private val material = identity.get()
    init { setApi(Build.VERSION.SDK_INT); setTimeout(20, TimeUnit.SECONDS) }
    override fun getPrivateKey(): PrivateKey = material.first
    override fun getCertificate(): Certificate = material.second
    override fun getDeviceName(): String = "Dania"

    fun terminal(): AdbStream =
        openStream("shell,v2,pty,TERM=xterm-256color:/system/bin/sh -i")

    fun command(command: String): AdbStream {
        require(command.length <= 32768 && !command.contains('\u0000'))
        // libadb's OPEN encoder requires ASCII destinations. Decode user UTF-8 on the target.
        val encoded = Base64.encodeToString(command.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
        return openStream("shell,v2,raw:echo $encoded | base64 -d | /system/bin/sh")
    }
}

class AdbSync(private val stream: AdbStream) : Closeable {
    private val input = stream.openInputStream()
    private val output = stream.openOutputStream()

    private fun request(id: String, payload: ByteArray) {
        require(payload.size <= 65536)
        output.write(id.toByteArray(Charsets.US_ASCII))
        output.write(Protocols.littleInt(payload.size))
        output.write(payload)
        output.flush()
    }

    private fun header(): Pair<String, Int> {
        val id = String(Protocols.readExactly(input, 4), Charsets.US_ASCII)
        val length = Protocols.readLittleInt(input)
        if (id == "FAIL") throw IllegalStateException(String(Protocols.readExactly(input, length), Charsets.UTF_8))
        return id to length
    }

    fun list(path: String): List<Map<String, Any>> {
        request("LIST", path.toByteArray(Charsets.UTF_8))
        val result = mutableListOf<Map<String, Any>>()
        while (true) {
            val (id, mode) = header()
            if (id == "DONE") {
                Protocols.readExactly(input, 12)
                return result
            }
            check(id == "DENT") { "Invalid directory response" }
            val size = Protocols.readLittleInt(input).toLong() and 0xffffffffL
            val modified = Protocols.readLittleInt(input).toLong() and 0xffffffffL
            val name = String(Protocols.readExactly(input, Protocols.readLittleInt(input)), Charsets.UTF_8)
            if (name != "." && name != "..") result.add(mapOf("name" to name, "mode" to mode,
                "size" to size, "modified" to modified))
            check(result.size <= 5000) { "Directory has too many entries" }
        }
    }

    fun push(path: String, source: InputStream, progress: (Long) -> Unit) {
        request("SEND", "$path,33188".toByteArray(Charsets.UTF_8))
        val buffer = ByteArray(65536)
        var total = 0L
        while (true) {
            val size = source.read(buffer)
            if (size < 0) break
            request("DATA", buffer.copyOf(size))
            total += size
            progress(total)
        }
        output.write("DONE".toByteArray(Charsets.US_ASCII))
        output.write(Protocols.littleInt((System.currentTimeMillis() / 1000).toInt()))
        output.flush()
        val (id, size) = header()
        check(id == "OKAY" && size == 0) { "Upload rejected" }
    }

    fun pull(path: String, destination: OutputStream, progress: (Long) -> Unit) {
        request("RECV", path.toByteArray(Charsets.UTF_8))
        var total = 0L
        while (true) {
            val (id, size) = header()
            if (id == "DONE") return
            check(id == "DATA" && size in 0..65536) { "Invalid download packet" }
            destination.write(Protocols.readExactly(input, size))
            total += size
            progress(total)
        }
    }

    override fun close() { stream.close() }
}
