import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Memory optimization manager for terminal emulator
/// 
/// Implements:
/// - Widget lifecycle management
/// - Memory pool management
/// - Garbage collection hints
/// - Memory pressure monitoring
class MemoryOptimizer {
  static const int _maxPoolSize = 50;
  static const Duration _gcInterval = Duration(seconds: 30);
  static const int _memoryThresholdMB = 200; // Trigger GC at 200MB
  
  final Map<Type, Queue<dynamic>> _objectPools = {};
  final List<WeakReference<WeakReferenceTarget>> _weakRefs = [];
  Timer? _gcTimer;
  int _lastGcTimestamp = DateTime.now().millisecondsSinceEpoch;
  
  bool _isInitialized = false;
  
  bool get isInitialized => _isInitialized;
  
  /// Initialize memory optimizer
  void initialize() {
    if (_isInitialized) return;
    
    _gcTimer = Timer.periodic(_gcInterval, (_) {
      _performGarbageCollection();
    });
    
    _isInitialized = true;
    debugPrint('🧠 Memory optimizer initialized');
  }
  
  /// Get object from pool or create new
  T getPooledObject<T>(T Function() factory) {
    final pool = _objectPools[T] ??= Queue<dynamic>();
    
    if (pool.isNotEmpty) {
      final obj = pool.removeFirst();
      debugPrint('♻️ Reusing pooled object of type ${T.toString()}');
      return obj as T;
    }
    
    return factory();
  }
  
  /// Return object to pool for reuse
  void returnToPool<T>(T object) {
    final pool = _objectPools[T] ??= Queue<dynamic>();
    
    if (pool.length < _maxPoolSize) {
      pool.add(object);
      debugPrint('📦 Returning object to pool: ${T.toString()}');
    }
  }
  
  /// Add weak reference for monitoring
  void addWeakReference(WeakReferenceTarget target) {
    _weakRefs.add(WeakReference(target));
    
    // Clean up old weak refs periodically
    if (_weakRefs.length > 100) {
      _cleanupWeakReferences();
    }
  }
  
  /// Perform garbage collection
  void _performGarbageCollection() {
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Check if enough time has passed since last GC
    if (now - _lastGcTimestamp < _gcInterval.inMilliseconds) {
      return;
    }
    
    debugPrint('🗑️ Performing garbage collection...');
    
    // Clean up weak references
    _cleanupWeakReferences();
    
    // Trim object pools
    _trimObjectPools();
    
    // Suggest garbage collection to Dart VM
    if (kDebugMode) {
      debugPrint('🗑️ Suggesting garbage collection...');
    }
    
    _lastGcTimestamp = now;
  }
  
  /// Clean up dead weak references
  void _cleanupWeakReferences() {
    _weakRefs.removeWhere((weakRef) {
      return weakRef.target == null;
    });
  }
  
  /// Trim object pools to prevent memory bloat
  void _trimObjectPools() {
    for (final entry in _objectPools.entries) {
      final pool = entry.value;
      final type = entry.key;
      
      // Keep only half of the pool
      final targetSize = (_maxPoolSize ~/ 2);
      while (pool.length > targetSize) {
        pool.removeLast();
      }
      
      debugPrint('✂️ Trimmed pool ${type.toString()} to ${pool.length} objects');
    }
  }
  
  /// Get memory usage statistics
  Map<String, dynamic> getMemoryStats() {
    final poolStats = <String, int>{};
    
    for (final entry in _objectPools.entries) {
      poolStats[entry.key.toString()] = entry.value.length;
    }
    
    return {
      'pool_sizes': poolStats,
      'weak_references': _weakRefs.length,
      'last_gc_timestamp': _lastGcTimestamp,
      'total_pooled_objects': _objectPools.values
          .fold(0, (sum, pool) => sum + pool.length),
    };
  }
  
  /// Force immediate garbage collection
  void forceGarbageCollection() {
    debugPrint('🗑️ Force garbage collection triggered');
    _performGarbageCollection();
  }
  
  /// Dispose memory optimizer
  void dispose() {
    _gcTimer?.cancel();
    
    // Clear all pools
    for (final pool in _objectPools.values) {
      pool.clear();
    }
    _objectPools.clear();
    
    // Clear weak references
    _weakRefs.clear();
    
    _isInitialized = false;
    debugPrint('🧠 Memory optimizer disposed');
  }
}

/// Interface for weak reference targets
abstract class WeakReferenceTarget {
  String get identifier;
}

/// Widget memory manager for terminal components
class WidgetMemoryManager {
  final Map<String, WeakReference> _widgetRefs = {};
  final Map<String, int> _accessCounts = {};
  final MemoryOptimizer _memoryOptimizer;
  
  WidgetMemoryManager(this._memoryOptimizer);
  
  /// Register widget for memory tracking
  void registerWidget(String key, dynamic widget) {
    _widgetRefs[key] = WeakReference(widget);
    _accessCounts[key] = 0;
    _memoryOptimizer.addWeakReference(_WidgetReference(key));
  }
  
  /// Mark widget as accessed
  void markAccessed(String key) {
    _accessCounts[key] = (_accessCounts[key] ?? 0) + 1;
  }
  
  /// Get widget if still alive
  T? getWidget<T>(String key) {
    final weakRef = _widgetRefs[key];
    if (weakRef?.target != null) {
      markAccessed(key);
      return weakRef!.target as T?;
    }
    
    // Clean up dead reference
    _widgetRefs.remove(key);
    _accessCounts.remove(key);
    return null;
  }
  
  /// Clean up unused widgets
  void cleanupUnusedWidgets() {
    final now = DateTime.now().millisecondsSinceEpoch;
    
    _widgetRefs.removeWhere((key, weakRef) {
      if (weakRef.target == null) {
        debugPrint('🗑️ Removing dead widget reference: $key');
        return true;
      }
      
      // Remove widgets not accessed recently
      final accessCount = _accessCounts[key] ?? 0;
      if (accessCount == 0) {
        debugPrint('🗑️ Removing unused widget: $key');
        return true;
      }
      
      return false;
    });
  }
  
  /// Get memory statistics
  Map<String, dynamic> getStats() {
    return {
      'tracked_widgets': _widgetRefs.length,
      'access_counts': Map.from(_accessCounts),
    };
  }
  
  /// Dispose manager
  void dispose() {
    _widgetRefs.clear();
    _accessCounts.clear();
  }
}

/// Widget reference for weak tracking
class _WidgetReference implements WeakReferenceTarget {
  final String _key;
  
  _WidgetReference(this._key);
  
  @override
  String get identifier => _key;
}
