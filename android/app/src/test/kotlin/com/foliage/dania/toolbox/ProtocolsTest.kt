package com.foliage.dania.toolbox

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.DataInputStream
import java.nio.ByteBuffer

class ProtocolsTest {
    @Test fun scrcpyIdMatchesServerSocket() {
        for (value in listOf(0, 1, 0x12345678, 0x7fffffff)) {
            val argument = Protocols.scrcpyId(value)
            val serverId = Integer.parseInt(argument, 16)
            assertEquals(value, serverId)
            assertEquals("scrcpy_%08x".format(value), "scrcpy_%08x".format(serverId))
        }
    }

    @Test fun quotesShellArguments() {
        assertEquals("'file'", Protocols.quote("file"))
        assertEquals("'a'\\''b'", Protocols.quote("a'b"))
        assertEquals("'$(rm -rf /)'", Protocols.quote("$(rm -rf /)"))
    }

    @Test fun readsShellV2ExitAndOutput() {
        val bytes = byteArrayOf(1) + Protocols.littleInt(3) + "abc".toByteArray() +
            byteArrayOf(3) + Protocols.littleInt(1) + byteArrayOf(7)
        var text = ""
        val exit = Protocols.readShell(ByteArrayInputStream(bytes)) { _, payload -> text += String(payload) }
        assertEquals(7, exit)
        assertEquals("abc", text)
    }

    @Test fun serializesTerminalInputAndResize() {
        val output = java.io.ByteArrayOutputStream()
        val text = "中文\r".toByteArray(Charsets.UTF_8)
        Protocols.writeShell(output, 0, text)
        Protocols.writeShell(output, 5, Protocols.terminalSize(120, 40))
        val input = ByteArrayInputStream(output.toByteArray())
        assertEquals(0, input.read())
        assertEquals(text.size, Protocols.readLittleInt(input))
        assertArrayEquals(text, Protocols.readExactly(input, text.size))
        assertEquals(5, input.read())
        val size = Protocols.readLittleInt(input)
        assertEquals("40x120x0x0\u0000", String(Protocols.readExactly(input, size)))
        assertEquals(-1, input.read())
    }

    @Test fun fragmentedShellFramesPreserveUnknownAndStderrBoundaries() {
        val bytes = byteArrayOf(99) + Protocols.littleInt(2) + byteArrayOf(0, 0) +
            byteArrayOf(2) + Protocols.littleInt(3) + "err".toByteArray() +
            byteArrayOf(3) + Protocols.littleInt(1) + byteArrayOf(0)
        val input = object : ByteArrayInputStream(bytes) {
            override fun read(buffer: ByteArray, offset: Int, size: Int): Int = super.read(buffer, offset, minOf(1, size))
        }
        val output = mutableListOf<Pair<Int, String>>()
        assertEquals(0, Protocols.readShell(input) { kind, value -> output.add(kind to String(value)) })
        assertEquals(listOf(2 to "err"), output)
    }

    @Test(expected = java.io.EOFException::class) fun rejectsTruncatedShellFrame() {
        Protocols.readShell(ByteArrayInputStream(byteArrayOf(1) + Protocols.littleInt(3) + byteArrayOf(1))) { _, _ -> }
    }

    @Test(expected = IllegalArgumentException::class) fun rejectsMalformedExitFrame() {
        Protocols.readShell(ByteArrayInputStream(byteArrayOf(3) + Protocols.littleInt(0))) { _, _ -> }
    }

    @Test(expected = IllegalArgumentException::class) fun rejectsOversizedTerminalInput() {
        Protocols.writeShell(java.io.ByteArrayOutputStream(), 0, ByteArray(16385))
    }

    @Test(expected = IllegalArgumentException::class) fun rejectsInvalidTerminalSize() {
        Protocols.terminalSize(0, 24)
    }

    @Test fun readsScrcpySessionPackets() {
        val bytes = ByteBuffer.allocate(12).putInt(Int.MIN_VALUE).putInt(720).putInt(1280).array()
        val packet = Protocols.videoPacket(DataInputStream(ByteArrayInputStream(bytes)))
        assertEquals(720, packet.width)
        assertEquals(1280, packet.height)
    }

    @Test fun readsScrcpyMediaPackets() {
        val bytes = ByteBuffer.allocate(15).putLong((1L shl 62) or 123L).putInt(3).put(byteArrayOf(1, 2, 3)).array()
        val packet = Protocols.videoPacket(DataInputStream(ByteArrayInputStream(bytes)))
        assertTrue(packet.config)
        assertEquals(123L, packet.pts)
        assertArrayEquals(byteArrayOf(1, 2, 3), packet.payload)
    }

    @Test fun serializesTouchWithClampedCoordinates() {
        val buffer = ByteBuffer.wrap(Protocols.touch(0, 42L, -10, 9999, 720, 1280))
        assertEquals(2, buffer.get().toInt())
        assertEquals(0, buffer.get().toInt())
        assertEquals(42L, buffer.long)
        assertEquals(0, buffer.int)
        assertEquals(1279, buffer.int)
        assertEquals(720, buffer.short.toInt())
        assertEquals(1280, buffer.short.toInt())
        assertEquals(65535, buffer.short.toInt() and 65535)
    }

    @Test(expected = IllegalArgumentException::class) fun rejectsOversizedPacket() {
        Protocols.readExactly(ByteArrayInputStream(byteArrayOf()), Int.MAX_VALUE)
    }

    @Test(expected = IllegalArgumentException::class) fun rejectsNulArgument() {
        Protocols.quote("bad\u0000path")
    }
}
