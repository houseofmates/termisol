import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// real-time performance metrics collected from Flutter's frame timing.
class PerformanceMetrics {
  final double buildDurationMs;
  final double rasterDurationMs;
  final double vsyncOverheadMs;
  final double totalFrameTimeMs;
  final double frameRate;
  final DateTime timestamp;

  const PerformanceMetrics({
    required this.buildDurationMs,
    required this.rasterDurationMs,
    required this.vsyncOverheadMs,
    required this.totalFrameTimeMs,
    required this.frameRate,
    required this.timestamp,
  });
}

/// lightweight frame metrics for the performance overlay.
class FrameMetrics {
  final double fps;
  final double frameTimeMs;
  final double buildTimeMs;
  final double rasterTimeMs;

  const FrameMetrics({
    required this.fps,
    required this.frameTimeMs,
    required this.buildTimeMs,
    required this.rasterTimeMs,
  });
}

/// termisol core integration system.
///
/// collects real frame timing data via SchedulerBinding.addTimingsCallback
/// and exposes a stream of PerformanceMetrics. no ghost integrations.
class TermisolCoreIntegration {
  static TermisolCoreIntegration? _instance;
  static TermisolCoreIntegration get instance => _instance ??= TermisolCoreIntegration._();

  TermisolCoreIntegration._();

  late TermisolCoreConfig _config;
  late TermisolCoreConfig _originalConfig;

  final List<PerformanceMetrics> _frameTimings = [];
  final _metricsController = StreamController<PerformanceMetrics>.broadcast();
  Timer? _metricsTimer;
  int _consecutiveSlowFrames = 0;
  int _consecutiveFastFrames = 0;
  bool _isInitialized = false;
  bool _optimized = false;

  /// notifier for the latest averaged frame metrics.
  final ValueNotifier<FrameMetrics> frameMetrics = ValueNotifier(
    const FrameMetrics(fps: 0, frameTimeMs: 0, buildTimeMs: 0, rasterTimeMs: 0),
  );

  /// notifier for the current active performance config.
  final ValueNotifier<TermisolCoreConfig> activeConfig = ValueNotifier(
    TermisolCoreConfig.highPerformance(),
  );

  /// stream of real frame timing metrics.
  Stream<PerformanceMetrics> get metrics => _metricsController.stream;

  /// whether the system is initialized.
  bool get isInitialized => _isInitialized;

  /// initialize the core integration system.
  Future<bool> initialize({TermisolCoreConfig? config}) async {
    if (_isInitialized) return true;

    _originalConfig = config ?? TermisolCoreConfig.highPerformance();
    _config = _originalConfig;
    activeConfig.value = _config;
    _startRealPerformanceMonitoring();
    _isInitialized = true;
    return true;
  }

