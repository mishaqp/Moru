package com.psyche.kelivo

import android.os.SystemClock
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View

/**
 * Real input for the browser: a tap and key presses sent to the WebView
 * like a finger and a keyboard. Pages see them as trusted events, unlike
 * the synthetic ones a script dispatches, which some sites ignore.
 */
internal object BrowserInput {
    /** The view point for a position given as fractions of the visible page. */
    fun point(fx: Double, fy: Double, width: Int, height: Int): Pair<Float, Float> =
        (fx.coerceIn(0.0, 1.0) * (width - 1)).toFloat() to
            (fy.coerceIn(0.0, 1.0) * (height - 1)).toFloat()

    /** The Android key for a `browser_use` key name, or null. */
    fun keyCode(name: String): Int? = when (name) {
        "Enter" -> KeyEvent.KEYCODE_ENTER
        "Tab" -> KeyEvent.KEYCODE_TAB
        "Escape" -> KeyEvent.KEYCODE_ESCAPE
        "Backspace" -> KeyEvent.KEYCODE_DEL
        "Delete" -> KeyEvent.KEYCODE_FORWARD_DEL
        " ", "Space" -> KeyEvent.KEYCODE_SPACE
        "ArrowUp" -> KeyEvent.KEYCODE_DPAD_UP
        "ArrowDown" -> KeyEvent.KEYCODE_DPAD_DOWN
        "ArrowLeft" -> KeyEvent.KEYCODE_DPAD_LEFT
        "ArrowRight" -> KeyEvent.KEYCODE_DPAD_RIGHT
        "Home" -> KeyEvent.KEYCODE_MOVE_HOME
        "End" -> KeyEvent.KEYCODE_MOVE_END
        "PageUp" -> KeyEvent.KEYCODE_PAGE_UP
        "PageDown" -> KeyEvent.KEYCODE_PAGE_DOWN
        else -> null
    }

    /** Taps [view] at the fractions [fx], [fy]; [done] runs after the lift. */
    fun tap(view: View, fx: Double, fy: Double, done: () -> Unit) {
        val (x, y) = point(fx, fy, view.width, view.height)
        val downTime = SystemClock.uptimeMillis()
        val down = MotionEvent.obtain(downTime, downTime, MotionEvent.ACTION_DOWN, x, y, 0)
        down.source = InputDevice.SOURCE_TOUCHSCREEN
        view.dispatchTouchEvent(down)
        down.recycle()
        // A person's tap lasts a moment; an instant one reads as a long gap
        // of zero, which some pages treat as a bot.
        view.postDelayed({
            val up = MotionEvent.obtain(
                downTime, SystemClock.uptimeMillis(), MotionEvent.ACTION_UP, x, y, 0,
            )
            up.source = InputDevice.SOURCE_TOUCHSCREEN
            view.dispatchTouchEvent(up)
            up.recycle()
            done()
        }, 70)
    }

    /** Presses and releases [code] in [view], which gets the focus first. */
    fun key(view: View, code: Int) {
        view.requestFocus()
        val time = SystemClock.uptimeMillis()
        view.dispatchKeyEvent(KeyEvent(time, time, KeyEvent.ACTION_DOWN, code, 0))
        view.dispatchKeyEvent(KeyEvent(time, SystemClock.uptimeMillis(), KeyEvent.ACTION_UP, code, 0))
    }
}
