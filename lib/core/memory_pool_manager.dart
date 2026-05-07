import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Memory pool for efficient widget recycling
/// 
/// Features:
/// - Object pooling and recycling
/// - Memory usage monitoring
/// - Automatic garbage collection
/// - Performance metrics
class MemoryPoolManager {
  final Map<Type, Queue<Widget>> _pools = {};
  final Map<String, int> _memoryUsage = {};
  final Map<String, PoolMetrics> _metrics = {};
  Timer? _cleanupTimer;

  MemoryPoolManager() {
    _cleanupTimer = Timer.periodic(const Duration(seconds: 30), (_) => _performCleanup());
  }

  /// Get or create a pool for specific widget type
  Queue<Widget> getPool<T extends Widget>() {
    return _pools.putIfAbsent(
      T,
      () => Queue<Widget>(),
    );
  }

  /// Get a widget from pool
  T? getWidget<T extends Widget>() {
    final pool = _pools[T];
    return pool?.isNotEmpty == true ? pool.removeFirst() : null;
  }

  /// Return a widget to pool
  void returnWidget<T extends Widget>(T widget) {
    final pool = _pools[T];
    if (pool != null) {
      pool.add(widget);
    }
  }

  /// Get memory usage for pool type
  int getMemoryUsage<T extends Widget>() {
    return _memoryUsage[T.toString()] ?? 0;
  }

  /// Update memory usage for pool type
  void _updateMemoryUsage<T extends Widget>(int bytes) {
    _memoryUsage[T.toString()] = bytes;
  }

  /// Get pool metrics
  PoolMetrics getMetrics<T extends Widget>() {
    return _metrics[T.toString()] ?? PoolMetrics();
  }

  /// Perform cleanup of unused widgets
  void _performCleanup() {
    for (final entry in _pools.entries) {
      final pool = entry.value;
      final type = entry.key;
      
      // Remove widgets older than 5 minutes
      while (pool.length > 10) {
        final widget = pool.removeLast();
        if (widget is StatefulWidget) {
          (widget as StatefulWidget).dispose();
        }
      }
      
      // Update metrics
      _updateMetrics(type, pool.length);
    }
  }

  /// Update pool metrics
  void _updateMetrics<T extends Widget>(Type type, int poolSize) {
    final metrics = _metrics[type.toString()] ?? PoolMetrics();
    _metrics[type.toString()] = PoolMetrics(
      totalCreated: metrics.totalCreated + 1,
      totalReused: metrics.totalReused + (poolSize < 10 ? 0 : 1),
      currentSize: poolSize,
      memoryUsage: _memoryUsage[type.toString()] ?? 0,
      lastCleanup: DateTime.now(),
    );
  }

  /// Dispose all pools
  void dispose() {
    _cleanupTimer?.cancel();
    
    for (final pool in _pools.values) {
      for (final widget in pool) {
        if (widget is StatefulWidget) {
          (widget as StatefulWidget).dispose();
        }
      }
    }
    
    _pools.clear();
    _memoryUsage.clear();
    _metrics.clear();
  }
}

/// Pool metrics for monitoring
class PoolMetrics {
  int totalCreated = 0;
  int totalReused = 0;
  int currentSize = 0;
  int memoryUsage = 0;
  DateTime? lastCleanup;

  const PoolMetrics({
    this.totalCreated = 0,
    this.totalReused = 0,
    this.currentSize = 0,
    this.memoryUsage = 0,
    this.lastCleanup,
  });
}