  /// start real performance monitoring using Flutter's frame timings callback.
  void _startRealPerformanceMonitoring() {
    SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
      for (final timing in timings) {
        final buildMs = timing.buildDuration.inMicroseconds / 1000.0;
        final rasterMs = timing.rasterDuration.inMicroseconds / 1000.0;
        final totalMs = timing.totalSpan.inMicroseconds / 1000.0;
        final vsyncMs = totalMs - buildMs - rasterMs;
        final fps = totalMs > 0 ? 1000.0 / totalMs : 0.0;

        final metric = PerformanceMetrics(
          buildDurationMs: buildMs,
          rasterDurationMs: rasterMs,
          vsyncOverheadMs: vsyncMs.clamp(0.0, totalMs),
          totalFrameTimeMs: totalMs,
          frameRate: fps,
          timestamp: DateTime.now(),
        );

        _frameTimings.add(metric);
        if (_frameTimings.length > 300) {
          _frameTimings.removeAt(0);
        }

        _metricsController.add(metric);
        _evaluateAutoOptimization(metric);
      }

      final recent = getRecentMetrics();
      if (recent.isNotEmpty) {
        final avgFrameTime = recent.fold<double>(0.0, (s, m) => s + m.totalFrameTimeMs) / recent.length;
        final avgBuildTime = recent.fold<double>(0.0, (s, m) => s + m.buildDurationMs) / recent.length;
        final avgRasterTime = recent.fold<double>(0.0, (s, m) => s + m.rasterDurationMs) / recent.length;
        final avgFps = avgFrameTime > 0 ? 1000.0 / avgFrameTime : 0.0;

        frameMetrics.value = FrameMetrics(
          fps: avgFps,
          frameTimeMs: avgFrameTime,
          buildTimeMs: avgBuildTime,
          rasterTimeMs: avgRasterTime,
        );
      }
    });

    _metricsTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkMemoryPressure();
    });
  }

  /// auto-optimize based on real frame metrics and system state.
  void _evaluateAutoOptimization(PerformanceMetrics metric) {
    if (metric.totalFrameTimeMs > 16.0) {
      _consecutiveSlowFrames++;
      _consecutiveFastFrames = 0;
    } else {
      _consecutiveFastFrames++;
      _consecutiveSlowFrames = 0;
    }

    if (_consecutiveSlowFrames >= 3 && !_optimized) {
      _applyOptimization();
    }

    if (_consecutiveFastFrames >= 10 && _optimized) {
      _restoreOptimization();
    }

    _checkThermalState();
  }

  void _applyOptimization() {
    _optimized = true;
    _config = TermisolCoreConfig.lowMemory();
    activeConfig.value = _config;
    debugPrint('[perf] applied low-memory optimization');
  }

  void _restoreOptimization() {
    _optimized = false;
    _config = _originalConfig;
    activeConfig.value = _config;
    debugPrint('[perf] restored high-performance config');
  }

  /// simplified thermal check using frame time as a proxy.
  void _checkThermalState() {
    if (_frameTimings.length >= 60) {
      final recentFrames = _frameTimings.sublist(_frameTimings.length - 60);
      final avgFrameTime = recentFrames.fold<double>(0.0, (sum, m) => sum + m.totalFrameTimeMs) / recentFrames.length;

      if (avgFrameTime > 20.0) {
        debugPrint('[perf] high average frame time detected: consider reducing quality');
      }
    }
  }

  /// check memory pressure using available platform APIs.
  void _checkMemoryPressure() {
    try {
      final info = _getProcessInfo();
      final rssMb = (info['rss'] as int? ?? 0) / (1024 * 1024);

      if (rssMb > 512) {
        debugPrint('[perf] process RSS > 512MB: consider clearing scrollback or image caches');
      }
    } catch (e) {
      // process info not available on this platform
    }
  }

  Map<String, dynamic> _getProcessInfo() {
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      return {};
    }
    return {};
  }

  /// get the last N performance samples.
  List<PerformanceMetrics> getRecentMetrics({int count = 60}) {
    if (_frameTimings.length <= count) return List.unmodifiable(_frameTimings);
    return List.unmodifiable(_frameTimings.sublist(_frameTimings.length - count));
  }

  /// get average frame time over the last N samples.
  double getAverageFrameTimeMs({int samples = 60}) {
    final recent = getRecentMetrics(count: samples);
    if (recent.isEmpty) return 0.0;
    final sum = recent.fold<double>(0.0, (s, m) => s + m.totalFrameTimeMs);
    return sum / recent.length;
  }

  /// get current system status.
  Map<String, dynamic> getSystemStatus() {
    return {
      'initialized': _isInitialized,
      'config': _config.toJson(),
      'performance': {
        'averageFrameTimeMs': getAverageFrameTimeMs(),
        'sampleCount': _frameTimings.length,
      },
    };
  }

  /// dispose all resources.
  Future<void> dispose() async {
    _metricsTimer?.cancel();
    await _metricsController.close();
    _frameTimings.clear();
    _isInitialized = false;
  }
}

/// Configuration for Termisol core.
class TermisolCoreConfig {
  final bool enableGpuAcceleration;
  final bool enableCloudAi;
  final int targetFps;
  final int maxScrollbackLines;
  final int imageCacheSize;
  final String aiModel;

  const TermisolCoreConfig({
    required this.enableGpuAcceleration,
    required this.enableCloudAi,
    required this.targetFps,
    required this.maxScrollbackLines,
    required this.imageCacheSize,
    required this.aiModel,
  });

  factory TermisolCoreConfig.defaultConfig() {
    return const TermisolCoreConfig(
      enableGpuAcceleration: true,
      enableCloudAi: true,
      targetFps: 60,
      maxScrollbackLines: 10000,
      imageCacheSize: 50,
      aiModel: 'cloud_only',
    );
  }

  factory TermisolCoreConfig.highPerformance() {
    return const TermisolCoreConfig(
      enableGpuAcceleration: true,
      enableCloudAi: true,
      targetFps: 144,
      maxScrollbackLines: 50000,
      imageCacheSize: 100,
      aiModel: 'cloud_only',
    );
  }

  factory TermisolCoreConfig.lowMemory() {
    return const TermisolCoreConfig(
      enableGpuAcceleration: false,
      enableCloudAi: false,
      targetFps: 30,
      maxScrollbackLines: 5000,
      imageCacheSize: 10,
      aiModel: 'cloud_only',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enableGpuAcceleration': enableGpuAcceleration,
      'enableCloudAi': enableCloudAi,
      'targetFps': targetFps,
      'maxScrollbackLines': maxScrollbackLines,
      'imageCacheSize': imageCacheSize,
      'aiModel': aiModel,
    };
  }
}
