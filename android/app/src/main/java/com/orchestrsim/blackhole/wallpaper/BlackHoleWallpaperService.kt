package com.orchestrsim.blackhole.wallpaper

import android.service.wallpaper.WallpaperService
import android.view.SurfaceHolder
import com.orchestrsim.blackhole.NativeBridge
import com.orchestrsim.blackhole.billing.ProManager

/**
 * BlackHole live wallpaper (a Pro perk). Runs in its own `:wallpaper`
 * process, so the native renderer singleton here never competes with the
 * app's. The system can hold two engines at once (the picker preview and the
 * active wallpaper); whichever is visible owns the renderer.
 *
 * Without Pro the picker preview still animates, so people can see what they
 * would get, but an applied wallpaper holds a still frame (no rotation, about
 * one frame a second) until Pro is unlocked.
 */
class BlackHoleWallpaperService : WallpaperService() {

    override fun onCreateEngine(): Engine = BhEngine()

    private var owner: BhEngine? = null

    inner class BhEngine : Engine() {
        private var holderRef: SurfaceHolder? = null
        private var width = 0
        private var height = 0
        private var params = WallpaperParams.default()
        private var paramsStamp = -1L

        override fun onCreate(surfaceHolder: SurfaceHolder) {
            super.onCreate(surfaceHolder)
            setTouchEventsEnabled(false)
            setOffsetNotificationsEnabled(false)
        }

        override fun onSurfaceCreated(holder: SurfaceHolder) {
            super.onSurfaceCreated(holder)
            holderRef = holder
        }

        override fun onSurfaceChanged(holder: SurfaceHolder, format: Int, w: Int, h: Int) {
            super.onSurfaceChanged(holder, format, w, h)
            holderRef = holder; width = w; height = h
            if (owner === this) {
                NativeBridge.nativeOnSurfaceChanged(w, h)
                push()
            } else if (isVisible) {
                takeOver()
            }
        }

        override fun onVisibilityChanged(visible: Boolean) {
            super.onVisibilityChanged(visible)
            if (visible) {
                if (owner !== this) takeOver() else { reloadIfChanged(); push() }
                NativeBridge.nativeOnPause(false)
            } else if (owner === this) {
                NativeBridge.nativeOnPause(true)
            }
        }

        override fun onSurfaceDestroyed(holder: SurfaceHolder) {
            if (owner === this) {
                NativeBridge.nativeOnSurfaceDestroyed()
                owner = null
            }
            holderRef = null
            super.onSurfaceDestroyed(holder)
        }

        override fun onDestroy() {
            if (owner === this) {
                NativeBridge.nativeOnSurfaceDestroyed()
                owner = null
            }
            super.onDestroy()
        }

        private fun takeOver() {
            val h = holderRef ?: return
            if (width == 0 || height == 0) return
            owner?.let { if (it !== this) NativeBridge.nativeOnSurfaceDestroyed() }
            owner = this
            reloadIfChanged(force = true)
            NativeBridge.nativeOnSurfaceCreated(h.surface)
            NativeBridge.nativeOnSurfaceChanged(width, height)
            push()
        }

        private fun reloadIfChanged(force: Boolean = false) {
            val stamp = WallpaperParams.lastModified(this@BlackHoleWallpaperService)
            if (force || stamp != paramsStamp) {
                params = WallpaperParams.load(this@BlackHoleWallpaperService)
                paramsStamp = stamp
            }
        }

        private fun animated(): Boolean = isPreview || ProManager.proFlag(this@BlackHoleWallpaperService)

        private fun push() {
            val f = params.f.copyOf()
            val anim = animated()
            if (!anim) { f[10] = 0f; f[15] = 0f }   // no camera spin, frozen disk
            NativeBridge.nativeSetFrameCap(if (anim) 30f else 1f)
            NativeBridge.nativeSetParams(f, params.i)
            NativeBridge.nativeSetCamera(params.yaw, params.pitch, params.zoom)
        }
    }
}
