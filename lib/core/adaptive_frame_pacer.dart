import 'dart:async';
import 'package:flutter/foundation.dart';

/// Adaptive frame rate controller for optimal performance.
///
/// Implements intelligent frame pacing that adjusts to:
/// - System load and thermal conditions
/// - Content complexity and rendering requirements  
/// - User preferences and battery considerations
/// - Smooth transitions to avoid jarring changes
class AdaptiveFramePacer {
  static const double _targetFPS = 60.0;
  static const double _minFPS = 15.0;
  static const double _maxFPS = 144.0;
  
  double _currentFPS = _targetFPS;
  double _systemLoad = 0.0;
  double _thermalFactor = 1.0;
  Timer? _adjustmentTimer;
  final Stopwatch _performanceMonitor = Stopwatch();
  
  // Performance tracking
  final List<double> _frameTimeHistory = [];
  double _averageFrameTime = 16.67; // Start at 60fps target
  int _framesSinceAdjustment = 0;
  
  // Configuration
  bool _adaptiveMode = true;
  bool _powerSavingMode = false;
  Duration _adjustmentInterval = const Duration(seconds: 2);
  
  /// Get current target FPS
  double get targetFPS => _currentFPS;
  
  /// Get current performance metrics
  Map<String, dynamic> get performanceMetrics {
    return {
      'current_fps': _currentFPS,
      'target_fps': _targetFPS,
      'system_load': _systemLoad,
      'thermal_factor': _thermalFactor,
      'average_frame_time': _averageFrameTime,
      'frames_since_adjustment': _framesSinceAdjustment,
      'adaptive_mode': _adaptiveMode,
      'power_saving': _powerSavingMode,
    };
  }
  
  /// Initialize the adaptive pacer
  void initialize() {
    _performanceMonitor.start();
    _startPeriodicAdjustment();
    debugPrint('🎯 Adaptive Frame Pacer initialized at ${_currentFPS.toStringAsFixed(1)} FPS');
  }
  
  /// Update system metrics (called from performance monitor or system)
  void updateSystemMetrics({
    double? systemLoad,
    double? thermalFactor,
    bool? powerSavingMode,
  }) {
    if (systemLoad != null) _systemLoad = systemLoad;
    if (thermalFactor != null) _thermalFactor = thermalFactor;
    if (powerSavingMode != null) _powerSavingMode = powerSavingMode;
    
    _recalculateTargetFPS();
  }
  
  /// Record frame performance for adaptive adjustment
  void recordFrameTime(double frameTimeMs) {
    _frameTimeHistory.add(frameTimeMs);
    if (_frameTimeHistory.length > 60) {
      _frameTimeHistory.removeAt(0);
    }
    
    _averageFrameTime = _frameTimeHistory.reduce((a, b) => a + b) / _frameTimeHistory.length;
    _framesSinceAdjustment++;
    
    // Trigger adjustment if needed
    if (_framesSinceAdjustment >= 30) { // Every 30 frames
      _recalculateTargetFPS();
    }
  }
  
  /// Recalculate target FPS based on current conditions
  void _recalculateTargetFPS() {
    if (!_adaptiveMode) {
      _currentFPS = _targetFPS;
      return;
    }
    
    double baseTarget = _targetFPS;
    
    // Adjust for system load
    if (_systemLoad > 0.8) {
      baseTarget *= 0.7; // Reduce by 30% under high load
    } else if (_systemLoad > 0.6) {
      baseTarget *= 0.85; // Reduce by 15% under medium load
    }
    
    // Adjust for thermal conditions
    if (_thermalFactor > 1.3) {
      baseTarget *= 0.6; // Reduce by 40% under thermal stress
    } else if (_thermalFactor > 1.1) {
      baseTarget *= 0.8; // Reduce by 20% under moderate thermal
    }
    
    // Adjust for power saving mode
    if (_powerSavingMode) {
      baseTarget *= 0.5; // Reduce by 50% in power saving
    }
    
    // Apply constraints
    double newTarget = baseTarget.clamp(_minFPS, _maxFPS);
    
    // Smooth transition to avoid jarring
    final maxChange = 10.0; // Max 10 FPS change per adjustment
    final targetChange = (newTarget - _currentFPS).clamp(-maxChange, maxChange);
    _currentFPS = (_currentFPS + targetChange * 0.1).clamp(_minFPS, _maxFPS);
    
    if (targetChange.abs() > 1.0) {
      debugPrint('🎯 Large FPS adjustment: ${_currentFPS.toStringAsFixed(1)} → ${newTarget.toStringAsFixed(1)}');
    }
  }
  
  /// Start periodic adjustment timer
  void _startPeriodicAdjustment() {
    _adjustmentTimer?.cancel();
    _adjustmentTimer = Timer.periodic(_adjustmentInterval, (_) {
      _recalculateTargetFPS();
    });
  }
  
  /// Manual FPS adjustment
  void setTargetFPS(double fps) {
    final clampedFPS = fps.clamp(_minFPS, _maxFPS);
    if (clampedFPS != _currentFPS) {
      _currentFPS = clampedFPS;
      debugPrint('🎯 Manual FPS adjustment: ${clampedFPS.toStringAsFixed(1)}');
    }
  }
  
  /// Enable/disable adaptive mode
  void setAdaptiveMode(bool enabled) {
    _adaptiveMode = enabled;
    if (!enabled) {
      _currentFPS = _targetFPS;
    }
    debugPrint('🎯 Adaptive mode ${enabled ? "enabled" : "disabled"}');
  }
  
  /// Set power saving mode
  void setPowerSavingMode(bool enabled) {
    _powerSavingMode = enabled;
    _recalculateTargetFPS();
    debugPrint('🔋 Power saving mode ${enabled ? "enabled" : "disabled"}');
  }
  
  /// Get recommended frame interval for current FPS
  Duration get frameInterval => Duration(microseconds: (1000000 / _currentFPS).round());
  
  /// Dispose resources
  void dispose() {
    _adjustmentTimer?.cancel();
    _performanceMonitor.stop();
    _frameTimeHistory.clear();
    debugPrint('🎯 Adaptive Frame Pacer disposed');
  }
}
