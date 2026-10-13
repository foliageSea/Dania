package com.foliage.dania.toolbox

import java.io.DataInputStream
import java.io.EOFException
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

object Protocols {
    fun scrcpyId(value: Int): String {
        require(value >= 0)
        return value.toString(16).padStart(8, '0')
    }

    fun quote(value: String): String {
        require(!value.contains('\u0000'))
        return "'" + value.replace("'", "'\\''") + "'"
    }

    fun littleInt(value: Int): ByteArray = ByteBuffer.allocate(4)
        .order(ByteOrder.LITTLE_ENDIAN).putInt(value).array()

    fun readLittleInt(input: InputStream): Int = ByteBuffer.wrap(readExactly(input, 4))
        .order(ByteOrder.LITTLE_ENDIAN).int

    fun readExactly(input: InputStream, size: Int): ByteArray {
        require(size in 0..(16 * 1024 * 1024)) { "Invalid packet size" }
        val bytes = ByteArray(size)
        var offset = 0
        while (offset < size) {
            val count = input.read(bytes, offset, size - offset)
            if (count < 0) throw EOFException("Unexpected end of stream")
            offset += count
        }
        return bytes
    }

    fun readShell(input: InputStream, output: (Int, ByteArray) -> Unit): Int {
        while (true) {
            val kind = input.read()
            if (kind < 0) throw EOFException("Shell closed without exit status")
            val size = readLittleInt(input)
            require(size in 0..(1024 * 1024)) { "Invalid shell packet" }
            val bytes = readExactly(input, size)
            when (kind) {
                1, 2 -> output(kind, bytes)
                3 -> {
                    require(bytes.isNotEmpty())
                    return bytes[0].toInt() and 255
                }
            }
        }
    }

    fun touch(action: Int, pointer: Long, x: Int, y: Int, width: Int, height: Int): ByteArray {
        require(action in 0..3 && width in 1..65535 && height in 1..65535)
        return ByteBuffer.allocate(32).put(2).put(action.toByte()).putLong(pointer)
            .putInt(x.coerceIn(0, width - 1)).putInt(y.coerceIn(0, height - 1))
            .putShort(width.toShort()).putShort(height.toShort())
            .putShort(if (action == 1 || action == 3) 0 else (-1).toShort())
            .putInt(0).putInt(0).array()
    }

    fun key(action: Int, code: Int): ByteArray = ByteBuffer.allocate(14)
        .put(0).put(action.toByte()).putInt(code).putInt(0).putInt(0).array()

    data class VideoPacket(val width: Int = 0, val height: Int = 0,
        val pts: Long = 0, val config: Boolean = false, val payload: ByteArray = byteArrayOf())

    // scrcpy 5.0.1: session packets precede every capture session, including rotation.
    fun videoPacket(input: DataInputStream): VideoPacket {
        val first = input.readInt()
        if (first < 0) {
            val width = input.readInt()
            val height = input.readInt()
            require(width in 1..16384 && height in 1..16384)
            return VideoPacket(width = width, height = height)
        }
        val flags = (first.toLong() shl 32) or (input.readInt().toLong() and 0xffffffffL)
        val size = input.readInt()
        return VideoPacket(pts = flags and 0x1fffffffffffffffL,
            config = flags and (1L shl 62) != 0L, payload = readExactly(input, size))
    }
}
