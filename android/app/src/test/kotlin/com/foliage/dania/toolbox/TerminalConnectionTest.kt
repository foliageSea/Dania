package com.foliage.dania.toolbox

import org.junit.Assert.*
import org.junit.Test
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread

class TerminalConnectionTest {
    private class Transport : TerminalTransport {
        var closes = 0
        val actions = Collections.synchronizedList(mutableListOf<String>())
        override fun write(bytes: ByteArray) { actions.add(String(bytes)) }
        override fun resize(columns: Int, rows: Int) { actions.add("resize " + columns + " " + rows) }
        override fun read(output: (ByteArray) -> Unit) = 0
        override fun close() { closes++ }
    }

    @Test fun closingDuringStartupRejectsAndClosesLateTransport() {
        val events = mutableListOf<Map<String, Any?>>()
        val ended = AtomicInteger()
        val connection = TerminalConnection("phone", "id", { events.add(it) }, { ended.incrementAndGet() })
        connection.finish("closed")
        val transport = Transport()
        try { connection.attach(transport); fail("Late transport must be rejected") }
        catch (_: IllegalStateException) {}
        connection.finish("failed")
        assertEquals(1, transport.closes)
        assertEquals(1, events.size)
        assertEquals(1, ended.get())
        assertEquals("closed", events.single()["reason"])
    }

    @Test fun outputWaitsForDartCreditsAndDuplicateAcknowledgementDoesNotGrantCredit() {
        val events = Collections.synchronizedList(mutableListOf<Map<String, Any?>>())
        val firstWindow = CountDownLatch(8)
        val ninth = CountDownLatch(1)
        val connection = TerminalConnection("phone", "id", {
            events.add(it)
            if (it.containsKey("bytes")) {
                if ((it["sequence"] as Int) <= 8) firstWindow.countDown() else ninth.countDown()
            }
        }, {})
        val finished = CountDownLatch(1)
        val producer = thread {
            try { connection.output(ByteArray(9 * 16384)) } finally { finished.countDown() }
        }
        try {
            assertTrue(firstWindow.await(2, TimeUnit.SECONDS))
            assertFalse(ninth.await(30, TimeUnit.MILLISECONDS))
            connection.acknowledge(1)
            connection.acknowledge(1)
            assertTrue(finished.await(2, TimeUnit.SECONDS))
            assertEquals(9, events.size)
            assertEquals((1..9).toList(), events.map { it["sequence"] })
        } finally { connection.finish("closed"); producer.join(2000) }
    }

    @Test fun serializesInputAndResizeAndClosesOnlyOnce() {
        val transport = Transport()
        val events = mutableListOf<Map<String, Any?>>()
        val connection = TerminalConnection("phone", "id", { events.add(it) }, {})
        connection.attach(transport)
        val completed = CountDownLatch(3)
        connection.enqueue({ it.write("first".toByteArray()) }) { assertNull(it); completed.countDown() }
        connection.enqueue({ it.resize(100, 30) }) { assertNull(it); completed.countDown() }
        connection.enqueue({ it.write("last".toByteArray()) }) { assertNull(it); completed.countDown() }
        assertTrue(completed.await(2, TimeUnit.SECONDS))
        connection.finish("exited", 0)
        connection.finish("closed")
        assertEquals(listOf("first", "resize 100 30", "last"), transport.actions)
        assertEquals(1, transport.closes)
        assertEquals(1, events.count { it["ended"] == true })
    }
}
