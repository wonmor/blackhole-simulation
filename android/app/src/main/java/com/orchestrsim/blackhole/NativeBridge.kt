package com.orchestrsim.blackhole

import android.view.Surface

/**
 * Thin JNI surface to the native Vulkan renderer (libblackhole.so) and the
 * Rust gravitas-ffi Kerr observables.
 */
object NativeBridge {
    init { System.loadLibrary("blackhole") }

    // --- Renderer lifecycle (called from the SurfaceHolder callbacks) ---
    external fun nativeOnSurfaceCreated(surface: Surface)
    external fun nativeOnSurfaceChanged(width: Int, height: Int)
    external fun nativeOnSurfaceDestroyed()
    external fun nativeOnPause(paused: Boolean)

    // --- Per-frame state ---
    // f: [mass, spin, lensing, frameDrag, diskDensity, diskTemp, diskSize,
    //     diskScaleHeight, bloomThreshold, bloomIntensity, autoSpin,
    //     (yaw), (pitch), (zoom), renderScale, spare]
    // i: [maxRaySteps, flagsMask, taaEnabled, bloomEnabled]
    external fun nativeSetParams(f: FloatArray, i: IntArray)
    external fun nativeSetCamera(yaw: Float, pitch: Float, zoom: Float)
    external fun nativeGetTelemetry(out: FloatArray)   // [fps, frameTimeMs, effectiveScale]

    // --- Rust Kerr observables (HUD) ---
    external fun nativeKerrHorizon(mass: Double, spin: Double): Double
    external fun nativeKerrPhotonSphere(mass: Double, spin: Double): Double
    external fun nativeKerrIsco(mass: Double, spin: Double, prograde: Boolean): Double
    external fun nativeKerrErgosphere(mass: Double, spin: Double, cosTheta: Double): Double
    external fun nativeGravitasVersion(): String
}
