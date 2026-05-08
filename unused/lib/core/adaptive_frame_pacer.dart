import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Adaptive frame pacer that dynamically adjusts frame timing for optimal performance.
/// Balances between smooth animation and power efficiency across different devices.
class AdaptiveFramePacer {
  static const double defaultTargetFps = 60.0;
  static const double minFps = 30.0;
  static const double maxFps = 120.0;
  static const int frameHistorySize = 60;

  final Queue<double> _frameIntervals = Queue();
  final StreamController<PacingMetrics> _metricsController = StreamController.broadcast();
  Timer? _pacingTimer;
  Ticker? _frameTicker;
  bool _adaptivePacingEnabled = true;
  double _targetFps = defaultTargetFps;
  double _currentFps = defaultTargetFps;
  int _frameCount = 0;
  DateTime? _lastFrameTime;
  Duration _frameInterval = Duration(microseconds: (1000000 / defaultTargetFps).round());

  /// Stream of pacing performance metrics
  Stream<PacingMetrics> get metrics => _metricsController.stream;

  /// Current target FPS
  double get targetFps => _targetFps;

  /// Current actual FPS
  double get currentFps => _currentFps;

  /// Whether adaptive pacing is enabled
  bool get adaptivePacingEnabled => _adaptivePacingEnabled;

  /// Current frame interval
  Duration get frameInterval => _frameInterval;

  AdaptiveFramePacer() {
    _initialize();
  }

