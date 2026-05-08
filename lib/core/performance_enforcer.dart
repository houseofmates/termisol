import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'production_gpu_renderer.dart';
import 'sub_16ms_latency_optimizer.dart';

/// Enforces performance limits and monitors system health.
/// Automatically throttles or disables features when performance degrades.
class PerformanceEnforcer {
  static const Duration monitoringInterval = Duration(milliseconds: 500);
  static const int maxMemoryPressureWarnings = 5;
  static const double criticalMemoryThreshold = 0.9; // 90% memory usage
  static const double warningMemoryThreshold = 0.75; // 75% memory usage

  final StreamController<PerformanceAlert> _alertController = StreamController.broadcast();
  final StreamController<SystemHealth> _healthController = StreamController.broadcast();
  final Queue<PerformanceSample> _performanceHistory = Queue();
  final Map<String, PerformanceThreshold> _thresholds = {};

  Timer? _monitoringTimer;
  int _memoryPressureWarnings = 0;
  bool _enforcementEnabled = true;
  PerformanceLevel _currentLevel = PerformanceLevel.optimal;
  DateTime? _lastOptimizationTime;

  /// Stream of performance alerts
  Stream<PerformanceAlert> get alerts => _alertController.stream;

  /// Stream of system health updates
  Stream<SystemHealth> get health => _healthController.stream;

  /// Current performance level
  PerformanceLevel get currentLevel => _currentLevel;

  /// Whether enforcement is enabled
  bool get enforcementEnabled => _enforcementEnabled;

  PerformanceEnforcer() {
    _initialize();
  }

  void _initialize() {
    // Set up default thresholds
    _setupDefaultThresholds();

    // Start monitoring
    _monitoringTimer = Timer.periodic(monitoringInterval, (_) => _monitorPerformance());

    debugPrint('PerformanceEnforcer initialized');
  }

  void _setupDefaultThresholds() {
    _thresholds['frameTime'] = PerformanceThreshold(
      name: 'Frame Time',
      warningThreshold: 25.0, // ms
      criticalThreshold: 33.33, // ms
      unit: 'ms',
    );

    _thresholds['memoryUsage'] = PerformanceThreshold(
      name: 'Memory Usage',
      warningThreshold: warningMemoryThreshold,
      criticalThreshold: criticalMemoryThreshold,
      unit: 'ratio',
    );

    _thresholds['cpuUsage'] = PerformanceThreshold(
      name: 'CPU Usage',
      warningThreshold: 0.7, // 70%
      criticalThreshold: 0.9, // 90%
      unit: 'ratio',
    );

    _thresholds['frameDrops'] = PerformanceThreshold(
      name: 'Frame Drop Rate',
      warningThreshold: 0.05, // 5%
      criticalThreshold: 0.15, // 15%
      unit: 'ratio',
    );
  }

  void _monitorPerformance() {
    final sample = _collectPerformanceSample();
    _performanceHistory.add(sample);

    // Keep only recent history
    if (_performanceHistory.length > 120) { // 1 minute at 500ms intervals
      _performanceHistory.removeFirst();
    }

    // Analyze and enforce
    _analyzePerformance(sample);
    _updateHealthStatus();
  }

  PerformanceSample _collectPerformanceSample() {
    // Collect metrics from various sources
    final gpuRenderer = ProductionGpuRenderer.instance;
    final latencyOptimizer = Sub16msLatencyOptimizer();

    final frameRate = gpuRenderer.currentFrameRate;
    final frameTime = latencyOptimizer.averageFrameTime;
    final frameDropRate = latencyOptimizer.frameDropRate;

    // Estimate memory usage (simplified)
    final memoryUsage = _estimateMemoryUsage();

    // Estimate CPU usage (simplified - would need platform-specific implementation)
    final cpuUsage = _estimateCpuUsage();

    return PerformanceSample(
      timestamp: DateTime.now(),
      frameRate: frameRate,
      averageFrameTime: frameTime,
      frameDropRate: frameDropRate,
      memoryUsage: memoryUsage,
      cpuUsage: cpuUsage,
      gpuAccelerationEnabled: gpuRenderer.gpuAccelerationEnabled,
    );
  }

  double _estimateMemoryUsage() {
    // Simplified memory estimation
    // In a real implementation, this would use platform-specific APIs
    final gpuStats = ProductionGpuRenderer.instance.getMemoryStats();
    final estimatedGpuMemory = gpuStats['estimatedMemoryUsage'] as int;

    // Assume base memory usage and add GPU memory
    const baseMemoryUsage = 0.3; // 30% baseline
    const maxMemory = 1024 * 1024 * 1024; // 1GB assumption
    final additionalUsage = (estimatedGpuMemory / maxMemory).clamp(0.0, 0.5);

    return (baseMemoryUsage + additionalUsage).clamp(0.0, 1.0);
  }

