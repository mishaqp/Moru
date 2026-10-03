package com.psyche.kelivo

import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.view.View
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
// Real bitmaps and JPEG encoding, so the output is a decodable picture.
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [28], manifest = Config.NONE)
class BrowserCaptureTest {
    @Test fun largeViewsAreScaledToTheMaximumSide() {
        // The longer side becomes 1280 and the other follows.
        assertEquals(576 to 1280, BrowserCapture.scaledSize(1080, 2400))
        assertEquals(1280 to 720, BrowserCapture.scaledSize(1920, 1080))
        assertEquals(400 to 300, BrowserCapture.scaledSize(400, 300))
    }

    @Test fun theViewIsDrawnIntoAJpeg() {
        val view = object : View(RuntimeEnvironment.getApplication()) {
            override fun onDraw(canvas: Canvas) {
                canvas.drawColor(Color.RED)
            }
        }
        view.layout(0, 0, 200, 100)
        val bytes = BrowserCapture.jpeg(view)
        val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        assertEquals(200, decoded.width)
        assertEquals(100, decoded.height)
        // JPEG is lossy; the red stays clearly red.
        val pixel = decoded.getPixel(100, 50)
        assert(Color.red(pixel) > 200 && Color.green(pixel) < 60)
    }

    @Test fun aViewWithoutSizeIsRefused() {
        val view = View(RuntimeEnvironment.getApplication())
        assertThrows(IllegalArgumentException::class.java) { BrowserCapture.jpeg(view) }
    }
}
