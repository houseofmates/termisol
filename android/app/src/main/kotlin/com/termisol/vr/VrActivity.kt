package com.termisol.vr

import android.app.Activity
import android.graphics.Bitmap
import android.os.Bundle
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView

/**
 * Dedicated Android Activity that hosts the native OpenXR render loop.
 *
 * This activity creates a [SurfaceView], passes its [Surface] to the native
 * layer via JNI, and lets the C++ side drive the EGL + OpenXR frame loop.
 */
class VrActivity : Activity(), SurfaceHolder.Callback {

    companion object {
        init {
            System.loadLibrary("termisol_vr")
        }
    }

    private external fun nativeOnCreate(surface: Surface)
    private external fun nativeOnDestroy()
    private external fun nativeStartVR()
    private external fun nativeUpdateTerminalTexture(bitmap: Bitmap)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val surfaceView = SurfaceView(this)
        surfaceView.holder.addCallback(this)
        setContentView(surfaceView)
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        nativeOnCreate(holder.surface)
        nativeStartVR()
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        // No-op: native renderer queries swapchain size from OpenXR.
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        nativeOnDestroy()
    }

    override fun onDestroy() {
        nativeOnDestroy()
        super.onDestroy()
    }

    /** Forward a rendered terminal bitmap to the native VR renderer. */
    fun updateTerminalTexture(bitmap: Bitmap) {
        nativeUpdateTerminalTexture(bitmap)
    }
}
