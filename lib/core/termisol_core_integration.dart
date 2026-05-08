import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'production_gpu_renderer.dart';
import '../ai/nvidia_ai_client.dart';
import 'terminal_session.dart';

/// Real-time performance metrics collected from Flutter's frame timing.
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

/// Termisol Core Integration System.
///
/// Ties together terminal sessions, cloud AI, and real performance monitoring
/// using Flutter's SchedulerBinding frame timings. No ghost integrations.
class TermisolCoreIntegration {
  static TermisolCoreIntegration? _instance;
  static TermisolCoreIntegration get instance => _instance ??= TermisolCoreIntegration._();

  TermisolCoreIntegration._();

  late final ProductionGpuRenderer _gpuRenderer;
  late final NvidiaAIClient _cloudAi;
  late TermisolCoreConfig _config;

  final List<PerformanceMetrics> _frameTimings = [];
  final _metricsController = StreamController<PerformanceMetrics>.broadcast();
  Timer? _metricsTimer;
  int _consecutiveSlowFrames = 0;
  bool _isInitialized = false;

  /// Stream of real frame timing metrics.
  Stream<PerformanceMetrics> get metrics => _metricsController.stream;

  /// Initialize the core integration system.
  Future<bool> initialize({TermisolCoreConfig? config}) async {
    if (_isInitialized) return true;

    _config = config ?? TermisolCoreConfig.highPerformance();

    try {
      _gpuRenderer = ProductionGpuRenderer.instance;
      if (_config.enableGpuAcceleration) {
        _gpuRenderer.setAcceleration(true);
      }

      if (_config.enableCloudAi) {
        _cloudAi = NvidiaAIClient();
        await _cloudAi.initialize();
      }

      _startRealPerformanceMonitoring();
      _isInitialized = true;
      return true;
    } catch (e, stack) {
      debugPrint('Core integration initialization failed: $e\n$stack');
      return false;
    }
  }

  /// Create a terminal session with the configured backend.
  Future<TerminalSession> createTerminalSession({
    String? id,
    String? name,
    int maxLines = 50000,
  }) async {
    if (!_isInitialized) {
      throw StateError('Core integration not initialized. Call initialize() first.');
    }

    final sessionId = id ?? 'session_${DateTime.now().millisecondsSinceEpoch}';
    final sessionName = name ?? 'Terminal $sessionId';

    final session = TerminalSession(
      id: sessionId,
      name: sessionName,
      maxLines: maxLines,
    );

    return session;
  }

  /// Handle AI queries using the cloud AI client only.
  /// Local AI fallback has been removed as no quantized model is shipped.
  Future<String> handleAiQuery(String query) async {
    if (!_isInitialized) return 'AI services unavailable: core not initialized';

    try {
      if (_config.enableCloudAi && _cloudAi.isInitialized) {
        final response = await _cloudAi.chatCompletion(
          messages: [ChatMessage(role: 'user', content: query)],
        );
        if (response.success) return response.content;
      }
      return 'AI services unavailable: no cloud AI configured';
    } catch (e) {
      debugPrint('AI query failed: $e');
      return 'AI query failed: $e';
    }
  }

  /// Start real performance monitoring using Flutter's frame timings callback.
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
    });

    // Periodic memory and health check
    _metricsTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkMemoryPressure();
    });
  }

  /// Auto-optimize based on real frame metrics.
  /// If raster > 16ms for 3 consecutive frames: reduce quality.
  void _evaluateAutoOptimization(PerformanceMetrics metric) {
    if (metric.rasterDurationMs > 16.0) {
      _consecutiveSlowFrames++;
    } else {
      _consecutiveSlowFrames = 0;
    }

    if (_consecutiveSlowFrames >= 3) {
      _gpuRenderer.setAcceleration(false);
      _consecutiveSlowFrames = 0;
      debugPrint('[perf] raster > 16ms for 3 frames: disabled GPU acceleration');
    }
  }

  /// Check memory pressure and evict caches if needed.
  void _checkMemoryPressure() {
    // Flutter does not expose RSS directly; use cache heuristics.
    final memStats = _gpuRenderer.getMemoryStats();
    final estimated = (memStats['estimatedMemoryUsage'] as int?) ?? 0;

    if (estimated > 512 * 1024 * 1024) {
      _gpuRenderer.clearCaches();
      debugPrint('[perf] estimated memory > 512MB: cleared caches');
    }
  }

  /// Get the last N performance samples.
  List<PerformanceMetrics> getRecentMetrics({int count = 60}) {
    if (_frameTimings.length <= count) return List.unmodifiable(_frameTimings);
    return List.unmodifiable(_frameTimings.sublist(_frameTimings.length - count));
  }

  /// Get average frame time over the last N samples.
  double getAverageFrameTimeMs({int samples = 60}) {
    final recent = getRecentMetrics(count: samples);
    if (recent.isEmpty) return 0.0;
    final sum = recent.fold<double>(0.0, (s, m) => s + m.totalFrameTimeMs);
    return sum / recent.length;
  }

  /// Get current system status.
  Map<String, dynamic> getSystemStatus() {
    return {
      'initialized': _isInitialized,
      'config': _config.toJson(),
      'performance': {
        'averageFrameTimeMs': getAverageFrameTimeMs(),
        'sampleCount': _frameTimings.length,
      },
      'gpu_renderer': _gpuRenderer.getMemoryStats(),
      'ai': {
        'cloud_enabled': _config.enableCloudAi,
        'cloud_status': _config.enableCloudAi ? _cloudAi.getMetrics() : null,
      },
    };
  }

  /// Dispose all resources.
  Future<void> dispose() async {
    _metricsTimer?.cancel();
    _metricsController.close();
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

/// Minimal chat message for cloud AI.
class ChatMessage {
  final String role;
  final String content;

  const ChatMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}
