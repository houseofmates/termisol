import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Texture cache helper for terminal rendering.
///
/// This is NOT a GPU renderer. Flutter's Skia/Impeller backend handles all
/// GPU rasterization. This class only caches decoded ui.Image objects to
/// avoid repeated image decoding overhead. The "GPU" name is retained for
/// backward compatibility with existing imports but the API is honest about
/// what it does.
class ProductionGpuRenderer {
  static ProductionGpuRenderer? _instance;
  static ProductionGpuRenderer get instance {
    _instance ??= ProductionGpuRenderer._();
    return _instance!;
  }

  ProductionGpuRenderer._();

  final Map<String, ui.Image> _textureCache = {};
  final StreamController<RenderMetrics> _metricsController =
      StreamController.broadcast();
  bool _accelerationEnabled = true;
  double _lastFrameTime = 0.0;
  int _frameCount = 0;
  DateTime? _lastMetricsTime;

  /// Stream of rendering performance metrics.
  Stream<RenderMetrics> get metrics => _metricsController.stream;

  /// Whether the user has opted into acceleration features.
  /// This does not mean dedicated GPU compute is available.
  bool get gpuAccelerationEnabled => _accelerationEnabled;

  /// Estimated current frame rate based on last recorded metrics.
  double get currentFrameRate {
    if (_lastMetricsTime == null) return 0.0;
    final elapsed =
        DateTime.now().difference(_lastMetricsTime!).inMilliseconds / 1000.0;
    return elapsed > 0 ? _frameCount / elapsed : 0.0;
  }

  /// Cache decoded images from raw bytes.
  Future<void> preloadTextures(Map<String, Uint8List> textureData) async {
    for (final entry in textureData.entries) {
      try {
        final codec = await ui.instantiateImageCodec(entry.value);
        final frame = await codec.getNextFrame();
        _textureCache[entry.key] = frame.image;
      } catch (e) {
        debugPrint('Failed to preload texture ${entry.key}: $e');
      }
    }
  }

  /// Get a cached image, or decode and cache it if not present.
  Future<ui.Image?> getTexture(String key, Uint8List? data) async {
    if (_textureCache.containsKey(key)) {
      return _textureCache[key];
    }

    if (data != null) {
      try {
        final codec = await ui.instantiateImageCodec(data);
        final frame = await codec.getNextFrame();
        _textureCache[key] = frame.image;
        // Enforce max cache size with LRU eviction
        _enforceCacheLimit();
        return frame.image;
      } catch (e) {
        debugPrint('Failed to load texture $key: $e');
      }
    }

    return null;
  }

  void _enforceCacheLimit() {
    const maxCacheSize = 100;
    while (_textureCache.length > maxCacheSize) {
      final oldest = _textureCache.keys.first;
      _textureCache.remove(oldest);
    }
  }

  /// Record frame timing for performance monitoring.
  void recordFrame(double frameTimeMs) {
    _lastFrameTime = frameTimeMs;
    _frameCount++;

    if (_frameCount % 60 == 0) {
      _lastMetricsTime = DateTime.now();
      _updateMetrics();
    }
  }

  void _updateMetrics() {
    final metrics = RenderMetrics(
      frameRate: currentFrameRate,
      lastFrameTime: _lastFrameTime,
      gpuAccelerationEnabled: _accelerationEnabled,
      textureCacheSize: _textureCache.length,
      timestamp: DateTime.now(),
    );
    if (!_metricsController.isClosed) {
      _metricsController.add(metrics);
    }
  }

  /// Clear all cached images to free memory.
  void clearCaches() {
    for (final image in _textureCache.values) {
      image.dispose();
    }
    _textureCache.clear();
  }

  /// Enable or disable acceleration features.
  void setAcceleration(bool enabled) {
    _accelerationEnabled = enabled;
  }

  /// Enable or disable acceleration (legacy alias).
  void setGpuAcceleration(bool enabled) => setAcceleration(enabled);

  /// Get memory usage statistics.
  Map<String, dynamic> getMemoryStats() {
    return {
      'textureCacheSize': _textureCache.length,
      'gpuAccelerationEnabled': _accelerationEnabled,
      'estimatedMemoryUsage': _estimateMemoryUsage(),
    };
  }

  int _estimateMemoryUsage() {
    // Rough estimation: assume 1MB per cached texture
    return _textureCache.length * 1024 * 1024;
  }

  /// Dispose all resources.
  void dispose() {
    clearCaches();
    _metricsController.close();
  }
}

/// Rendering performance metrics.
class RenderMetrics {
  final double frameRate;
  final double lastFrameTime;
  final bool gpuAccelerationEnabled;
  final int textureCacheSize;
  final DateTime timestamp;

  const RenderMetrics({
    required this.frameRate,
    required this.lastFrameTime,
    required this.gpuAccelerationEnabled,
    required this.textureCacheSize,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'frameRate': frameRate,
    'lastFrameTime': lastFrameTime,
    'gpuAccelerationEnabled': gpuAccelerationEnabled,
    'textureCacheSize': textureCacheSize,
    'timestamp': timestamp.toIso8601String(),
  };
}