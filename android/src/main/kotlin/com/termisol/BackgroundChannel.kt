package com.termisol

import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class BackgroundChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "com.termisol/background"
        const val ACTION_START_SERVICE = "start_service"
        const val ACTION_STOP_SERVICE = "stop_service"
        const val ACTION_SETUP_TRAY = "setup_tray"
    }

    private var methodChannel: MethodChannel? = null

    fun initialize(flutterEngine: FlutterEngine) {
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        methodChannel?.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            ACTION_START_SERVICE -> {
                try {
                    val intent = Intent(context, BackgroundService::class.java)
                    context.startForegroundService(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("SERVICE_START_ERROR", e.message, null)
                }
            }
            
            ACTION_STOP_SERVICE -> {
                try {
                    val intent = Intent(context, BackgroundService::class.java)
                    context.stopService(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("SERVICE_STOP_ERROR", e.message, null)
                }
            }
            
            ACTION_SETUP_TRAY -> {
                // Android doesn't have system tray like desktop, use notification instead
                setupNotificationTray(call.arguments as? Map<String, Any>)
                result.success(true)
            }
            
            "isScreenReaderOn" -> {
                val isScreenReaderOn = isAccessibilityServiceEnabled()
                result.success(isScreenReaderOn)
            }
            
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun setupNotificationTray(config: Map<String, Any>?) {
        // Implementation for notification-based tray on Android
        val intent = Intent(context, MainActivity::class.java)
        // Create notification with actions
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        // Check if TalkBack or other accessibility services are enabled
        return try {
            val accessibilityEnabled = android.provider.Settings.Secure.getInt(
                context.contentResolver,
                android.provider.Settings.Secure.ACCESSIBILITY_ENABLED
            )
            accessibilityEnabled == 1
        } catch (e: Exception) {
            false
        }
    }
}