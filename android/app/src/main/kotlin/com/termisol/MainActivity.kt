package com.termisol

import android.content.Context
import android.content.pm.PackageManager
import android.os.Bundle
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.oculus.vrappframework.VrAppFramework
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class MainActivity : FlutterActivity() {
    private val TAG = "TermisolVR"
    private val CHANNEL = "com.termisol/vr"
    private val HAND_TRACKING_CHANNEL = "com.termisol/vr/hand_tracking"
    private val EYE_TRACKING_CHANNEL = "com.termisol/vr/eye_tracking"
    private val DEVICE_DETECTION_CHANNEL = "com.termisol/vr/device_detection"

    private var vrInitialized = false
    private var handTrackingSink: EventChannel.EventSink? = null
    private var eyeTrackingSink: EventChannel.EventSink? = null
    private var deviceDetectionSink: EventChannel.EventSink? = null

    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        checkVrPermissions()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initializeVr" -> initializeVr(result)
                "isVrSupported" -> result.success(isVrSupported())
                "startVrSession" -> startVrSession(result)
                "stopVrSession" -> stopVrSession(result)
                "triggerHapticFeedback" -> triggerHapticFeedback(call, result)
                else -> result.notImplemented()
            }
        }

        // Hand tracking event channel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, HAND_TRACKING_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    handTrackingSink = events
                    startHandTrackingUpdates()
                }

                override fun onCancel(arguments: Any?) {
                    handTrackingSink = null
                    stopHandTrackingUpdates()
                }
            }
        )

        // Eye tracking event channel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EYE_TRACKING_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eyeTrackingSink = events
                    startEyeTrackingUpdates()
                }

                override fun onCancel(arguments: Any?) {
                    eyeTrackingSink = null
                    stopEyeTrackingUpdates()
                }
            }
        )

        // Device detection event channel
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

    private fun checkVrPermissions() {
        val permissions = arrayOf(
            "com.oculus.permission.HAND_TRACKING",
            "com.oculus.permission.EYE_TRACKING"
        )

        val missingPermissions = permissions.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }

        if (missingPermissions.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, missingPermissions.toTypedArray(), 100)
        }
    }

    private fun isVrSupported(): Boolean {
        return packageManager.hasSystemFeature("android.hardware.vr.headtracking") &&
               packageManager.hasSystemFeature("oculus.software.handtracking")
    }

    private fun initializeVr(result: MethodChannel.Result) {
        try {
            if (!isVrSupported()) {
                result.success(mapOf(
                    "success" to false,
                    "error" to "VR not supported on this device"
                ))
                return
            }

            // Initialize VR framework
            // Note: In a full implementation, this would initialize the Oculus VR API
            // For now, we'll simulate successful initialization
            vrInitialized = true

            val deviceInfo = getDeviceInfo()
            result.success(mapOf(
                "success" to true,
                "deviceInfo" to deviceInfo
            ))

            Log.i(TAG, "VR initialized successfully")
        } catch (e: Exception) {
            Log.e(TAG, "VR initialization failed", e)
            result.success(mapOf(
                "success" to false,
                "error" to e.message
            ))
        }
    }

    private fun startVrSession(result: MethodChannel.Result) {
        try {
            if (!vrInitialized) {
                result.success(false)
                return
            }
            // In full implementation: enter VR mode via Oculus SDK
            result.success(true)
            Log.i(TAG, "VR session started")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start VR session", e)
            result.success(false)
        }
    }

    private fun stopVrSession(result: MethodChannel.Result) {
        try {
            if (!vrInitialized) {
                result.success(false)
                return
            }
            // In full implementation: exit VR mode via Oculus SDK
            result.success(true)
            Log.i(TAG, "VR session stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop VR session", e)
            result.success(false)
        }
    }

    private fun triggerHapticFeedback(call: MethodChannel.MethodCall, result: MethodChannel.Result) {
        try {
            val patternData = call.argument<Map<String, Any>>("pattern")
            if (patternData != null && vrInitialized) {
                val amplitude = (patternData["amplitude"] as? Double) ?: 1.0
                val pattern = (patternData["pattern"] as? List<Int>) ?: emptyList()

                // In full implementation: trigger haptic feedback via Oculus SDK
                Log.d(TAG, "Haptic feedback triggered with amplitude: $amplitude")
            }
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Haptic feedback failed", e)
            result.success(null) // Don't fail for haptic feedback
        }
    }

    private fun getDeviceInfo(): Map<String, Any> {
        val deviceType = when {
            packageManager.hasSystemFeature("oculus.hardware.quest_3s") -> "quest3s"
            packageManager.hasSystemFeature("oculus.hardware.quest_3") -> "quest3"
            packageManager.hasSystemFeature("oculus.hardware.quest_2") -> "quest2"
            else -> "quest" // Generic Quest device
        }

        return mapOf(
            "deviceType" to deviceType,
            "supportsHandTracking" to packageManager.hasSystemFeature("oculus.software.handtracking"),
            "supportsEyeTracking" to packageManager.hasSystemFeature("oculus.software.eyetracking"),
            "supportsSpatialAudio" to packageManager.hasSystemFeature("oculus.software.spatial_audio"),
            "displayRefreshRate" to 90.0 // Quest default
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

    private fun startHandTrackingUpdates() {
        scope.launch {
            while (handTrackingSink != null && vrInitialized) {
                try {
                    // In full implementation: get real hand tracking data from Oculus SDK
                    // For now, provide mock data that matches the expected structure
                    val mockHandData = mapOf(
                        "leftHand" to mapMockHandData(true, 200.0, 300.0),
                        "rightHand" to mapMockHandData(true, 600.0, 300.0),
                        "confidence" to 0.95
                    )
                    handTrackingSink?.success(mockHandData)
                    delay(16) // ~60fps
                } catch (e: Exception) {
                    Log.e(TAG, "Hand tracking update failed", e)
                    delay(1000) // Slow down on error
                }
            }
        }
    }

    private fun stopHandTrackingUpdates() {
        // Hand tracking stops when sink is null
    }

    private fun startEyeTrackingUpdates() {
        scope.launch {
            while (eyeTrackingSink != null && vrInitialized) {
                try {
                    // In full implementation: get real eye tracking data from Oculus SDK
                    // For now, provide mock data that matches the expected structure
                    val mockEyeData = mapOf(
                        "gazePosition" to mapOf("x" to 400.0, "y" to 300.0),
                        "pupilDilation" to 0.6,
                        "leftEyeBlink" to false,
                        "rightEyeBlink" to false,
                        "confidence" to 0.9
                    )
                    eyeTrackingSink?.success(mockEyeData)
                    delay(16) // ~60fps
                } catch (e: Exception) {
                    Log.e(TAG, "Eye tracking update failed", e)
                    delay(1000) // Slow down on error
                }
            }
        }
    }

    private fun stopEyeTrackingUpdates() {
        // Eye tracking stops when sink is null
    }

    private fun mapMockHandData(isLeft: Boolean, x: Double, y: Double): Map<String, Any> {
        // Mock hand data that matches Flutter expectations
        // In full implementation, this would map real Oculus SDK hand data
        val fingers = (0..4).map { fingerIndex ->
            mapOf(
                "type" to fingerIndex,
                "tipPosition" to mapOf("x" to x + fingerIndex * 20.0, "y" to y),
                "confidence" to 0.9
            )
        }

        return mapOf(
            "position" to mapOf("x" to x, "y" to y),
            "confidence" to 0.95,
            "gesture" to 1, // HandGesture.open
            "fingers" to fingers,
            "isTracked" to true
        )
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
        vrApi?.shutdown()
    }
}
