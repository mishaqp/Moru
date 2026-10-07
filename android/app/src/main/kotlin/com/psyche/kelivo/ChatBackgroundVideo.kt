package com.psyche.kelivo

import android.content.Context
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.concurrent.Executors

/** Imports a playback derivative. The selected/copied original is never written. */
internal class ChatBackgroundVideo(private val context: Context) {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun configure(messenger: BinaryMessenger) {
        MethodChannel(messenger, "app.chat_background_video").setMethodCallHandler { call, result ->
            if (call.method != "prepare") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val source = call.argument<String>("sourcePath")
            val maxWidth = call.argument<Number>("maxWidth")?.toInt() ?: 0
            val maxHeight = call.argument<Number>("maxHeight")?.toInt() ?: 0
            if (source.isNullOrEmpty() || maxWidth <= 0 || maxHeight <= 0) {
                result.error("invalid_args", "A file and positive screen bounds are required.", null)
                return@setMethodCallHandler
            }
            worker.execute {
                try {
                    val path = prepare(File(source), maxWidth, maxHeight)
                    main.post { result.success(path) }
                } catch (_: Exception) {
                    // Paths and source metadata stay private; the UI shows its localized error.
                    main.post { result.error("video_preparation_failed", "Unable to prepare this video.", null) }
                }
            }
        }
    }

