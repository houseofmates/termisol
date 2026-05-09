package com.termisol.vr

import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Bridges Dart VR method calls to the native Android/OpenXR implementation.
 *
 * Handles lifecycle methods (`initializeVr`, `startVrSession`, etc.) and
 * forwards controller input events back to Dart via an [EventChannel].
 */
class OpenXrBridge(
    private val context: Context,
    private val methodChannel: MethodChannel,
    private val eventChannel: EventChannel,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val isVrSupported = AtomicBoolean(false)
    private var eventSink: EventChannel.EventSink? = null

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        detectVrSupport()
    }

    private fun detectVrSupport() {
        val model = Build.MODEL ?: ""
        val manufacturer = Build.MANUFACTURER ?: ""
        isVrSupported.set(
            manufacturer.contains("Oculus", ignoreCase = true) ||
            manufacturer.contains("Meta", ignoreCase = true) ||
            model.contains("Quest", ignoreCase = true),
        )
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initializeVr" -> {
                result.success(mapOf("success" to true))
            }
            "isVrSupported" -> {
                result.success(isVrSupported.get())
            }
            "startVrSession" -> {
                if (isVrSupported.get()) {
                    val intent = Intent(context, VrActivity::class.java)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(intent)
                    result.success(true)
                } else {
                    result.success(false)
                }
            }
            "stopVrSession" -> {
                result.success(true)
            }
            "triggerHapticFeedback" -> {
                val duration = call.argument<Int>("duration") ?: 50
                // TODO: wire haptic feedback through to native OpenXR actions.
                result.success(null)
            }
            "getBuildInfo" -> {
                result.success(
                    mapOf(
                        "model" to Build.MODEL,
                        "manufacturer" to Build.MANUFACTURER,
                    ),
                )
            }
            "submitFrame" -> {
                val cells = call.argument<ByteArray>("cells")
                val rows = call.argument<Int>("rows") ?: 0
                val cols = call.argument<Int>("cols") ?: 0
                if (cells != null && rows > 0 && cols > 0) {
                    // TODO: forward to the active VrActivity instance.
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    /** Emit a controller input event to the Dart side. */
    fun sendInputEvent(type: String, x: Double, y: Double, button: Int) {
        eventSink?.success(
            mapOf(
                "type" to type,
                "x" to x,
                "y" to y,
                "button" to button,
            ),
        )
    }
}
