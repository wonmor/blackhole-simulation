package com.orchestrsim.blackhole

import android.annotation.SuppressLint
import android.content.Context
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.SurfaceHolder
import android.view.SurfaceView
import com.orchestrsim.blackhole.model.SimState

/**
 * Hosts the native Vulkan surface and translates touch into camera moves.
 * Drag → yaw/pitch, pinch → zoom, matching the iOS gesture mapping.
 */
@SuppressLint("ViewConstructor")
class BlackHoleSurfaceView(context: Context, private val sim: SimState) :
    SurfaceView(context), SurfaceHolder.Callback {

    private var zoomBaseline = 100.0f
    private var totalScale = 1.0f

    private val dragDetector = GestureDetector(context,
        object : GestureDetector.SimpleOnGestureListener() {
            override fun onDown(e: MotionEvent) = true
            override fun onScroll(
                e1: MotionEvent?, e2: MotionEvent,
                distanceX: Float, distanceY: Float
            ): Boolean {
                val s = minOf(width, height).coerceAtLeast(1).toFloat()
                // distanceX/Y are (old - new); finger movement is the negation.
                sim.yaw = wrap01(sim.yaw + (-distanceX) / s)
                sim.pitch = (sim.pitch + (-distanceY) / s * 0.9f).coerceIn(0.05f, 0.95f)
                sim.pushCamera()
                return true
            }
        })

    private val scaleDetector = ScaleGestureDetector(context,
        object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScaleBegin(d: ScaleGestureDetector): Boolean {
                zoomBaseline = sim.zoom
                totalScale = 1.0f
                return true
            }
            override fun onScale(d: ScaleGestureDetector): Boolean {
                totalScale *= d.scaleFactor
                sim.zoom = (zoomBaseline / totalScale.coerceAtLeast(0.1f))
                    .coerceIn(1.5f, 100.0f)
                sim.pushCamera()
                return true
            }
        })

    init {
        holder.addCallback(this)
        isFocusable = true
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        scaleDetector.onTouchEvent(event)
        // Suppress single-finger drag while pinching to avoid camera fighting.
        if (!scaleDetector.isInProgress) dragDetector.onTouchEvent(event)
        return true
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        NativeBridge.nativeOnSurfaceCreated(holder.surface)
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, w: Int, h: Int) {
        NativeBridge.nativeOnSurfaceChanged(w, h)
        sim.pushParams()
        sim.pushCamera()
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        NativeBridge.nativeOnSurfaceDestroyed()
    }

    private fun wrap01(x: Float): Float {
        var v = x % 1.0f
        if (v < 0f) v += 1.0f
        return v
    }
}
