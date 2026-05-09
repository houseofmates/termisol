package com.termisol

import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.termisol.vr.OpenXrBridge

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "Termisol"
        private const val VR_CHANNEL = "com.termisol/vr"
        private const val VR_EVENT_CHANNEL = "com.termisol/vr/events"
        private const val DEVICE_DETECTION_CHANNEL = "com.termisol/vr/device_detection"
    }

    private var deviceDetectionSink: EventChannel.EventSink? = null
    private var openXrBridge: OpenXrBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VR_CHANNEL)
        val eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, VR_EVENT_CHANNEL)
        openXrBridge = OpenXrBridge(this, methodChannel, eventChannel)

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

    private fun getBuildInfo(): Map<String, String> {
        return mapOf(
            "model" to (Build.MODEL ?: ""),
            "manufacturer" to (Build.MANUFACTURER ?: "")
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
