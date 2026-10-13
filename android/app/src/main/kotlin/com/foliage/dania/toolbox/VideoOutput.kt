package com.foliage.dania.toolbox

import android.media.MediaCodec

object VideoOutput {
    fun drain(dequeue: () -> Int, release: (Int, Boolean) -> Unit): Boolean {
        var latest = -1
        // Bound each pass so input, rotation and shutdown can acquire the codec lock.
        for (attempt in 0 until 16) {
            val index = dequeue()
            when {
                index >= 0 -> {
                    if (latest >= 0) release(latest, false)
                    latest = index
                }
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED ||
                    index == MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED -> continue
                else -> break
            }
        }
        if (latest < 0) return false
        release(latest, true)
        return true
    }
}
