package com.psyche.kelivo

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/** `moru.vibrate` of mini apps. */
internal object MiniAppVibration {
    const val MAX_SEGMENTS = 20
    const val MAX_TOTAL_MS = 5000

    /**
     * Android waveform timings for [pattern] (on, off, on, ... in ms): a
     * leading 0 so it starts at once. Null when there is nothing to play or
     * the pattern is out of bounds.
     */
    fun timings(pattern: List<Int>): LongArray? {
        if (pattern.isEmpty() || pattern.size > MAX_SEGMENTS) return null
        if (pattern.any { it < 0 }) return null
        val total = pattern.sum()
        if (total == 0 || total > MAX_TOTAL_MS) return null
        return LongArray(pattern.size + 1) { i -> if (i == 0) 0L else pattern[i - 1].toLong() }
    }

    /** False when the device cannot vibrate or the pattern is empty. */
    fun vibrate(context: Context, pattern: List<Int>): Boolean {
        val timings = timings(pattern) ?: return false
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
        if (vibrator == null || !vibrator.hasVibrator()) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createWaveform(timings, -1))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(timings, -1)
        }
        return true
    }
}
