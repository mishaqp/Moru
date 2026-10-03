package com.psyche.kelivo

import android.content.Context
import android.os.Vibrator
import org.robolectric.RuntimeEnvironment
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class MiniAppVibrationTest {
    @Test fun patternStartsAtOnce() {
        assertArrayEquals(longArrayOf(0, 200), MiniAppVibration.timings(listOf(200)))
        assertArrayEquals(longArrayOf(0, 100, 50, 100), MiniAppVibration.timings(listOf(100, 50, 100)))
    }

    @Test fun emptyNegativeAndTooLongPatternsPlayNothing() {
        assertNull(MiniAppVibration.timings(emptyList()))
        assertNull(MiniAppVibration.timings(listOf(0, 0)))
        assertNull(MiniAppVibration.timings(listOf(100, -1)))
        assertNull(MiniAppVibration.timings(List(MiniAppVibration.MAX_SEGMENTS + 1) { 10 }))
        assertNull(MiniAppVibration.timings(listOf(MiniAppVibration.MAX_TOTAL_MS + 1)))
    }

    @Test fun vibratesTheDevice() {
        val context = RuntimeEnvironment.getApplication()
        val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        assertTrue(MiniAppVibration.vibrate(context, listOf(120)))
        assertTrue(shadowOf(vibrator).isVibrating)
        assertFalse(MiniAppVibration.vibrate(context, emptyList()))
    }
}
