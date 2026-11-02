package com.orchestrsim.blackhole.model

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.orchestrsim.blackhole.NativeBridge

/**
 * Observable simulation parameters + persistence, mirroring the iOS
 * `BlackHoleParameters`. Camera pose (yaw/pitch/zoom) is intentionally NOT
 * persisted — it drifts every frame via auto-spin. Any setter pushes the full
 * param block to the native renderer.
 */
class SimState(context: Context) {
    private val prefs = context.getSharedPreferences("bh.params", Context.MODE_PRIVATE)

    // Geometry
    var mass by persistFloat("mass", 1.0f)
    var spin by persistFloat("spin", 0.5f)
    var lensingStrength by persistFloat("lens", 0.7f)
    var frameDragStrength by persistFloat("frameDrag", 2.0f)

    // Disk
    var diskDensity by persistFloat("diskDensity", 4.0f)
    var diskTemp by persistFloat("diskTemp", 9500.0f)
    var diskSize by persistFloat("diskSize", 50.0f)
    var diskScaleHeight by persistFloat("diskScale", 0.2f)
    /** Disk rotation speed multiplier: 0 freezes the disk, 1 is the default. */
    var diskSpeed by persistFloat("diskSpeed", 1.0f)

    // Camera (not persisted)
    var zoom by mutableStateOf(100.0f)
    var yaw by mutableStateOf(0.5f)
    var pitch by mutableStateOf(0.539f)
    var autoSpin by persistFloat("autoSpin", 0.005f)

    // Pipeline
    var preset by mutableStateOf(QualityPreset.autoDetected(context))
    var bloomThreshold by persistFloat("bloomThr", 1.0f)
    var bloomIntensity by persistFloat("bloomInt", 0.45f)

    // Feature toggles
    var enableLensing by persistBool("enLens", true)
    var enableDisk by persistBool("enDisk", true)
    var enableStars by persistBool("enStars", true)
    var enablePhotonGlow by persistBool("enPhoton", true)
    var enableDoppler by persistBool("enDoppler", true)
    var enableJets by persistBool("enJets", false)
    var showRedshift by persistBool("showRedshift", false)

    init {
        prefs.getString("preset", null)?.let { raw ->
            runCatching { preset = QualityPreset.valueOf(raw) }
        }
    }

    fun flagsMask(): Int {
        var m = 0
        if (enableLensing) m = m or (1 shl 0)
        if (enableDisk) m = m or (1 shl 1)
        if (enableDoppler) m = m or (1 shl 2)
        if (enablePhotonGlow) m = m or (1 shl 3)
        if (enableStars) m = m or (1 shl 4)
        if (enableJets) m = m or (1 shl 5)
        if (showRedshift) m = m or (1 shl 6)
        return m
    }

    /** Push the full (non-camera) parameter block to the native renderer. */
    fun pushParams() {
        val f = floatArrayOf(
            mass, spin, lensingStrength, frameDragStrength,
            diskDensity, diskTemp, diskSize, diskScaleHeight,
            bloomThreshold, bloomIntensity, autoSpin,
            yaw, pitch, zoom, preset.renderScale, diskSpeed
        )
        val i = intArrayOf(
            preset.maxRaySteps,
            flagsMask(),
            if (preset.taaEnabled) 1 else 0,
            if (preset.bloomEnabled) 1 else 0
        )
        NativeBridge.nativeSetParams(f, i)
    }

    fun pushCamera() = NativeBridge.nativeSetCamera(yaw, pitch, zoom)

    /** Free users can't land on a Pro preset via a scenario or lesson. */
    private fun clampPreset(allowPro: Boolean) {
        if (!allowPro && preset.isPro) preset = QualityPreset.HIGH
    }

    fun applyScenario(s: Scenario, allowPro: Boolean) {
        s.apply(this)
        clampPreset(allowPro)
        prefs.edit().putString("preset", preset.name).apply()
        pushParams()
        pushCamera()
    }

    fun applyLesson(l: Lesson, allowPro: Boolean) {
        l.apply(this)
        clampPreset(allowPro)
        prefs.edit().putString("preset", preset.name).apply()
        pushParams()
        pushCamera()
    }

    /** Reset every parameter to factory defaults (the iOS reset button). */
    fun resetToDefaults(allowPro: Boolean) {
        mass = 1.0f; spin = 0.5f; lensingStrength = 0.7f; frameDragStrength = 2.0f
        diskDensity = 4.0f; diskTemp = 9500.0f; diskSize = 50.0f; diskScaleHeight = 0.2f; diskSpeed = 1.0f
        zoom = 100.0f; yaw = 0.5f; pitch = 0.539f; autoSpin = 0.005f
        bloomThreshold = 1.0f; bloomIntensity = 0.45f
        enableLensing = true; enableDisk = true; enableStars = true; enablePhotonGlow = true
        enableDoppler = true; enableJets = false; showRedshift = false
        clampPreset(allowPro)
        pushParams(); pushCamera()
    }

    fun selectPreset(p: QualityPreset) {
        preset = p
        prefs.edit().putString("preset", p.name).apply()
        pushParams()
    }

    // ---- persistence-backed Compose state delegates ----
    private fun persistFloat(key: String, default: Float) =
        object {
            private val state = mutableStateOf(prefs.getFloat(key, default))
            operator fun getValue(t: Any?, p: Any?) = state.value
            operator fun setValue(t: Any?, p: Any?, v: Float) {
                state.value = v
                prefs.edit().putFloat(key, v).apply()
            }
        }

    private fun persistBool(key: String, default: Boolean) =
        object {
            private val state = mutableStateOf(prefs.getBoolean(key, default))
            operator fun getValue(t: Any?, p: Any?) = state.value
            operator fun setValue(t: Any?, p: Any?, v: Boolean) {
                state.value = v
                prefs.edit().putBoolean(key, v).apply()
            }
        }
}