  void _initialize() {
    // Start frame monitoring
    _frameTicker = Ticker(_onFrameTick);
    _frameTicker?.start();

    // Start pacing adjustments
    _pacingTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _adjustPacing();
      _updateMetrics();
    });

    debugPrint('AdaptiveFramePacer initialized with target: ${_targetFps}fps');
  }

  void _onFrameTick(Duration elapsed) {
    final now = DateTime.now();
    if (_lastFrameTime != null) {
      final interval = now.difference(_lastFrameTime!).inMicroseconds / 1000000.0; // seconds
      _recordFrameInterval(interval);
    }

    _lastFrameTime = now;
    _frameCount++;
  }

  void _recordFrameInterval(double intervalSeconds) {
    _frameIntervals.add(intervalSeconds);
    if (_frameIntervals.length > frameHistorySize) {
      _frameIntervals.removeFirst();
    }

    // Update current FPS
    if (_frameIntervals.isNotEmpty) {
      final averageInterval = _frameIntervals.reduce((a, b) => a + b) / _frameIntervals.length;
      _currentFps = 1.0 / averageInterval;
    }
  }

  void _adjustPacing() {
    if (!_adaptivePacingEnabled || _frameIntervals.length < 10) return;

    final averageInterval = _frameIntervals.reduce((a, b) => a + b) / _frameIntervals.length;
    final currentFps = 1.0 / averageInterval;

    // Calculate optimal FPS based on device capabilities and performance
    final optimalFps = _calculateOptimalFps(currentFps);

    if ((optimalFps - _targetFps).abs() > 5.0) { // Only adjust if difference is significant
      setTargetFps(optimalFps);
    }
  }

  double _calculateOptimalFps(double currentFps) {
    // Adaptive algorithm based on device type and performance

    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      // Mobile devices: balance between smoothness and battery life
      if (currentFps < 50.0) {
        return minFps; // Drop to 30fps to save battery
      } else if (currentFps > 70.0) {
        return 60.0; // Cap at 60fps for mobile
      } else {
        return 60.0;
      }
    } else if (defaultTargetPlatform == TargetPlatform.linux ||
               defaultTargetPlatform == TargetPlatform.windows ||
               defaultTargetPlatform == TargetPlatform.macOS) {
      // Desktop: higher refresh rates possible
      if (currentFps < 50.0) {
        return minFps;
      } else {
        // Allow higher frame rates on desktop
        return currentFps.clamp(minFps, maxFps);
      }
    } else {
      // VR headset or other specialized hardware
      return 72.0; // Common VR refresh rate
    }
  }

  /// Set target FPS manually
  void setTargetFps(double fps) {
    _targetFps = fps.clamp(minFps, maxFps);
    _frameInterval = Duration(microseconds: (1000000 / _targetFps).round());
    debugPrint('Target FPS set to: $_targetFps');
  }

  /// Enable or disable adaptive pacing
  void setAdaptivePacing(bool enabled) {
    _adaptivePacingEnabled = enabled;
    if (!enabled) {
      // Reset to default when disabled
      setTargetFps(defaultTargetFps);
    }
    debugPrint('Adaptive pacing ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Force a specific frame rate for specific use cases (e.g., VR, gaming)
  void forceFrameRate(double fps) {
    _adaptivePacingEnabled = false;
    setTargetFps(fps);
    debugPrint('Forced frame rate: $fps');
  }

  /// Get the next frame time based on current pacing
  DateTime getNextFrameTime() {
    return DateTime.now().add(_frameInterval);
  }

  /// Check if it's time for the next frame
  bool shouldRenderFrame() {
    if (_lastFrameTime == null) return true;

    final timeSinceLastFrame = DateTime.now().difference(_lastFrameTime!);
    return timeSinceLastFrame >= _frameInterval;
  }

  void _updateMetrics() {
    final variance = _calculateFrameVariance();
    final stability = _calculateFrameStability();

    final metrics = PacingMetrics(
      targetFps: _targetFps,
      currentFps: _currentFps,
      frameVariance: variance,
      frameStability: stability,
      adaptivePacingEnabled: _adaptivePacingEnabled,
      frameCount: _frameCount,
      timestamp: DateTime.now(),
    );

    _metricsController.add(metrics);
  }

  double _calculateFrameVariance() {
    if (_frameIntervals.length < 2) return 0.0;

    final mean = _frameIntervals.reduce((a, b) => a + b) / _frameIntervals.length;
    final variance = _frameIntervals.map((interval) => (interval - mean) * (interval - mean)).reduce((a, b) => a + b) / _frameIntervals.length;

    return variance;
  }

  double _calculateFrameStability() {
    final variance = _calculateFrameVariance();
    // Convert variance to a 0-1 stability score (lower variance = higher stability)
    return 1.0 / (1.0 + variance * 1000); // Scale factor for readability
  }

  /// Get detailed pacing report
  Map<String, dynamic> getPacingReport() {
    return {
      'targetFps': _targetFps,
      'currentFps': _currentFps,
      'adaptivePacingEnabled': _adaptivePacingEnabled,
      'frameIntervalMs': _frameInterval.inMicroseconds / 1000.0,
      'frameCount': _frameCount,
      'frameHistorySize': _frameIntervals.length,
      'averageFrameInterval': _frameIntervals.isNotEmpty
          ? _frameIntervals.reduce((a, b) => a + b) / _frameIntervals.length
          : 0.0,
      'frameVariance': _calculateFrameVariance(),
      'frameStability': _calculateFrameStability(),
    };
  }

  /// Reset pacing statistics
  void resetStatistics() {
    _frameIntervals.clear();
    _frameCount = 0;
    _lastFrameTime = null;
    debugPrint('Frame pacer statistics reset');
  }

  /// Pause pacing (useful for debugging or specific scenarios)
  void pause() {
    _frameTicker?.stop();
    debugPrint('Frame pacing paused');
  }

  /// Resume pacing
  void resume() {
    _frameTicker?.start();
    debugPrint('Frame pacing resumed');
  }

  /// Dispose resources
  void dispose() {
    _pacingTimer?.cancel();
    _frameTicker?.dispose();
    _metricsController.close();
    debugPrint('AdaptiveFramePacer disposed');
  }
}

/// Frame pacing performance metrics
class PacingMetrics {
  final double targetFps;
  final double currentFps;
  final double frameVariance;
  final double frameStability;
  final bool adaptivePacingEnabled;
  final int frameCount;
  final DateTime timestamp;

  const PacingMetrics({
    required this.targetFps,
    required this.currentFps,
    required this.frameVariance,
    required this.frameStability,
    required this.adaptivePacingEnabled,
    required this.frameCount,
    required this.timestamp,
  });

  bool get isStable => frameStability > 0.8;
  bool get isOnTarget => (currentFps - targetFps).abs() / targetFps < 0.1;

  Map<String, dynamic> toJson() => {
    'targetFps': targetFps,
    'currentFps': currentFps,
    'frameVariance': frameVariance,
    'frameStability': frameStability,
    'adaptivePacingEnabled': adaptivePacingEnabled,
    'frameCount': frameCount,
    'timestamp': timestamp.toIso8601String(),
    'isStable': isStable,
    'isOnTarget': isOnTarget,
  };
}