package com.termisol

import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class MainActivity : FlutterActivity() {
    private val TAG = "Termisol"
    private val CHANNEL = "com.termisol/vr"
    private val HAND_TRACKING_CHANNEL = "com.termisol/vr/hand_tracking"
    private val EYE_TRACKING_CHANNEL = "com.termisol/vr/eye_tracking"
    private val DEVICE_DETECTION_CHANNEL = "com.termisol/vr/device_detection"

    private var handTrackingSink: EventChannel.EventSink? = null
    private var eyeTrackingSink: EventChannel.EventSink? = null
    private var deviceDetectionSink: EventChannel.EventSink? = null

    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

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

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, HAND_TRACKING_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    handTrackingSink = events
                }
                override fun onCancel(arguments: Any?) {
                    handTrackingSink = null
                }
            }
        )

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EYE_TRACKING_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eyeTrackingSink = events
                }
                override fun onCancel(arguments: Any?) {
                    eyeTrackingSink = null
                }
            }
        )

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
        return mapOf(
            "deviceType" to "android",
            "supportsHandTracking" to false,
            "supportsEyeTracking" to false,
            "supportsSpatialAudio" to false,
            "displayRefreshRate" to 60.0
        )
    }

    private fun sendDeviceInfo() {
        scope.launch {
            try {
                deviceDetectionSink?.success(getDeviceInfo())
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send device info", e)
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
    }
}
