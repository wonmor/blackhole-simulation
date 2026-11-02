package com.orchestrsim.blackhole.export

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.media.MediaMuxer
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.orchestrsim.blackhole.NativeBridge
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Pro exports, rendered offscreen by the Vulkan renderer at a fixed size
 * (independent of the screen) with the current settings and camera:
 *  - a supersampled 4K poster (3840 px long side, 500 ray steps, 16 passes);
 *  - a 12-second 360-degree orbit video (1080p, 30 fps, 256 steps, 2 passes).
 * Same budgets as the iOS ExportStudio.
 */
object ExportStudio {
    sealed class State {
        data object Idle : State()
        data class Rendering(val label: String, val progress: Float) : State()
        data object Saving : State()
        data class Done(val message: String) : State()
        data class Failed(val message: String) : State()
    }

    var state by mutableStateOf<State>(State.Idle); private set
    @Volatile private var cancelRequested = false

    const val POSTER_LONG_SIDE = 3840
    const val POSTER_PASSES = 16
    const val VIDEO_LONG_SIDE = 1920
    const val VIDEO_SECONDS = 12
    const val VIDEO_FPS = 30

    val isBusy: Boolean get() = state is State.Rendering || state == State.Saving

    fun cancel() { cancelRequested = true }
    fun reset() { if (!isBusy) state = State.Idle }

    /** Output size with the on-screen aspect ratio, both sides even. */
    fun exportSize(viewW: Int, viewH: Int, longSide: Int): Pair<Int, Int> {
        val aspect = (viewW.toDouble() / viewH.coerceAtLeast(1)).coerceIn(0.2, 5.0)
        val (w, h) = if (aspect >= 1) longSide to (longSide / aspect).toInt()
                     else (longSide * aspect).toInt() to longSide
        return (w and 1.inv()) to (h and 1.inv())
    }

    private fun camera(): FloatArray? {
        val cam = FloatArray(5)
        return if (NativeBridge.nativeExportCamera(cam)) cam else null
    }

    suspend fun exportPoster(ctx: Context, viewW: Int, viewH: Int) = withContext(Dispatchers.Default) {
        if (isBusy) return@withContext
        cancelRequested = false
        val (w, h) = exportSize(viewW, viewH, POSTER_LONG_SIDE)
        state = State.Rendering("Ray tracing $w x $h", 0f)
        val cam = camera() ?: run { state = State.Failed("The renderer isn't ready yet."); return@withContext }
        val buf = ByteBuffer.allocateDirect(w * h * 4).order(ByteOrder.nativeOrder())
        try {
            for (p in 0 until POSTER_PASSES) {
                if (cancelRequested) { state = State.Idle; return@withContext }
                val ok = NativeBridge.nativeExportPass(w, h, cam, 500, p, POSTER_PASSES,
                    if (p == POSTER_PASSES - 1) buf else null)
                if (!ok) { state = State.Failed("Not enough GPU memory for a $w x $h render."); return@withContext }
                state = State.Rendering("Ray tracing $w x $h", (p + 1f) / POSTER_PASSES)
            }
        } finally {
            NativeBridge.nativeExportEnd()
        }
        state = State.Saving
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        buf.rewind()
        bmp.copyPixelsFromBuffer(buf)
        val ok = MediaSaver.savePng(ctx, bmp, "BlackHole-4K-${System.currentTimeMillis()}.png")
        bmp.recycle()
        state = if (ok) State.Done("Saved a $w x $h poster to Pictures/BlackHole.")
                else State.Failed("Couldn't save the image.")
    }

