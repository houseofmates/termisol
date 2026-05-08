package com.termisol

import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "Termisol"
        private const val CHANNEL = "com.termisol/vr"
        private const val DEVICE_DETECTION_CHANNEL = "com.termisol/vr/device_detection"
    }

    private var deviceDetectionSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initializeVr" -> result.success(mapOf("success" to false, "error" to "VR not supported on this build"))
                "isVrSupported" -> result.success(false)
                "startVrSession" -> result.success(false)
                "stopVrSession" -> result.success(false)
                "triggerHapticFeedback" -> result.success(null)
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_DETECTION_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    deviceDetectionSink = events
                    sendDeviceInfo()
                }
                override fun onCancel(arguments: Any?) {
                    deviceDetectionSink = null
                }
            }
        )
    }

    private fun getDeviceInfo(): Map<String, Any> {
        val display = windowManager.defaultDisplay
        val refreshRate = display.refreshRate
        return mapOf(
            "deviceType" to "android",
            "supportsHandTracking" to false,
            "supportsEyeTracking" to false,
            "supportsSpatialAudio" to false,
            "displayRefreshRate" to refreshRate
        )
    }

    private fun sendDeviceInfo() {
        try {
            deviceDetectionSink?.success(getDeviceInfo())
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send device info", e)
        }
    }
}
