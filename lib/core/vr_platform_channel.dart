import 'dart:async';
import 'package:flutter/services.dart';

/// Platform channel for Quest VR functionality
/// Communicates with native Android Oculus Mobile SDK
class VrPlatformChannel {
  static const MethodChannel _channel = MethodChannel('com.termisol/vr');

  static const EventChannel _handTrackingChannel = EventChannel('com.termisol/vr/hand_tracking');
  static const EventChannel _eyeTrackingChannel = EventChannel('com.termisol/vr/eye_tracking');
  static const EventChannel _deviceDetectionChannel = EventChannel('com.termisol/vr/device_detection');

  static Stream<VrDeviceInfo>? _deviceDetectionStream;
  static Stream<HandTrackingData>? _handTrackingStream;
  static Stream<EyeTrackingData>? _eyeTrackingStream;

  /// Initialize VR system
  static Future<VrInitResult> initialize() async {
    try {
      final result = await _channel.invokeMethod('initializeVr');
      return VrInitResult.fromJson(result);
    } on PlatformException catch (e) {
      return VrInitResult(success: false, error: e.message);
    }
  }

  /// Check if device supports VR
  static Future<bool> isVrSupported() async {
    try {
      return await _channel.invokeMethod('isVrSupported');
    } catch (e) {
      return false;
    }
  }

  /// Start VR session
  static Future<bool> startVrSession() async {
    try {
      return await _channel.invokeMethod('startVrSession');
    } catch (e) {
      return false;
    }
  }

  /// Stop VR session
  static Future<void> stopVrSession() async {
    try {
      await _channel.invokeMethod('stopVrSession');
    } catch (e) {
      // Ignore errors when stopping
    }
  }

  /// Get device detection stream
  static Stream<VrDeviceInfo> get deviceDetectionStream {
    _deviceDetectionStream ??= _deviceDetectionChannel.receiveBroadcastStream().map((data) {
      return VrDeviceInfo.fromJson(data);
    });
    return _deviceDetectionStream!;
  }

  /// Get hand tracking stream
  static Stream<HandTrackingData> get handTrackingStream {
    _handTrackingStream ??= _handTrackingChannel.receiveBroadcastStream().map((data) {
      return HandTrackingData.fromJson(data);
    });
    return _handTrackingStream!;
  }

  /// Get eye tracking stream
  static Stream<EyeTrackingData> get eyeTrackingStream {
    _eyeTrackingStream ??= _eyeTrackingChannel.receiveBroadcastStream().map((data) {
      return EyeTrackingData.fromJson(data);
    });
    return _eyeTrackingStream!;
  }

  /// Trigger haptic feedback
  static Future<void> triggerHapticFeedback(HapticPattern pattern) async {
    try {
      await _channel.invokeMethod('triggerHapticFeedback', {
        'pattern': pattern.toJson(),
      });
    } catch (e) {
      // Haptic feedback failure is not critical
    }
  }
}

/// VR initialization result
class VrInitResult {
  final bool success;
  final String? error;
  final VrDeviceInfo? deviceInfo;

  VrInitResult({
    required this.success,
    this.error,
    this.deviceInfo,
  });

  factory VrInitResult.fromJson(dynamic json) {
    if (json is Map) {
      return VrInitResult(
        success: json['success'] ?? false,
        error: json['error'],
        deviceInfo: json['deviceInfo'] != null ? VrDeviceInfo.fromJson(json['deviceInfo']) : null,
      );
    }
    return VrInitResult(success: false, error: 'Invalid response');
  }
}

/// VR device information
class VrDeviceInfo {
  final String deviceType; // 'quest2', 'quest3', 'quest3s', etc.
  final bool supportsHandTracking;
  final bool supportsEyeTracking;
  final bool supportsSpatialAudio;
  final double displayRefreshRate;

  VrDeviceInfo({
    required this.deviceType,
    required this.supportsHandTracking,
    required this.supportsEyeTracking,
    required this.supportsSpatialAudio,
    required this.displayRefreshRate,
  });

