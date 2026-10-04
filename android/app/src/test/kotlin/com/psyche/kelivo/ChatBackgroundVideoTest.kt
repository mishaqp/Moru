package com.psyche.kelivo

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.assertThrows
import org.junit.Test

class ChatBackgroundVideoTest {
    @Test fun highResolutionVideoIsBoundedToScreenInBothOrientations() {
        assertEquals(1920 to 1080, ChatBackgroundVideoSize.bounded(3840, 2160, 1080, 2400))
        assertEquals(1080 to 1920, ChatBackgroundVideoSize.bounded(2160, 3840, 2400, 1080))
    }

    @Test fun rotationAndEncoderAlignmentKeepDisplayedVideoInsideBounds() {
        for (rotation in listOf(0, 90, 180, 270)) {
            val (width, height) = ChatBackgroundVideoSize.bounded(
                4096, 2160, 1080, 2340, rotation, 16, 16,
            )
            assertEquals(0, width % 16)
            assertEquals(0, height % 16)
            val displayWidth = if (rotation % 180 == 0) width else height
            val displayHeight = if (rotation % 180 == 0) height else width
            assertTrue(minOf(displayWidth, displayHeight) <= 1080)
            assertTrue(maxOf(displayWidth, displayHeight) <= 2340)
            assertTrue(width <= 4096 && height <= 2160)
        }
    }

    @Test fun smallVideosAreNeverUpscaled() {
        assertEquals(640 to 360, ChatBackgroundVideoSize.bounded(640, 360, 1080, 2400))
    }

    @Test fun encoderLimitsReduceResolutionAndFrameRateInsteadOfRejectingVideo() {
        val (width, height, frameRate) = ChatBackgroundVideoSize.supported(
            3840, 2160, 1080, 2400, 0, 16, 16, 60,
        ) { w, h, fps -> w <= 1280 && h <= 720 && fps <= 30 }
        assertTrue(width <= 1280 && height <= 720)
        assertTrue(width >= 1200 && height >= 640)
        assertEquals(0, width % 16)
        assertEquals(0, height % 16)
        assertEquals(30, frameRate)
    }

    @Test fun anEncoderWithNoViableSizeFailsWithoutUpscaling() {
        assertThrows(IllegalArgumentException::class.java) {
            ChatBackgroundVideoSize.supported(640, 360, 1080, 2400, 0, 2, 2, 30) { _, _, _ -> false }
        }
    }

    @Test fun reducedFrameRateKeepsOnlyOneFramePerOutputInterval() {
        val slots = (0 until 60).map {
            ChatBackgroundVideoSize.frameSlot(it * 1_000_000L / 60, 0, 30)
        }
        assertEquals(30, slots.toSet().size)
        assertEquals(0L, slots.first())
        assertEquals(29L, slots.last())
    }

    @Test fun matchingFrameRatesPreserveAllFramesWithTruncatedMicrosecondTimestamps() {
        for (frameRate in listOf(24, 30, 60)) {
            val slots = (0 until frameRate).map {
                ChatBackgroundVideoSize.frameSlot(it * 1_000_000L / frameRate, 0, frameRate)
            }
            assertEquals((0L until frameRate.toLong()).toList(), slots)
        }
    }

    @Test fun halvingFrameRatePreservesEverySecondFrameWithoutCadenceJitter() {
        var lastSlot = -1L
        val retained = (0 until 60).filter {
            val slot = ChatBackgroundVideoSize.frameSlot(it * 1_000_000L / 60, 0, 30)
            if (slot > lastSlot) {
                lastSlot = slot
                true
            } else false
        }
        assertEquals((0 until 60 step 2).toList(), retained)
    }

    @Test fun negativeSourceTimestampsNormalizeFromTheirActualOrigin() {
        val origin = -100_000L
        for (frame in 0 until 30) {
            val time = origin + frame * 1_000_000L / 30
            assertEquals(frame * 1_000_000L / 30, ChatBackgroundVideoSize.normalizedTime(time, origin))
            assertEquals(frame.toLong(), ChatBackgroundVideoSize.frameSlot(time, origin, 30))
        }
    }
}
