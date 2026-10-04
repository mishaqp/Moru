package com.psyche.kelivo

/** Encoded size capped in either display orientation, without upscaling. */
internal object ChatBackgroundVideoSize {
    fun bounded(
        width: Int,
        height: Int,
        maxWidth: Int,
        maxHeight: Int,
        rotation: Int = 0,
        widthAlignment: Int = 2,
        heightAlignment: Int = 2,
    ): Pair<Int, Int> {
        require(width > 0 && height > 0 && maxWidth > 0 && maxHeight > 0)
        require(widthAlignment > 0 && heightAlignment > 0)
        require(rotation in listOf(0, 90, 180, 270))
        val displayWidth = if (rotation % 180 == 0) width else height
        val displayHeight = if (rotation % 180 == 0) height else width
        val scale = minOf(
            1.0,
            minOf(maxWidth, maxHeight).toDouble() / minOf(displayWidth, displayHeight),
            maxOf(maxWidth, maxHeight).toDouble() / maxOf(displayWidth, displayHeight),
        )
        val outWidth = (width * scale).toInt() / widthAlignment * widthAlignment
        val outHeight = (height * scale).toInt() / heightAlignment * heightAlignment
        require(outWidth > 0 && outHeight > 0) { "The video is too small to encode." }
        return outWidth to outHeight
    }

    /** Keep the largest bounded size this encoder can accept, then its best rate. */
    fun supported(
        width: Int,
        height: Int,
        maxWidth: Int,
        maxHeight: Int,
        rotation: Int,
        widthAlignment: Int,
        heightAlignment: Int,
        requestedFrameRate: Int,
        supports: (Int, Int, Int) -> Boolean,
    ): Triple<Int, Int, Int> {
        require(requestedFrameRate in 1..60)
        val (boundedWidth, boundedHeight) = bounded(
            width, height, maxWidth, maxHeight, rotation, widthAlignment, heightAlignment,
        )
        var scale = 1.0
        while (scale > 0) {
            val candidateWidth = (boundedWidth * scale).toInt() / widthAlignment * widthAlignment
            val candidateHeight = (boundedHeight * scale).toInt() / heightAlignment * heightAlignment
            if (candidateWidth <= 0 || candidateHeight <= 0) break
            for (frameRate in requestedFrameRate downTo 1) {
                if (supports(candidateWidth, candidateHeight, frameRate)) {
                    return Triple(candidateWidth, candidateHeight, frameRate)
                }
            }
            scale = minOf(
                (candidateWidth - widthAlignment).toDouble() / boundedWidth,
                (candidateHeight - heightAlignment).toDouble() / boundedHeight,
            )
        }
        throw IllegalArgumentException("The encoder cannot accept a bounded video size.")
    }

    fun normalizedTime(presentationTimeUs: Long, firstPresentationTimeUs: Long): Long =
        maxOf(0, presentationTimeUs - firstPresentationTimeUs)

    fun frameSlot(presentationTimeUs: Long, firstPresentationTimeUs: Long, frameRate: Int): Long =
        // Extractors truncate rational frame times to integer microseconds.
        (normalizedTime(presentationTimeUs, firstPresentationTimeUs) * frameRate + frameRate - 1) / 1_000_000

    fun fits(width: Int, height: Int, maxWidth: Int, maxHeight: Int): Boolean =
        width > 0 && height > 0 &&
            minOf(width, height) <= minOf(maxWidth, maxHeight) &&
            maxOf(width, height) <= maxOf(maxWidth, maxHeight)
}