    private fun encoderSupports(w: Int, h: Int): Boolean {
        val list = MediaCodecList(MediaCodecList.REGULAR_CODECS)
        return list.codecInfos.any { info ->
            info.isEncoder && info.supportedTypes.any { it.equals(MediaFormat.MIMETYPE_VIDEO_AVC, true) } &&
                runCatching {
                    info.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC).videoCapabilities.isSizeSupported(w, h)
                }.getOrDefault(false)
        }
    }

    suspend fun exportOrbitVideo(ctx: Context, viewW: Int, viewH: Int, diskSpeed: Float) = withContext(Dispatchers.Default) {
        if (isBusy) return@withContext
        cancelRequested = false
        var size = exportSize(viewW, viewH, VIDEO_LONG_SIDE)
        for (side in listOf(VIDEO_LONG_SIDE, 1280, 960)) {
            size = exportSize(viewW, viewH, side)
            if (encoderSupports(size.first, size.second)) break
        }
        val (w, h) = size
        val label = "Rendering $w x $h orbit"
        state = State.Rendering(label, 0f)
        val start = camera() ?: run { state = State.Failed("The renderer isn't ready yet."); return@withContext }
        val file = File(ctx.cacheDir, "BlackHole-orbit-${System.currentTimeMillis()}.mp4")

        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, w, h).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
            setInteger(MediaFormat.KEY_BIT_RATE, 16_000_000)
            setInteger(MediaFormat.KEY_FRAME_RATE, VIDEO_FPS)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        val codec = runCatching { MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC) }.getOrNull()
            ?: run { state = State.Failed("No H.264 encoder on this device."); return@withContext }
        var muxer: MediaMuxer? = null
        var track = -1
        var muxing = false
        val info = MediaCodec.BufferInfo()
        val rgba = ByteBuffer.allocateDirect(w * h * 4).order(ByteOrder.nativeOrder())

        fun drain(endOfStream: Boolean) {
            while (true) {
                val idx = codec.dequeueOutputBuffer(info, if (endOfStream) 10_000 else 0)
                when {
                    idx == MediaCodec.INFO_TRY_AGAIN_LATER -> if (!endOfStream) return
                    idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val m = MediaMuxer(file.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                        track = m.addTrack(codec.outputFormat)
                        m.start(); muxer = m; muxing = true
                    }
                    idx >= 0 -> {
                        val out = codec.getOutputBuffer(idx)!!
                        if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                        if (info.size > 0 && muxing) {
                            out.position(info.offset); out.limit(info.offset + info.size)
                            muxer!!.writeSampleData(track, out, info)
                        }
                        codec.releaseOutputBuffer(idx, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                    }
                }
            }
        }

        var failed: String? = null
        try {
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
            val frames = VIDEO_SECONDS * VIDEO_FPS
            val cam = start.copyOf()
            for (i in 0 until frames) {
                if (cancelRequested) break
                val t = i.toFloat() / frames
                cam[0] = (start[0] + t) % 1f
                cam[3] = start[3] + i.toFloat() / VIDEO_FPS
                cam[4] = start[4] + i.toFloat() / VIDEO_FPS * diskSpeed.coerceAtLeast(0f)
                if (!NativeBridge.nativeExportPass(w, h, cam, 256, 0, 2, null) ||
                    !NativeBridge.nativeExportPass(w, h, cam, 256, 1, 2, rgba)) {
                    failed = "Not enough GPU memory for a $w x $h render."; break
                }
                var inIdx: Int
                do { inIdx = codec.dequeueInputBuffer(10_000); if (inIdx < 0) drain(false) } while (inIdx < 0)
                val img = codec.getInputImage(inIdx)!!
                val pl = img.planes
                rgba.rewind()
                NativeBridge.nativeRgbaToYuv(rgba, w, h,
                    pl[0].buffer, pl[0].rowStride, pl[0].pixelStride,
                    pl[1].buffer, pl[1].rowStride, pl[1].pixelStride,
                    pl[2].buffer, pl[2].rowStride, pl[2].pixelStride)
                codec.queueInputBuffer(inIdx, 0, w * h * 3 / 2, i * 1_000_000L / VIDEO_FPS, 0)
                drain(false)
                state = State.Rendering(label, (i + 1f) / frames)
            }
            if (failed == null && !cancelRequested) {
                var inIdx: Int
                do { inIdx = codec.dequeueInputBuffer(10_000); if (inIdx < 0) drain(false) } while (inIdx < 0)
                codec.queueInputBuffer(inIdx, 0, 0, frames * 1_000_000L / VIDEO_FPS, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                drain(true)
            }
        } catch (e: Exception) {
            failed = e.message ?: "Video encoding failed."
        } finally {
            NativeBridge.nativeExportEnd()
            runCatching { codec.stop() }
            codec.release()
            runCatching { if (muxing) muxer?.stop() }
            runCatching { muxer?.release() }
        }
        if (cancelRequested) { file.delete(); state = State.Idle; return@withContext }
        if (failed != null) { file.delete(); state = State.Failed(failed!!); return@withContext }
        state = State.Saving
        val ok = MediaSaver.saveMp4(ctx, file, file.name)
        file.delete()
        state = if (ok) State.Done("Saved a $VIDEO_SECONDS-second $w x $h orbit video to Movies/BlackHole.")
                else State.Failed("Couldn't save the video.")
    }
}