  double _estimateCpuUsage() {
    // Simplified CPU estimation based on frame times
    final latencyOptimizer = Sub16msLatencyOptimizer();
    final avgFrameTime = latencyOptimizer.averageFrameTime;
    final targetFrameTime = latencyOptimizer.targetFrameTime;

    if (targetFrameTime == 0) return 0.0;

    // Higher frame times indicate higher CPU usage
    final usage = (avgFrameTime / targetFrameTime).clamp(0.1, 2.0);
    return usage.clamp(0.0, 1.0);
  }

  void _analyzePerformance(PerformanceSample sample) {
    final alerts = <PerformanceAlert>[];

    // Check each threshold
    for (final threshold in _thresholds.values) {
      final value = _getValueForThreshold(sample, threshold);

      if (value >= threshold.criticalThreshold) {
        alerts.add(PerformanceAlert(
          type: AlertType.critical,
          message: '${threshold.name} critically high: ${value.toStringAsFixed(2)}${threshold.unit}',
          timestamp: sample.timestamp,
          suggestedAction: _getSuggestedAction(threshold.name, AlertType.critical),
        ));

        if (_enforcementEnabled) {
          _enforcePerformanceLimit(threshold.name, AlertType.critical);
        }
      } else if (value >= threshold.warningThreshold) {
        alerts.add(PerformanceAlert(
          type: AlertType.warning,
          message: '${threshold.name} warning: ${value.toStringAsFixed(2)}${threshold.unit}',
          timestamp: sample.timestamp,
          suggestedAction: _getSuggestedAction(threshold.name, AlertType.warning),
        ));
      }
    }

    // Emit alerts
    for (final alert in alerts) {
      _alertController.add(alert);
    }

    // Update performance level
    _updatePerformanceLevel(sample, alerts);
  }

  double _getValueForThreshold(PerformanceSample sample, PerformanceThreshold threshold) {
    switch (threshold.name) {
      case 'Frame Time':
        return sample.averageFrameTime;
      case 'Memory Usage':
        return sample.memoryUsage;
      case 'CPU Usage':
        return sample.cpuUsage;
      case 'Frame Drop Rate':
        return sample.frameDropRate;
      default:
        return 0.0;
    }
  }

  String _getSuggestedAction(String metric, AlertType severity) {
    switch (metric) {
      case 'Frame Time':
        return severity == AlertType.critical
            ? 'Disable GPU acceleration or reduce visual effects'
            : 'Consider reducing animation complexity';
      case 'Memory Usage':
        return severity == AlertType.critical
            ? 'Clear caches and restart application'
            : 'Clear texture caches';
      case 'CPU Usage':
        return severity == AlertType.critical
            ? 'Close background processes'
            : 'Reduce background task frequency';
      case 'Frame Drop Rate':
        return severity == AlertType.critical
            ? 'Enable frame pacing or reduce frame rate'
            : 'Check for memory leaks';
      default:
        return 'Monitor performance closely';
    }
  }

  void _enforcePerformanceLimit(String metric, AlertType severity) {
    if (!_enforcementEnabled) return;

    switch (metric) {
      case 'Frame Time':
        if (severity == AlertType.critical) {
          ProductionGpuRenderer.instance.setGpuAcceleration(false);
          debugPrint('Enforced: Disabled GPU acceleration due to frame time issues');
        }
        break;
      case 'Memory Usage':
        if (severity == AlertType.critical) {
          ProductionGpuRenderer.instance.clearCaches();
          _memoryPressureWarnings++;
          debugPrint('Enforced: Cleared caches due to memory pressure');
        }
        break;
    }

    _lastOptimizationTime = DateTime.now();
  }

  void _updatePerformanceLevel(PerformanceSample sample, List<PerformanceAlert> alerts) {
    final criticalAlerts = alerts.where((a) => a.type == AlertType.critical).length;
    final warningAlerts = alerts.where((a) => a.type == AlertType.warning).length;

    PerformanceLevel newLevel;
    if (criticalAlerts > 0) {
      newLevel = PerformanceLevel.critical;
    } else if (warningAlerts > 2) {
      newLevel = PerformanceLevel.degraded;
    } else if (warningAlerts > 0) {
      newLevel = PerformanceLevel.warning;
    } else {
      newLevel = PerformanceLevel.optimal;
    }

    if (newLevel != _currentLevel) {
      _currentLevel = newLevel;
      debugPrint('Performance level changed to: $_currentLevel');
    }
  }

  void _updateHealthStatus() {
    final health = SystemHealth(
      performanceLevel: _currentLevel,
      memoryPressureWarnings: _memoryPressureWarnings,
      lastOptimizationTime: _lastOptimizationTime,
      enforcementEnabled: _enforcementEnabled,
      timestamp: DateTime.now(),
    );

    _healthController.add(health);
  }

