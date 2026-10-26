package com.orchestrsim.blackhole.model

import android.content.Context
import android.app.ActivityManager

/**
 * Visual-quality budget for the render pipeline. Values mirror the iOS/macOS
 * `QualityPreset` (ray steps 32/64/128/256, render scale, TAA, bloom).
 */
enum class QualityPreset(
    val displayName: String,
    val maxRaySteps: Int,
    val renderScale: Float,
    val taaEnabled: Boolean,
    val bloomEnabled: Boolean
) {
    LOW("Low", 32, 0.5f, false, false),
    MEDIUM("Medium", 64, 0.75f, true, false),
    HIGH("High", 128, 1.0f, true, true),
    ULTRA("Ultra", 256, 1.0f, true, true);

    companion object {
        /** Conservative per-device default; user can crank it up in Controls. */
        fun autoDetected(context: Context): QualityPreset {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val mem = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
            val gb = mem.totalMem / (1024.0 * 1024.0 * 1024.0)
            return when {
                am.isLowRamDevice || gb < 3.0 -> LOW
                gb < 6.0 -> MEDIUM
                else -> HIGH
            }
        }
    }
}
