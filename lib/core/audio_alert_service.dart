import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Audio alert service for long-running command completion and Hermes agent TUI.
///
/// Plays notif.mp3 when:
/// - A command runs for longer than 50 seconds and finishes
/// - The Hermes agent TUI finishes its output (stops streaming responses)
class AudioAlertService {
  static final AudioAlertService _instance = AudioAlertService._();
  factory AudioAlertService() => _instance;
  AudioAlertService._();

  final MethodChannel _channel = const MethodChannel('com.termisol/audio');

  Timer? _commandTimer;
  Timer? _streamingCheckTimer;
  DateTime? _commandStartTime;
  bool _wasStreaming = false;
  int _consecutiveEmptyChecks = 0;
  static const int _requiredEmptyChecks = 3; // Number of checks before considering streaming done
  static const int _streamingCheckIntervalMs = 2000; // Check every 2 seconds
  static const int _longCommandThresholdSeconds = 50;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Initialize the audio alert service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _channel.invokeMethod('initAudio');
      _isInitialized = true;
      debugPrint('🔔 Audio Alert Service initialized');
    } catch (e) {
      debugPrint('⚠️ Audio Alert Service init failed (no audio backend): $e');
      _isInitialized = true; // Still mark as initialized, just silent
    }
  }

  /// Notify that a command has started executing.
  void onCommandStarted() {
    if (!_isInitialized) return;

    _commandStartTime = DateTime.now();
    _commandTimer?.cancel();

    // Check periodically if the command has exceeded the long-running threshold
    _commandTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_commandStartTime != null) {
        final elapsed = DateTime.now().difference(_commandStartTime!);
        if (elapsed.inSeconds >= _longCommandThresholdSeconds) {
          // Mark as long-running so we alert when it finishes
          debugPrint('🔔 Command exceeded ${_longCommandThresholdSeconds}s threshold');
        }
      }
    });
  }

  /// Notify that a command has finished executing.
  void onCommandFinished() {
    if (!_isInitialized) return;

    _commandTimer?.cancel();

    if (_commandStartTime != null) {
      final elapsed = DateTime.now().difference(_commandStartTime!);
      if (elapsed.inSeconds >= _longCommandThresholdSeconds) {
        _playNotification();
        debugPrint('🔔 Long-running command finished after ${elapsed.inSeconds}s');
      }
      _commandStartTime = null;
    }
  }

  /// Notify that the Hermes agent TUI is outputting/streaming.
  void onHermesOutput() {
    if (!_isInitialized) return;

    _wasStreaming = true;
    _consecutiveEmptyChecks = 0;

    // Start/reset the streaming check timer
    _streamingCheckTimer?.cancel();
    _streamingCheckTimer = Timer.periodic(
      Duration(milliseconds: _streamingCheckIntervalMs),
      (_) => _checkHermesStreaming(),
    );
  }

  /// Notify that the Hermes agent received a chunk of output.
  void onHermesChunkReceived() {
    if (!_isInitialized) return;

    _wasStreaming = true;
    _consecutiveEmptyChecks = 0;
  }

  /// Check if Hermes has stopped streaming.
  void _checkHermesStreaming() {
    if (!_wasStreaming) {
      _consecutiveEmptyChecks++;
      if (_consecutiveEmptyChecks >= _requiredEmptyChecks) {
        // Hermes has stopped streaming - play notification
        _streamingCheckTimer?.cancel();
        _wasStreaming = false;
        _consecutiveEmptyChecks = 0;
        _playNotification();
        debugPrint('🔔 Hermes agent finished outputting');
      }
    } else {
      _wasStreaming = false; // Reset for next check interval
    }
  }

  /// Manually mark Hermes as done (e.g., from a "done" message).
  void onHermesFinished() {
    if (!_isInitialized) return;

    _streamingCheckTimer?.cancel();
    if (_wasStreaming || _consecutiveEmptyChecks > 0) {
      _playNotification();
      _wasStreaming = false;
      _consecutiveEmptyChecks = 0;
      debugPrint('🔔 Hermes agent explicitly marked as finished');
    }
  }

  /// Play the notification sound.
  Future<void> _playNotification() async {
    try {
      await _channel.invokeMethod('playNotif');
    } catch (e) {
      debugPrint('⚠️ Failed to play notification: $e');
    }
  }

  /// Play notification immediately (for manual triggers).
  Future<void> playNow() async {
    await _playNotification();
  }

  /// Cancel all active monitoring.
  void cancelAll() {
    _commandTimer?.cancel();
    _streamingCheckTimer?.cancel();
    _commandStartTime = null;
    _wasStreaming = false;
    _consecutiveEmptyChecks = 0;
  }

  /// Dispose resources.
  void dispose() {
    cancelAll();
    _isInitialized = false;
  }
}