  factory VrDeviceInfo.fromJson(Map<dynamic, dynamic> json) {
    return VrDeviceInfo(
      deviceType: json['deviceType'] ?? 'unknown',
      supportsHandTracking: json['supportsHandTracking'] ?? false,
      supportsEyeTracking: json['supportsEyeTracking'] ?? false,
      supportsSpatialAudio: json['supportsSpatialAudio'] ?? false,
      displayRefreshRate: (json['displayRefreshRate'] as num?)?.toDouble() ?? 72.0,
    );
  }
}

/// Hand tracking data
class HandTrackingData {
  final HandData leftHand;
  final HandData rightHand;
  final double confidence;

  HandTrackingData({
    required this.leftHand,
    required this.rightHand,
    required this.confidence,
  });

  factory HandTrackingData.fromJson(Map<dynamic, dynamic> json) {
    return HandTrackingData(
      leftHand: HandData.fromJson(json['leftHand'] ?? {}),
      rightHand: HandData.fromJson(json['rightHand'] ?? {}),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Individual hand data
class HandData {
  final Offset position;
  final double confidence;
  final HandGesture gesture;
  final List<FingerData> fingers;
  final bool isTracked;

  HandData({
    required this.position,
    required this.confidence,
    required this.gesture,
    required this.fingers,
    required this.isTracked,
  });

  factory HandData.fromJson(Map<dynamic, dynamic> json) {
    return HandData(
      position: Offset(
        (json['position']?['x'] as num?)?.toDouble() ?? 0.0,
        (json['position']?['y'] as num?)?.toDouble() ?? 0.0,
      ),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      gesture: HandGesture.values[json['gesture'] ?? 0],
      fingers: (json['fingers'] as List?)?.map((f) => FingerData.fromJson(f)).toList() ?? [],
      isTracked: json['isTracked'] ?? false,
    );
  }
}

/// Finger tracking data
class FingerData {
  final FingerType type;
  final Offset tipPosition;
  final double confidence;

  FingerData({
    required this.type,
    required this.tipPosition,
    required this.confidence,
  });

  factory FingerData.fromJson(Map<dynamic, dynamic> json) {
    return FingerData(
      type: FingerType.values[json['type'] ?? 0],
      tipPosition: Offset(
        (json['tipPosition']?['x'] as num?)?.toDouble() ?? 0.0,
        (json['tipPosition']?['y'] as num?)?.toDouble() ?? 0.0,
      ),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Finger types
enum FingerType {
  thumb,
  pointer,  // renamed from index to avoid conflict
  middle,
  ring,
  pinky,
}

/// Hand gestures
enum HandGesture {
  unknown,
  open,
  fist,
  pinch,
  point,
  thumbsUp,
  peace,
}

/// Eye tracking data
class EyeTrackingData {
  final Offset gazePosition;
  final double pupilDilation;
  final bool leftEyeBlink;
  final bool rightEyeBlink;
  final double confidence;

  EyeTrackingData({
    required this.gazePosition,
    required this.pupilDilation,
    required this.leftEyeBlink,
    required this.rightEyeBlink,
    required this.confidence,
  });

  factory EyeTrackingData.fromJson(Map<dynamic, dynamic> json) {
    return EyeTrackingData(
      gazePosition: Offset(
        (json['gazePosition']?['x'] as num?)?.toDouble() ?? 0.0,
        (json['gazePosition']?['y'] as num?)?.toDouble() ?? 0.0,
      ),
      pupilDilation: (json['pupilDilation'] as num?)?.toDouble() ?? 0.5,
      leftEyeBlink: json['leftEyeBlink'] ?? false,
      rightEyeBlink: json['rightEyeBlink'] ?? false,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Haptic feedback pattern
class HapticPattern {
  final String name;
  final List<int> pattern; // [delay_ms, duration_ms, delay_ms, duration_ms, ...]
  final double amplitude;

  HapticPattern({
    required this.name,
    required this.pattern,
    this.amplitude = 1.0,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'pattern': pattern,
      'amplitude': amplitude,
    };
  }
}