  /// Enable or disable automatic performance enforcement
  void setEnforcementEnabled(bool enabled) {
    _enforcementEnabled = enabled;
    debugPrint('Performance enforcement ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Manually trigger performance optimization
  void triggerOptimization() {
    final gpuRenderer = ProductionGpuRenderer.instance;
    gpuRenderer.clearCaches();
    _memoryPressureWarnings = 0;
    _lastOptimizationTime = DateTime.now();
    debugPrint('Manual performance optimization triggered');
  }

  /// Get current performance report
  Map<String, dynamic> getPerformanceReport() {
    if (_performanceHistory.isEmpty) return {};

    final latest = _performanceHistory.last;
    final average = _calculateAveragePerformance();

    return {
      'currentLevel': _currentLevel.name,
      'enforcementEnabled': _enforcementEnabled,
      'latestSample': latest.toJson(),
      'averages': average,
      'memoryPressureWarnings': _memoryPressureWarnings,
      'lastOptimizationTime': _lastOptimizationTime?.toIso8601String(),
    };
  }

  Map<String, double> _calculateAveragePerformance() {
    if (_performanceHistory.isEmpty) return {};

    double sumFrameRate = 0;
    double sumFrameTime = 0;
    double sumMemory = 0;
    double sumCpu = 0;
    double sumFrameDrops = 0;

    for (final sample in _performanceHistory) {
      sumFrameRate += sample.frameRate;
      sumFrameTime += sample.averageFrameTime;
      sumMemory += sample.memoryUsage;
      sumCpu += sample.cpuUsage;
      sumFrameDrops += sample.frameDropRate;
    }

    final count = _performanceHistory.length;
    return {
      'averageFrameRate': sumFrameRate / count,
      'averageFrameTime': sumFrameTime / count,
      'averageMemoryUsage': sumMemory / count,
      'averageCpuUsage': sumCpu / count,
      'averageFrameDropRate': sumFrameDrops / count,
    };
  }

  /// Reset performance statistics and warnings
  void resetStatistics() {
    _performanceHistory.clear();
    _memoryPressureWarnings = 0;
    _lastOptimizationTime = null;
    debugPrint('Performance enforcer statistics reset');
  }

  /// Dispose resources
  void dispose() {
    _monitoringTimer?.cancel();
    _alertController.close();
    _healthController.close();
    debugPrint('PerformanceEnforcer disposed');
  }
}

/// Performance threshold configuration
class PerformanceThreshold {
  final String name;
  final double warningThreshold;
  final double criticalThreshold;
  final String unit;

  const PerformanceThreshold({
    required this.name,
    required this.warningThreshold,
    required this.criticalThreshold,
    required this.unit,
  });
}

/// Performance sample data point
class PerformanceSample {
  final DateTime timestamp;
  final double frameRate;
  final double averageFrameTime;
  final double frameDropRate;
  final double memoryUsage;
  final double cpuUsage;
  final bool gpuAccelerationEnabled;

  const PerformanceSample({
    required this.timestamp,
    required this.frameRate,
    required this.averageFrameTime,
    required this.frameDropRate,
    required this.memoryUsage,
    required this.cpuUsage,
    required this.gpuAccelerationEnabled,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'frameRate': frameRate,
    'averageFrameTime': averageFrameTime,
    'frameDropRate': frameDropRate,
    'memoryUsage': memoryUsage,
    'cpuUsage': cpuUsage,
    'gpuAccelerationEnabled': gpuAccelerationEnabled,
  };
}

/// Performance alert
class PerformanceAlert {
  final AlertType type;
  final String message;
  final DateTime timestamp;
  final String suggestedAction;

  const PerformanceAlert({
    required this.type,
    required this.message,
    required this.timestamp,
    required this.suggestedAction,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'message': message,
    'timestamp': timestamp.toIso8601String(),
    'suggestedAction': suggestedAction,
  };
}

/// System health status
class SystemHealth {
  final PerformanceLevel performanceLevel;
  final int memoryPressureWarnings;
  final DateTime? lastOptimizationTime;
  final bool enforcementEnabled;
  final DateTime timestamp;

  const SystemHealth({
    required this.performanceLevel,
    required this.memoryPressureWarnings,
    required this.lastOptimizationTime,
    required this.enforcementEnabled,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'performanceLevel': performanceLevel.name,
    'memoryPressureWarnings': memoryPressureWarnings,
    'lastOptimizationTime': lastOptimizationTime?.toIso8601String(),
    'enforcementEnabled': enforcementEnabled,
    'timestamp': timestamp.toIso8601String(),
  };
}

enum AlertType { warning, critical }

enum PerformanceLevel { optimal, warning, degraded, critical }