    private fun prepare(source: File, maxWidth: Int, maxHeight: Int): String {
        val original = source.canonicalFile
        val privateRoot = File(context.applicationInfo.dataDir).canonicalPath + File.separator
        require(original.path.startsWith(privateRoot) && original.isFile && original.length() > 0)
        val directory = File(context.cacheDir, "chat_backgrounds")
        check(directory.isDirectory || directory.mkdirs())
        val key = listOf(original.path, original.length(), original.lastModified(), maxWidth, maxHeight, 1)
            .joinToString("|")
        val hash = MessageDigest.getInstance("SHA-256").digest(key.toByteArray())
            .joinToString("") { "%02x".format(it) }
        val output = File(directory, "$hash.mp4")
        if (validOutput(output, maxWidth, maxHeight)) return output.path
        output.delete()
        val partial = File(directory, "$hash.part.mp4")
        partial.delete()
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(original.path)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true
            } ?: throw IllegalArgumentException("There is no video track.")
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            val width = format.getInteger(MediaFormat.KEY_WIDTH)
            val height = format.getInteger(MediaFormat.KEY_HEIGHT)
            val rotation = if (format.containsKey(MediaFormat.KEY_ROTATION)) {
                ((format.getInteger(MediaFormat.KEY_ROTATION) % 360) + 360) % 360
            } else 0
            require(width > 0 && height > 0 && rotation in listOf(0, 90, 180, 270))
            // MP4 B-frame remuxing is supported from Nougat MR1 (API 25).
            if (Build.VERSION.SDK_INT >= 25 &&
                format.getString(MediaFormat.KEY_MIME) == MediaFormat.MIMETYPE_VIDEO_AVC &&
                ChatBackgroundVideoSize.fits(width, height, maxWidth, maxHeight)) {
                remux(extractor, format, rotation, partial)
            } else {
                transcode(extractor, format, rotation, partial, maxWidth, maxHeight)
            }
            check(validOutput(partial, maxWidth, maxHeight)) { "The encoded video is invalid." }
            check(partial.renameTo(output)) { "Unable to save the encoded video." }
            return output.path
        } finally {
            runCatching { extractor.release() }
            partial.delete()
        }
    }

    private fun validOutput(file: File, maxWidth: Int, maxHeight: Int): Boolean {
        if (!file.isFile || file.length() == 0L) return false
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(file.path)
            if (extractor.trackCount != 1) return false
            val format = extractor.getTrackFormat(0)
            format.getString(MediaFormat.KEY_MIME) == MediaFormat.MIMETYPE_VIDEO_AVC &&
                ChatBackgroundVideoSize.fits(
                    format.getInteger(MediaFormat.KEY_WIDTH), format.getInteger(MediaFormat.KEY_HEIGHT),
                    maxWidth, maxHeight,
                ) && format.containsKey(MediaFormat.KEY_DURATION) &&
                format.getLong(MediaFormat.KEY_DURATION) > 0
        } catch (_: Exception) {
            false
        } finally {
            runCatching { extractor.release() }
        }
    }

    /** Already bounded AVC needs only a video-only copy, without any decode. */
    private fun remux(extractor: MediaExtractor, format: MediaFormat, rotation: Int, output: File) {
        val muxer = MediaMuxer(output.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var started = false
        try {
            muxer.setOrientationHint(rotation)
            val track = muxer.addTrack(format)
            muxer.start()
            started = true
            val declaredSize = if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
            } else 0
            // Grow for the current compressed sample; do not allocate a full decoded frame.
            require(declaredSize <= 64 * 1024 * 1024)
            var buffer = ByteBuffer.allocateDirect(maxOf(4 * 1024 * 1024, declaredSize))
            val info = MediaCodec.BufferInfo()
            var firstTime: Long? = null
            while (extractor.sampleTrackIndex >= 0) {
                if (Build.VERSION.SDK_INT >= 28) {
                    val needed = extractor.sampleSize
                    require(needed in 0..64L * 1024 * 1024) { "The video sample is too large." }
                    if (needed > buffer.capacity()) buffer = ByteBuffer.allocateDirect(needed.toInt())
                }
                buffer.clear()
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) break
                val sampleTime = extractor.sampleTime
                val origin = firstTime ?: sampleTime.also { firstTime = it }
                val flags = if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) {
                    MediaCodec.BUFFER_FLAG_KEY_FRAME
                } else 0
                require(extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_ENCRYPTED == 0)
                info.set(0, size, ChatBackgroundVideoSize.normalizedTime(sampleTime, origin), flags)
                muxer.writeSampleData(track, buffer, info)
                extractor.advance()
            }
            check(firstTime != null) { "The video is empty." }
            muxer.stop()
            started = false
        } finally {
            if (started) runCatching { muxer.stop() }
            runCatching { muxer.release() }
        }
    }

    private fun transcode(
        extractor: MediaExtractor,
        sourceFormat: MediaFormat,
        rotation: Int,
        output: File,
        maxWidth: Int,
        maxHeight: Int,
    ) {
        var encoder: MediaCodec? = null
        var decoder: MediaCodec? = null
        var surface: ChatBackgroundVideoSurface? = null
        var muxer: MediaMuxer? = null
        var muxerStarted = false
        try {
            val activeEncoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            encoder = activeEncoder
            val capabilities = activeEncoder.codecInfo.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC)
            require(capabilities.colorFormats.contains(MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface))
            val videoCapabilities = checkNotNull(capabilities.videoCapabilities)
            val requestedFrameRate = if (sourceFormat.containsKey(MediaFormat.KEY_FRAME_RATE)) {
                sourceFormat.getInteger(MediaFormat.KEY_FRAME_RATE).coerceIn(1, 60)
            } else 30
            val (width, height, frameRate) = ChatBackgroundVideoSize.supported(
                sourceFormat.getInteger(MediaFormat.KEY_WIDTH), sourceFormat.getInteger(MediaFormat.KEY_HEIGHT),
                maxWidth, maxHeight, rotation,
                maxOf(2, videoCapabilities.widthAlignment), maxOf(2, videoCapabilities.heightAlignment),
                requestedFrameRate,
            ) { w, h, fps -> videoCapabilities.areSizeAndRateSupported(w, h, fps.toDouble()) }
            val bitrate = (width.toLong() * height * 4).coerceIn(750_000, 10_000_000)
                .coerceIn(videoCapabilities.bitrateRange.lower.toLong(), videoCapabilities.bitrateRange.upper.toLong())
            val encoderFormat = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
                setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
                setInteger(MediaFormat.KEY_BIT_RATE, bitrate.toInt())
                setInteger(MediaFormat.KEY_FRAME_RATE, frameRate)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
                // API 24's MP4 writer cannot accept B-frames, including encoded ones.
                if (Build.VERSION.SDK_INT < 25) {
                    setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline)
                }
            }
            activeEncoder.configure(encoderFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            val activeSurface = ChatBackgroundVideoSurface(activeEncoder.createInputSurface(), width, height)
            surface = activeSurface
            activeEncoder.start()
            val activeDecoder = MediaCodec.createDecoderByType(sourceFormat.getString(MediaFormat.KEY_MIME)!!)
            decoder = activeDecoder
            // Surface decoder rotation is disabled; the muxer retains the original orientation.
            sourceFormat.setInteger(MediaFormat.KEY_ROTATION, 0)
            activeDecoder.configure(sourceFormat, activeSurface.decoderSurface, null, 0)
            activeDecoder.start()
            val activeMuxer = MediaMuxer(output.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = activeMuxer
            activeMuxer.setOrientationHint(rotation)
            var outputTrack = -1
            val encodedInfo = MediaCodec.BufferInfo()
            val decodedInfo = MediaCodec.BufferInfo()
            var inputEnded = false
            var decoderEnded = false
            var encoderEnded = false
            var firstPresentationTime: Long? = null
            var lastFrameSlot = -1L
            var lastProgress = SystemClock.elapsedRealtime()

            fun drainEncoder(wait: Boolean) {
                while (!encoderEnded) {
                    val index = activeEncoder.dequeueOutputBuffer(encodedInfo, if (wait) 10_000L else 0L)
                    if (index == MediaCodec.INFO_TRY_AGAIN_LATER) return
                    if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        check(!muxerStarted)
                        outputTrack = activeMuxer.addTrack(activeEncoder.outputFormat)
                        activeMuxer.start()
                        muxerStarted = true
                    } else if (index >= 0) {
                        try {
                            if (encodedInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) encodedInfo.size = 0
                            if (encodedInfo.size > 0) {
                                check(muxerStarted)
                                val bytes = activeEncoder.getOutputBuffer(index)!!
                                bytes.position(encodedInfo.offset)
                                bytes.limit(encodedInfo.offset + encodedInfo.size)
                                activeMuxer.writeSampleData(outputTrack, bytes, encodedInfo)
                            }
                            encoderEnded = encodedInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                            lastProgress = SystemClock.elapsedRealtime()
                        } finally {
                            activeEncoder.releaseOutputBuffer(index, false)
                        }
                    }
                }
            }

            while (!encoderEnded) {
                drainEncoder(decoderEnded)
                if (!inputEnded) {
                    val index = activeDecoder.dequeueInputBuffer(10_000)
                    if (index >= 0) {
                        val bytes = activeDecoder.getInputBuffer(index)!!
                        bytes.clear()
                        val size = extractor.readSampleData(bytes, 0)
                        if (size < 0) {
                            activeDecoder.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputEnded = true
                        } else {
                            require(extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_ENCRYPTED == 0)
                            activeDecoder.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                        lastProgress = SystemClock.elapsedRealtime()
                    }
                }
                if (!decoderEnded) {
                    val index = activeDecoder.dequeueOutputBuffer(decodedInfo, 10_000)
                    if (index >= 0) {
                        val origin = firstPresentationTime
                        val slot = if (origin == null) 0L else {
                            ChatBackgroundVideoSize.frameSlot(
                                decodedInfo.presentationTimeUs, origin, frameRate,
                            )
                        }
                        val render = decodedInfo.size > 0 && slot > lastFrameSlot
                        activeDecoder.releaseOutputBuffer(index, render)
                        if (render) {
                            val initialTime = firstPresentationTime ?: decodedInfo.presentationTimeUs.also {
                                firstPresentationTime = it
                            }
                            lastFrameSlot = slot
                            activeSurface.draw(
                                ChatBackgroundVideoSize.normalizedTime(decodedInfo.presentationTimeUs, initialTime) * 1000,
                            )
                        }
                        if (decodedInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            activeEncoder.signalEndOfInputStream()
                            decoderEnded = true
                        }
                        lastProgress = SystemClock.elapsedRealtime()
                    }
                }
                check(SystemClock.elapsedRealtime() - lastProgress < 30_000) { "Video preparation stalled." }
            }
            check(muxerStarted && firstPresentationTime != null)
            activeMuxer.stop()
            muxerStarted = false
        } finally {
            decoder?.let { runCatching { it.stop() }; runCatching { it.release() } }
            encoder?.let { runCatching { it.stop() }; runCatching { it.release() } }
            surface?.let { runCatching { it.close() } }
            muxer?.let {
                if (muxerStarted) runCatching { it.stop() }
                runCatching { it.release() }
            }
        }
    }
}
