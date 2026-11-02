package com.orchestrsim.blackhole.wallpaper

import android.content.Context
import com.orchestrsim.blackhole.model.QualityPreset
import com.orchestrsim.blackhole.model.SimState
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * The look the live wallpaper renders, handed from the app process to the
 * wallpaper process (which runs separately, so it never touches the app's
 * SharedPreferences) as a small JSON file. Quality is capped for battery:
 * at most 128 ray steps and 75% render scale, at 30 fps.
 */
data class WallpaperParams(
    val f: FloatArray,        // NativeBridge.nativeSetParams float block (16)
    val i: IntArray,          // NativeBridge.nativeSetParams int block (4)
    val yaw: Float, val pitch: Float, val zoom: Float
) {
    fun save(ctx: Context) {
        val o = JSONObject()
            .put("f", JSONArray(f.map { it.toDouble() }))
            .put("i", JSONArray(i.toList()))
            .put("yaw", yaw.toDouble()).put("pitch", pitch.toDouble()).put("zoom", zoom.toDouble())
        val tmp = File(ctx.filesDir, "$FILE.tmp")
        tmp.writeText(o.toString())
        tmp.renameTo(File(ctx.filesDir, FILE))
    }

    companion object {
        const val FILE = "wallpaper.json"
        const val MAX_STEPS = 128
        const val MAX_SCALE = 0.75f

        fun from(sim: SimState): WallpaperParams {
            val p = sim.preset
            val f = floatArrayOf(
                sim.mass, sim.spin, sim.lensingStrength, sim.frameDragStrength,
                sim.diskDensity, sim.diskTemp, sim.diskSize, sim.diskScaleHeight,
                sim.bloomThreshold, sim.bloomIntensity,
                if (kotlin.math.abs(sim.autoSpin) < 0.002f) 0.01f else sim.autoSpin,
                sim.yaw, sim.pitch, sim.zoom, minOf(p.renderScale, MAX_SCALE), sim.diskSpeed
            )
            val i = intArrayOf(minOf(p.maxRaySteps, MAX_STEPS), sim.flagsMask(), 1, 1)
            return WallpaperParams(f, i, sim.yaw, sim.pitch, sim.zoom)
        }

        /** Default look when the app has never written one (Stellar-like). */
        fun default(): WallpaperParams {
            val hi = QualityPreset.HIGH
            return WallpaperParams(
                floatArrayOf(1f, 0.9f, 1f, 2f, 4f, 12000f, 45f, 0.15f, 1f, 0.45f, 0.01f,
                    0.5f, 0.52f, 32f, MAX_SCALE, 1f),
                intArrayOf(minOf(hi.maxRaySteps, MAX_STEPS), 0b0011111, 1, 1), 0.5f, 0.52f, 32f)
        }

        fun load(ctx: Context): WallpaperParams = runCatching {
            val o = JSONObject(File(ctx.filesDir, FILE).readText())
            val fa = o.getJSONArray("f"); val ia = o.getJSONArray("i")
            WallpaperParams(
                FloatArray(fa.length()) { fa.getDouble(it).toFloat() },
                IntArray(ia.length()) { ia.getInt(it) },
                o.getDouble("yaw").toFloat(), o.getDouble("pitch").toFloat(), o.getDouble("zoom").toFloat())
        }.getOrElse { default() }

        fun lastModified(ctx: Context): Long = File(ctx.filesDir, FILE).lastModified()
    }

    override fun equals(other: Any?) = other is WallpaperParams && f.contentEquals(other.f) &&
        i.contentEquals(other.i) && yaw == other.yaw && pitch == other.pitch && zoom == other.zoom
    override fun hashCode() = f.contentHashCode() * 31 + i.contentHashCode()
}
