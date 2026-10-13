package com.foliage.dania.toolbox

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.DataInputStream
import java.nio.ByteBuffer

class ProtocolsTest {
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
