package com.foliage.dania.toolbox

import org.junit.Assert.*
import org.junit.Test
import java.util.ArrayDeque

class VideoOutputTest {
    @Test fun rendersSingleFrameImmediately() {
        val buffers = ArrayDeque(listOf(4, -1))
        val released = mutableListOf<Pair<Int, Boolean>>()
        assertTrue(VideoOutput.drain({ buffers.removeFirst() }, { id, render -> released.add(id to render) }))
        assertEquals(listOf(4 to true), released)
    }

    @Test fun skipsStaleDecodedFramesAndRendersLatest() {
        val buffers = ArrayDeque(listOf(-2, 4, 5, -3, 6, -1))
        val released = mutableListOf<Pair<Int, Boolean>>()
        assertTrue(VideoOutput.drain({ buffers.removeFirst() }, { id, render -> released.add(id to render) }))
        assertEquals(listOf(4 to false, 5 to false, 6 to true), released)
    }

    @Test fun returnsWithoutRenderingWhenOutputIsEmpty() {
        assertFalse(VideoOutput.drain({ -1 }, { _, _ -> fail("No buffer should be released") }))
    }

    @Test fun boundsContinuousOutputToLetInputAndShutdownProceed() {
        var dequeued = 0
        val released = mutableListOf<Pair<Int, Boolean>>()
        assertTrue(VideoOutput.drain({ dequeued++ }, { id, render -> released.add(id to render) }))
        assertEquals(16, dequeued)
        assertEquals(16, released.size)
        assertEquals(15 to true, released.last())
        assertTrue(released.dropLast(1).all { !it.second })
    }
}
