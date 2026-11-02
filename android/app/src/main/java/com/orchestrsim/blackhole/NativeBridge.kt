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

    /** Caps the render loop (live wallpaper uses 30); 0 = display rate. */
    external fun nativeSetFrameCap(fps: Float)

    // --- Offscreen export (4K poster, orbit video). Blocking; call off the UI thread. ---
    /** out: [yaw, pitch, zoom, time, diskTime] of the frame on screen. */
    external fun nativeExportCamera(out: FloatArray): Boolean
    /** Renders supersampling pass [passIndex] of [passCount]; fills [out] (w*h*4 RGBA) on the last. */
    external fun nativeExportPass(
        w: Int, h: Int, cam: FloatArray, raySteps: Int,
        passIndex: Int, passCount: Int, out: java.nio.ByteBuffer?
    ): Boolean
    external fun nativeExportEnd()
    external fun nativeRgbaToYuv(
        rgba: java.nio.ByteBuffer, w: Int, h: Int,
        y: java.nio.ByteBuffer, yRow: Int, yPix: Int,
        u: java.nio.ByteBuffer, uRow: Int, uPix: Int,
        v: java.nio.ByteBuffer, vRow: Int, vPix: Int
    ): Boolean

    // --- Rust Kerr observables (HUD) ---
    external fun nativeKerrHorizon(mass: Double, spin: Double): Double
    external fun nativeKerrPhotonSphere(mass: Double, spin: Double): Double
    external fun nativeKerrIsco(mass: Double, spin: Double, prograde: Boolean): Double
    external fun nativeKerrErgosphere(mass: Double, spin: Double, cosTheta: Double): Double
    external fun nativeGravitasVersion(): String
}
