package com.termisol

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

    private var vrAppFramework: VrAppFramework? = null
    private var vrInitialized = false
    private var handTrackingSink: EventChannel.EventSink? = null
    private var eyeTrackingSink: EventChannel.EventSink? = null
    private var deviceDetectionSink: EventChannel.EventSink? = null

    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestVrPermissions()
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

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, HAND_TRACKING_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    handTrackingSink = events
                    startHandTrackingUpdates()
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
                    startEyeTrackingUpdates()
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

    private fun requestVrPermissions() {
        val permissions = arrayOf(
            "com.oculus.permission.HAND_TRACKING",
            "com.oculus.permission.EYE_TRACKING"
        )
        val missing = permissions.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, missing.toTypedArray(), 100)
        }
    }

    private fun isVrSupported(): Boolean {
        return packageManager.hasSystemFeature("android.hardware.vr.headtracking") &&
               packageManager.hasSystemFeature("oculus.software.handtracking")
    }

    private fun initializeVr(result: MethodChannel.Result) {
        try {
            if (!isVrSupported()) {
                result.success(mapOf("success" to false, "error" to "VR not supported on this device"))
                return
            }

            vrAppFramework = VrAppFramework()
            vrInitialized = true

            result.success(mapOf("success" to true, "deviceInfo" to getDeviceInfo()))
            Log.i(TAG, "VR initialized successfully")
        } catch (e: Exception) {
            Log.e(TAG, "VR initialization failed", e)
            result.success(mapOf("success" to false, "error" to e.message))
        }
    }

    private fun startVrSession(result: MethodChannel.Result) {
        try {
            if (!vrInitialized) {
                result.success(false)
                return
            }
            vrAppFramework?.enterVrMode(this)
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
            vrAppFramework?.exitVrMode()
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
                val amplitude = (patternData["amplitude"] as? Double)?.toFloat() ?: 1.0f
                vrAppFramework?.triggerHapticFeedback(amplitude)
                Log.d(TAG, "Haptic feedback triggered with amplitude: $amplitude")
            }
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Haptic feedback failed", e)
            result.success(null)
        }
    }

    private fun getDeviceInfo(): Map<String, Any> {
        val deviceType = when {
            packageManager.hasSystemFeature("oculus.hardware.quest_3s") -> "quest3s"
            packageManager.hasSystemFeature("oculus.hardware.quest_3") -> "quest3"
            packageManager.hasSystemFeature("oculus.hardware.quest_2") -> "quest2"
            else -> "quest"
        }
        return mapOf(
            "deviceType" to deviceType,
            "supportsHandTracking" to packageManager.hasSystemFeature("oculus.software.handtracking"),
            "supportsEyeTracking" to packageManager.hasSystemFeature("oculus.software.eyetracking"),
            "supportsSpatialAudio" to packageManager.hasSystemFeature("oculus.software.spatial_audio"),
            "displayRefreshRate" to 90.0
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
                    val handData = vrAppFramework?.pollHandTracking()
                    if (handData != null) {
                        handTrackingSink?.success(handData)
                    }
                    delay(16)
                } catch (e: Exception) {
                    Log.e(TAG, "Hand tracking update failed", e)
                    delay(1000)
                }
            }
        }
    }

    private fun startEyeTrackingUpdates() {
        scope.launch {
            while (eyeTrackingSink != null && vrInitialized) {
                try {
                    val eyeData = vrAppFramework?.pollEyeTracking()
                    if (eyeData != null) {
                        eyeTrackingSink?.success(eyeData)
                    }
                    delay(16)
                } catch (e: Exception) {
                    Log.e(TAG, "Eye tracking update failed", e)
                    delay(1000)
                }
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
        vrInitialized = false
        vrAppFramework?.shutdown()
    }
}