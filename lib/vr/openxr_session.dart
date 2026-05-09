import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Exception thrown when an OpenXR operation fails.
class OpenXrException implements Exception {
  final String message;
  OpenXrException(this.message);
  @override
  String toString() => 'OpenXrException: $message';
}

/// Types of input events that can be emitted by VR controllers.
enum VrInputType { trigger, thumbstick, grip, menu }

/// A single input event from a VR controller.
class VrInputEvent {
  final VrInputType type;
  final double x;
  final double y;
  final int button;

  const VrInputEvent({
    required this.type,
    required this.x,
    required this.y,
    required this.button,
  });

  factory VrInputEvent.fromMap(Map<dynamic, dynamic> map) {
    return VrInputEvent(
      type: VrInputType.values.byName(map['type'] as String),
      x: (map['x'] as num?)?.toDouble() ?? 0.0,
      y: (map['y'] as num?)?.toDouble() ?? 0.0,
      button: map['button'] as int? ?? 0,
    );
  }
}

/// Encapsulates a snapshot of the terminal grid to be rendered in VR.
class VrTerminalFrame {
  final int rows;
  final int cols;
  final Uint8List cells;

  const VrTerminalFrame({
    required this.rows,
    required this.cols,
    required this.cells,
  });
}

/// Manages the lifecycle of the native OpenXR session and provides a typed
/// interface over the `com.termisol/vr` platform channel.
class OpenXrSession {
  static const MethodChannel _channel = MethodChannel('com.termisol/vr');
  static const EventChannel _eventChannel = EventChannel('com.termisol/vr/events');

  static Stream<VrInputEvent>? _inputStream;

  /// Initialize the native OpenXR runtime.
  static Future<bool> initialize() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('initializeVr');
      return result?['success'] as bool? ?? false;
    } on PlatformException catch (e) {
      throw OpenXrException('initialization failed: ${e.message}');
    }
  }

  /// Query whether the current device supports VR.
  static Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isVrSupported') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Start a VR session. On Android this launches the native [VrActivity].
  static Future<bool> startSession() async {
    try {
      return await _channel.invokeMethod<bool>('startVrSession') ?? false;
    } on PlatformException catch (e) {
      throw OpenXrException('failed to start session: ${e.message}');
    }
  }

  /// Stop the current VR session.
  static Future<void> stopSession() async {
    await _channel.invokeMethod('stopVrSession');
  }

  /// Submit a terminal frame to the native VR renderer.
  static Future<void> submitFrame(VrTerminalFrame frame) async {
    await _channel.invokeMethod('submitFrame', <String, dynamic>{
      'rows': frame.rows,
      'cols': frame.cols,
      'cells': frame.cells,
    });
  }

  /// Stream of controller input events from the native runtime.
  static Stream<VrInputEvent> get inputEvents {
    _inputStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((dynamic data) => VrInputEvent.fromMap(data as Map<dynamic, dynamic>));
    return _inputStream!;
  }

  /// Trigger haptic feedback on the active controller.
  static Future<void> triggerHaptic({int durationMs = 50}) async {
    await _channel.invokeMethod('triggerHapticFeedback', durationMs);
  }
}
