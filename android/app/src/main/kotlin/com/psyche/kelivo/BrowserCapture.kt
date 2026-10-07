package com.psyche.kelivo

import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import java.io.ByteArrayOutputStream

/** Screenshots of the shared browser for `browser_use` action=screenshot. */
internal object BrowserCapture {
    const val MAX_SIDE = 1280
    const val QUALITY = 80

    /** Size to draw [width]x[height] at so the longer side is at most [MAX_SIDE]. */
    fun scaledSize(width: Int, height: Int): Pair<Int, Int> {
        val longer = maxOf(width, height)
        if (longer <= MAX_SIDE) return width to height
        val scale = MAX_SIDE.toFloat() / longer
        return maxOf(1, (width * scale).toInt()) to maxOf(1, (height * scale).toInt())
    }

    /** JPEG of what [view] shows now. Throws when it has no size yet. */
    fun jpeg(view: View): ByteArray {
        val width = view.width
        val height = view.height
        require(width > 0 && height > 0) { "The browser has no size yet." }
        val (outWidth, outHeight) = scaledSize(width, height)
        val bitmap = Bitmap.createBitmap(outWidth, outHeight, Bitmap.Config.ARGB_8888)
        try {
            val canvas = Canvas(bitmap)
            canvas.scale(outWidth.toFloat() / width, outHeight.toFloat() / height)
            view.draw(canvas)
            val out = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, QUALITY, out)
            return out.toByteArray()
        } finally {
            bitmap.recycle()
        }
    }
}
