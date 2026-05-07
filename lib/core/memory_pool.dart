import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Memory Pool - Reduced allocations and performance optimization
/// 
/// Implements comprehensive memory management:
/// - Object pooling for common types
/// - Memory allocation tracking
/// - Garbage collection optimization
/// - Memory leak detection
/// - Performance monitoring
class MemoryPool {
  bool _isInitialized = false;
  
  // Object pools
  final Map<Type, ObjectPool> _pools = {};
  
  // Memory tracking
  final Map<String, MemoryTracker> _trackers = {};
  final Map<String, int> _allocationCounts = {};
  final Map<String, int> _deallocationCounts = {};
  
  // Performance monitoring
  final MemoryPerformanceMonitor _performance = MemoryPerformanceMonitor();
  
  // Configuration
  MemoryPoolConfig _config = MemoryPoolConfig();
  
  // Memory usage
  final MemoryUsage _usage = MemoryUsage();
  
  MemoryPool();
  
  bool get isInitialized => _isInitialized;
  Map<String, MemoryTracker> get trackers => Map.unmodifiable(_trackers);
  MemoryUsage get usage => _usage;
  MemoryPerformanceMonitor get performance => _performance;
  
  /// Initialize memory pool
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Load configuration
      await _loadConfiguration();
      
      // Setup object pools
      _setupObjectPools();
      
      // Setup memory tracking
      _setupMemoryTracking();
      
      // Setup performance monitoring
      _performance.initialize();
      
      // Setup garbage collection optimization
      _setupGarbageCollection();
      
      _isInitialized = true;
      debugPrint('🧠 Memory Pool initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Memory Pool: $e');
    }
  }
  
  /// Load configuration
  Future<void> _loadConfiguration() async {
    try {
      final configFile = File('${Platform.environment['HOME']}/.termisol/memory_pool_config.json');
      if (await configFile.exists()) {
        final content = await configFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        _config = MemoryPoolConfig.fromJson(data);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load memory pool config: $e');
    }
  }
  
  /// Setup object pools
  void _setupObjectPools() {
    // String pool
    _pools[String] = ObjectPool<String>(
      name: 'String',
      factory: () => '',
      reset: (obj) => obj = '',
      maxSize: _config.stringPoolSize,
    );
    
    // List pool
    _pools[List] = ObjectPool<List>(
      name: 'List',
      factory: () => <dynamic>[],
      reset: (obj) => obj.clear(),
      maxSize: _config.listPoolSize,
    );
    
    // Map pool
    _pools[Map] = ObjectPool<Map>(
      name: 'Map',
      factory: () => <String, dynamic>{},
      reset: (obj) => obj.clear(),
      maxSize: _config.mapPoolSize,
    );
    
    // Set pool
    _pools[Set] = ObjectPool<Set>(
      name: 'Set',
      factory: () => <dynamic>{},
      reset: (obj) => obj.clear(),
      maxSize: _config.setPoolSize,
    );
    
    // Uint8List pool
    _pools[Uint8List] = ObjectPool<Uint8List>(
      name: 'Uint8List',
      factory: () => Uint8List(0),
      reset: (obj) {
        if (obj.length > 0) {
          obj.setRange(0, obj.length, List.filled(obj.length, 0));
        }
      },
      maxSize: _config.bufferPoolSize,
    );
    
    // Int32List pool
    _pools[Int32List] = ObjectPool<Int32List>(
      name: 'Int32List',
      factory: () => Int32List(0),
      reset: (obj) {
        if (obj.length > 0) {
          obj.setRange(0, obj.length, List.filled(obj.length, 0));
        }
      },
      maxSize: _config.bufferPoolSize,
    );
    
    debugPrint('🏊 Object pools setup: ${_pools.length} pools');
  }
  
  /// Setup memory tracking
  void _setupMemoryTracking() {
    // Create trackers for different allocation types
    _trackers['general'] = MemoryTracker('general');
    _trackers['string'] = MemoryTracker('string');
    _trackers['buffer'] = MemoryTracker('buffer');
    _trackers['object'] = MemoryTracker('object');
    _trackers['ui'] = MemoryTracker('ui');
    _trackers['network'] = MemoryTracker('network');
    _trackers['file'] = MemoryTracker('file');
    
    debugPrint('📊 Memory tracking setup: ${_trackers.length} trackers');
  }
  
  /// Setup garbage collection optimization
  void _setupGarbageCollection() {
    if (_config.enableGarbageCollectionOptimization) {
      Timer.periodic(Duration(seconds: _config.gcOptimizationInterval), (_) {
        _optimizeGarbageCollection();
      });
      debugPrint('🗑️ Garbage collection optimization enabled');
    }
  }
  
  /// Get object from pool
  T getObject<T>() {
    final pool = _pools[T];
    if (pool != null) {
      final obj = pool.acquire();
      _trackAllocation(T, obj);
      return obj;
    }
    
    // Create new object if no pool exists
    final obj = _createObject<T>();
    _trackAllocation(T, obj);
    return obj;
  }
  
  /// Return object to pool
  void returnObject<T>(T obj) {
    final pool = _pools[T];
    if (pool != null) {
      pool.release(obj);
      _trackDeallocation(T, obj);
    }
  }
  
  /// Create new object
  T _createObject<T>() {
    switch (T) {
      case String:
        return '' as T;
      case List:
        return <dynamic>[] as T;
      case Map:
        return <String, dynamic>{} as T;
      case Set:
        return <dynamic>{} as T;
      case Uint8List:
        return Uint8List(0) as T;
      case Int32List:
        return Int32List(0) as T;
      default:
        throw UnsupportedError('Unsupported type for object creation: $T');
    }
  }
  
  /// Track allocation
  void _trackAllocation<T>(T obj, String? category) {
    final trackerName = category ?? _getCategoryForType<T>();
    final tracker = _trackers[trackerName];
    
    if (tracker != null) {
      tracker.trackAllocation(obj);
    }
    
    _allocationCounts[trackerName] = (_allocationCounts[trackerName] ?? 0) + 1;
    _usage.totalAllocations++;
  }
  
  /// Track deallocation
  void _trackDeallocation<T>(T obj, String? category) {
    final trackerName = category ?? _getCategoryForType<T>();
    final tracker = _trackers[trackerName];
    
    if (tracker != null) {
      tracker.trackDeallocation(obj);
    }
    
    _deallocationCounts[trackerName] = (_deallocationCounts[trackerName] ?? 0) + 1;
    _usage.totalDeallocations++;
  }
  
  /// Get category for type
  String _getCategoryForType<T>() {
    switch (T) {
      case String:
        return 'string';
      case Uint8List:
      case Int32List:
        return 'buffer';
      case List:
      case Map:
      case Set:
        return 'object';
      default:
        return 'general';
    }
  }
  
  /// Allocate buffer
  Uint8List allocateBuffer(int size, {String? category}) {
    final buffer = getObject<Uint8List>();
    
    // Resize if needed
    if (buffer.length < size) {
      returnObject<Uint8List>(buffer);
      final newBuffer = Uint8List(size);
      _trackAllocation(newBuffer, category ?? 'buffer');
      return newBuffer;
    }
    
    return buffer;
  }
  
  /// Release buffer
  void releaseBuffer(Uint8List buffer, {String? category}) {
    _trackDeallocation(buffer, category ?? 'buffer');
    returnObject<Uint8List>(buffer);
  }
  
  /// Allocate string buffer
  String allocateStringBuffer({String? category}) {
    return getObject<String>();
  }
  
  /// Release string buffer
  void releaseStringBuffer(String buffer, {String? category}) {
    _trackDeallocation(buffer, category ?? 'string');
    returnObject<String>(buffer);
  }
  
  /// Create pooled list
  List<T> createPooledList<T>({String? category}) {
    final list = getObject<List>();
    _trackAllocation(list, category ?? 'object');
    return list.cast<T>();
  }
  
  /// Release pooled list
  void releasePooledList<T>(List<T> list, {String? category}) {
    _trackDeallocation(list, category ?? 'object');
    returnObject<List>(list);
  }
  
  /// Create pooled map
  Map<K, V> createPooledMap<K, V>({String? category}) {
    final map = getObject<Map>();
    _trackAllocation(map, category ?? 'object');
    return map.cast<K, V>();
  }
  
  /// Release pooled map
  void releasePooledMap<K, V>(Map<K, V> map, {String? category}) {
    _trackDeallocation(map, category ?? 'object');
    returnObject<Map>(map);
  }
  
  /// Create pooled set
  Set<T> createPooledSet<T>({String? category}) {
    final set = getObject<Set>();
    _trackAllocation(set, category ?? 'object');
    return set.cast<T>();
  }
  
  /// Release pooled set
  void releasePooledSet<T>(Set<T> set, {String? category}) {
    _trackDeallocation(set, category ?? 'object');
    returnObject<Set>(set);
  }
  
  /// Optimize memory
  void optimizeMemory() {
    final stopwatch = Stopwatch()..start();
    
    try {
      // Optimize object pools
      for (final pool in _pools.values) {
        pool.optimize();
      }
      
      // Trigger garbage collection
      _triggerGarbageCollection();
      
      // Update memory usage
      _updateMemoryUsage();
      
      _performance.recordOptimization(stopwatch.elapsedMicroseconds);
      
      debugPrint('⚡ Memory optimization completed in ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      debugPrint('⚠️ Failed to optimize memory: $e');
    }
  }
  
  /// Optimize garbage collection
  void _optimizeGarbageCollection() {
    if (!_config.enableGarbageCollectionOptimization) return;
    
    try {
      // Force garbage collection
      _triggerGarbageCollection();
      
      // Clean up object pools
      for (final pool in _pools.values) {
        pool.cleanup();
      }
      
      debugPrint('🗑️ Garbage collection optimized');
    } catch (e) {
      debugPrint('⚠️ Failed to optimize garbage collection: $e');
    }
  }
  
  /// Trigger garbage collection
  void _triggerGarbageCollection() {
    // Note: Dart doesn't have direct GC control
    // This would be a placeholder for potential future Dart APIs
    _usage.lastGCTime = DateTime.now();
  }
  
  /// Update memory usage
  void _updateMemoryUsage() {
    try {
      // Calculate total pool usage
      int totalPoolUsage = 0;
      for (final pool in _pools.values) {
        totalPoolUsage += pool.getCurrentUsage();
      }
      
      // Calculate tracker usage
      int totalTrackerUsage = 0;
      for (final tracker in _trackers.values) {
        totalTrackerUsage += tracker.getCurrentUsage();
      }
      
      _usage.totalPoolUsage = totalPoolUsage;
      _usage.totalTrackerUsage = totalTrackerUsage;
      _usage.lastUpdated = DateTime.now();
      
    } catch (e) {
      debugPrint('⚠️ Failed to update memory usage: $e');
    }
  }
  
  /// Detect memory leaks
  List<MemoryLeak> detectMemoryLeaks() {
    final leaks = <MemoryLeak>[];
    
    for (final tracker in _trackers.values) {
      final trackerLeaks = tracker.detectLeaks();
      leaks.addAll(trackerLeaks);
    }
    
    return leaks;
  }
  
  /// Get memory statistics
  MemoryStatistics getStatistics() {
    return MemoryStatistics(
      totalAllocations: _usage.totalAllocations,
      totalDeallocations: _usage.totalDeallocations,
      currentUsage: _usage.totalPoolUsage + _usage.totalTrackerUsage,
      poolUsage: _usage.totalPoolUsage,
      trackerUsage: _usage.totalTrackerUsage,
      poolCount: _pools.length,
      trackerCount: _trackers.length,
      memoryLeaks: detectMemoryLeaks(),
      performance: _performance.getStatistics(),
      lastUpdated: _usage.lastUpdated,
    );
  }
  
  /// Get pool statistics
  Map<String, PoolStatistics> getPoolStatistics() {
    final stats = <String, PoolStatistics>{};
    
    for (final entry in _pools.entries) {
      final pool = entry.value;
      stats[entry.key.toString()] = PoolStatistics(
        name: pool.name,
        totalObjects: pool.totalObjects,
        availableObjects: pool.availableObjects,
        inUseObjects: pool.inUseObjects,
        hitRate: pool.hitRate,
        missRate: pool.missRate,
        memoryUsage: pool.getCurrentUsage(),
      );
    }
    
    return stats;
  }
  
  /// Get tracker statistics
  Map<String, TrackerStatistics> getTrackerStatistics() {
    final stats = <String, TrackerStatistics>{};
    
    for (final entry in _trackers.entries) {
      final tracker = entry.value;
      stats[entry.key] = TrackerStatistics(
        name: tracker.name,
        totalAllocations: tracker.totalAllocations,
        totalDeallocations: tracker.totalDeallocations,
        currentObjects: tracker.currentObjects,
        peakObjects: tracker.peakObjects,
        averageObjectSize: tracker.averageObjectSize,
        memoryUsage: tracker.getCurrentUsage(),
      );
    }
    
    return stats;
  }
  
  /// Clear all pools
  void clearAllPools() {
    for (final pool in _pools.values) {
      pool.clear();
    }
    
    debugPrint('🗑️ All object pools cleared');
  }
  
  /// Clear specific pool
  void clearPool<T>() {
    final pool = _pools[T];
    if (pool != null) {
      pool.clear();
      debugPrint('🗑️ Pool cleared: $T');
    }
  }
  
  /// Reset statistics
  void resetStatistics() {
    _usage.reset();
    _performance.reset();
    
    for (final tracker in _trackers.values) {
      tracker.reset();
    }
    
    _allocationCounts.clear();
    _deallocationCounts.clear();
    
    debugPrint('📊 Memory statistics reset');
  }
  
  /// Export memory data
  String exportMemoryData() {
    final data = {
      'version': '1.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'usage': _usage.toJson(),
      'pools': getPoolStatistics(),
      'trackers': getTrackerStatistics(),
      'performance': _performance.getStatistics().toJson(),
      'config': _config.toJson(),
    };
    
    return jsonEncode(data);
  }
  
  /// Dispose resources
  void dispose() {
    // Clear all pools
    clearAllPools();
    
    // Clear trackers
    _trackers.clear();
    
    // Clear counters
    _allocationCounts.clear();
    _deallocationCounts.clear();
    
    // Dispose performance monitor
    _performance.dispose();
    
    _isInitialized = false;
    debugPrint('🧠 Memory Pool disposed');
  }
}

/// Object pool implementation
class ObjectPool<T> {
  final String name;
  final T Function() factory;
  final void Function(T) reset;
  final int maxSize;
  final Queue<T> _available = Queue();
  final Set<T> _inUse = {};
  
  int _totalObjects = 0;
  int _hits = 0;
  int _misses = 0;
  
  ObjectPool({
    required this.name,
    required this.factory,
    required this.reset,
    required this.maxSize,
  });
  
  int get totalObjects => _totalObjects;
  int get availableObjects => _available.length;
  int get inUseObjects => _inUse.length;
  double get hitRate => _hits + _misses > 0 ? _hits / (_hits + _misses) : 0.0;
  double get missRate => _hits + _misses > 0 ? _misses / (_hits + _misses) : 0.0;
  
  /// Acquire object from pool
  T acquire() {
    T obj;
    
    if (_available.isNotEmpty) {
      obj = _available.removeFirst();
      _hits++;
    } else {
      obj = factory();
      _totalObjects++;
      _misses++;
    }
    
    _inUse.add(obj);
    return obj;
  }
  
  /// Release object back to pool
  void release(T obj) {
    if (!_inUse.contains(obj)) return;
    
    _inUse.remove(obj);
    reset(obj);
    
    if (_available.length < maxSize) {
      _available.add(obj);
    }
  }
  
  /// Optimize pool
  void optimize() {
    // Remove excess objects
    while (_available.length > maxSize) {
      _available.removeFirst();
    }
  }
  
  /// Cleanup pool
  void cleanup() {
    _available.clear();
    _inUse.clear();
  }
  
  /// Clear pool
  void clear() {
    _available.clear();
    _inUse.clear();
    _totalObjects = 0;
    _hits = 0;
    _misses = 0;
  }
  
  /// Get current usage
  int getCurrentUsage() {
    return (_available.length + _inUse.length) * _estimateObjectSize();
  }
  
  /// Estimate object size
  int _estimateObjectSize() {
    // Rough estimation - would need to be more sophisticated
    return 64; // Estimated object overhead
  }
}

/// Memory tracker implementation
class MemoryTracker {
  final String name;
  final Map<int, int> _allocations = {};
  int _totalAllocations = 0;
  int _totalDeallocations = 0;
  int _currentObjects = 0;
  int _peakObjects = 0;
  int _totalSize = 0;
  
  MemoryTracker(this.name);
  
  int get totalAllocations => _totalAllocations;
  int get totalDeallocations => _totalDeallocations;
  int get currentObjects => _currentObjects;
  int get peakObjects => _peakObjects;
  double get averageObjectSize => _currentObjects > 0 ? _totalSize / _currentObjects : 0.0;
  
  /// Track allocation
  void trackAllocation<T>(T obj) {
    _totalAllocations++;
    _currentObjects++;
    _peakObjects = max(_peakObjects, _currentObjects);
    
    final size = _estimateObjectSize(obj);
    _totalSize += size;
    _allocations[identityHashCode(obj)] = size;
  }
  
  /// Track deallocation
  void trackDeallocation<T>(T obj) {
    _totalDeallocations++;
    _currentObjects--;
    
    final hashCode = identityHashCode(obj);
    final size = _allocations.remove(hashCode) ?? 0;
    _totalSize -= size;
  }
  
  /// Detect leaks
  List<MemoryLeak> detectLeaks() {
    final leaks = <MemoryLeak>[];
    
    // Objects allocated but not deallocated
    if (_currentObjects > 0) {
      leaks.add(MemoryLeak(
        type: name,
        leakedObjects: _currentObjects,
        estimatedSize: _totalSize,
        detectedAt: DateTime.now(),
      ));
    }
    
    return leaks;
  }
  
  /// Estimate object size
  int _estimateObjectSize<T>(T obj) {
    // Rough size estimation
    if (obj is String) {
      return (obj as String).length * 2; // UTF-16
    } else if (obj is List) {
      return (obj as List).length * 8; // Reference size
    } else if (obj is Map) {
      return (obj as Map).length * 16; // Key-value pairs
    } else if (obj is Uint8List) {
      return (obj as Uint8List).length;
    } else if (obj is Int32List) {
      return (obj as Int32List).length * 4;
    } else {
      return 64; // Default object overhead
    }
  }
  
  /// Get current usage
  int getCurrentUsage() {
    return _totalSize;
  }
  
  /// Reset tracker
  void reset() {
    _allocations.clear();
    _totalAllocations = 0;
    _totalDeallocations = 0;
    _currentObjects = 0;
    _peakObjects = 0;
    _totalSize = 0;
  }
}

/// Memory performance monitor
class MemoryPerformanceMonitor {
  final List<MemoryMetric> _metrics = [];
  int _optimizations = 0;
  int _gcCalls = 0;
  Duration _totalOptimizationTime = Duration.zero;
  
  MemoryPerformanceMonitor();
  
  /// Initialize monitor
  void initialize() {
    debugPrint('📊 Memory performance monitor initialized');
  }
  
  /// Record optimization
  void recordOptimization(int microseconds) {
    _optimizations++;
    _totalOptimizationTime += Duration(microseconds: microseconds);
    
    _metrics.add(MemoryMetric(
      type: 'optimization',
      value: microseconds,
      timestamp: DateTime.now(),
    ));
  }
  
  /// Record garbage collection
  void recordGarbageCollection(int microseconds) {
    _gcCalls++;
    
    _metrics.add(MemoryMetric(
      type: 'garbage_collection',
      value: microseconds,
      timestamp: DateTime.now(),
    ));
  }
  
  /// Get statistics
  MemoryPerformanceStatistics getStatistics() {
    return MemoryPerformanceStatistics(
      totalOptimizations: _optimizations,
      totalGCCalls: _gcCalls,
      averageOptimizationTime: _optimizations > 0 
          ? _totalOptimizationTime.inMicroseconds / _optimizations 
          : 0.0,
      metrics: List.unmodifiable(_metrics),
    );
  }
  
  /// Reset monitor
  void reset() {
    _metrics.clear();
    _optimizations = 0;
    _gcCalls = 0;
    _totalOptimizationTime = Duration.zero;
  }
  
  /// Dispose monitor
  void dispose() {
    _metrics.clear();
  }
}

/// Memory usage data structure
class MemoryUsage {
  int totalAllocations = 0;
  int totalDeallocations = 0;
  int totalPoolUsage = 0;
  int totalTrackerUsage = 0;
  DateTime? lastGCTime;
  DateTime lastUpdated = DateTime.now();
  
  MemoryUsage();
  
  void reset() {
    totalAllocations = 0;
    totalDeallocations = 0;
    totalPoolUsage = 0;
    totalTrackerUsage = 0;
    lastGCTime = null;
    lastUpdated = DateTime.now();
  }
  
  Map<String, dynamic> toJson() => {
    'totalAllocations': totalAllocations,
    'totalDeallocations': totalDeallocations,
    'totalPoolUsage': totalPoolUsage,
    'totalTrackerUsage': totalTrackerUsage,
    'lastGCTime': lastGCTime?.toIso8601String(),
    'lastUpdated': lastUpdated.toIso8601String(),
  };
}

/// Memory leak data structure
class MemoryLeak {
  final String type;
  final int leakedObjects;
  final int estimatedSize;
  final DateTime detectedAt;
  
  MemoryLeak({
    required this.type,
    required this.leakedObjects,
    required this.estimatedSize,
    required this.detectedAt,
  });
  
  Map<String, dynamic> toJson() => {
    'type': type,
    'leakedObjects': leakedObjects,
    'estimatedSize': estimatedSize,
    'detectedAt': detectedAt.toIso8601String(),
  };
}

/// Memory metric data structure
class MemoryMetric {
  final String type;
  final int value;
  final DateTime timestamp;
  
  MemoryMetric({
    required this.type,
    required this.value,
    required this.timestamp,
  });
}

/// Memory pool configuration
class MemoryPoolConfig {
  final int stringPoolSize;
  final int listPoolSize;
  final int mapPoolSize;
  final int setPoolSize;
  final int bufferPoolSize;
  final bool enableGarbageCollectionOptimization;
  final int gcOptimizationInterval;
  final bool enableLeakDetection;
  final Duration leakDetectionInterval;
  
  MemoryPoolConfig({
    this.stringPoolSize = 1000,
    this.listPoolSize = 500,
    this.mapPoolSize = 200,
    this.setPoolSize = 200,
    this.bufferPoolSize = 100,
    this.enableGarbageCollectionOptimization = true,
    this.gcOptimizationInterval = 30,
    this.enableLeakDetection = true,
    this.leakDetectionInterval = const Duration(minutes: 5),
  });
  
  Map<String, dynamic> toJson() => {
    'stringPoolSize': stringPoolSize,
    'listPoolSize': listPoolSize,
    'mapPoolSize': mapPoolSize,
    'setPoolSize': setPoolSize,
    'bufferPoolSize': bufferPoolSize,
    'enableGarbageCollectionOptimization': enableGarbageCollectionOptimization,
    'gcOptimizationInterval': gcOptimizationInterval,
    'enableLeakDetection': enableLeakDetection,
    'leakDetectionInterval': leakDetectionInterval.inMilliseconds,
  };
  
  factory MemoryPoolConfig.fromJson(Map<String, dynamic> json) {
    return MemoryPoolConfig(
      stringPoolSize: json['stringPoolSize'] as int? ?? 1000,
      listPoolSize: json['listPoolSize'] as int? ?? 500,
      mapPoolSize: json['mapPoolSize'] as int? ?? 200,
      setPoolSize: json['setPoolSize'] as int? ?? 200,
      bufferPoolSize: json['bufferPoolSize'] as int? ?? 100,
      enableGarbageCollectionOptimization: json['enableGarbageCollectionOptimization'] as bool? ?? true,
      gcOptimizationInterval: json['gcOptimizationInterval'] as int? ?? 30,
      enableLeakDetection: json['enableLeakDetection'] as bool? ?? true,
      leakDetectionInterval: Duration(milliseconds: json['leakDetectionInterval'] as int? ?? 300000),
    );
  }
}

/// Memory statistics data structure
class MemoryStatistics {
  final int totalAllocations;
  final int totalDeallocations;
  final int currentUsage;
  final int poolUsage;
  final int trackerUsage;
  final int poolCount;
  final int trackerCount;
  final List<MemoryLeak> memoryLeaks;
  final MemoryPerformanceStatistics performance;
  final DateTime lastUpdated;
  
  MemoryStatistics({
    required this.totalAllocations,
    required this.totalDeallocations,
    required this.currentUsage,
    required this.poolUsage,
    required this.trackerUsage,
    required this.poolCount,
    required this.trackerCount,
    required this.memoryLeaks,
    required this.performance,
    required this.lastUpdated,
  });
}

/// Pool statistics data structure
class PoolStatistics {
  final String name;
  final int totalObjects;
  final int availableObjects;
  final int inUseObjects;
  final double hitRate;
  final double missRate;
  final int memoryUsage;
  
  PoolStatistics({
    required this.name,
    required this.totalObjects,
    required this.availableObjects,
    required this.inUseObjects,
    required this.hitRate,
    required this.missRate,
    required this.memoryUsage,
  });
}

/// Tracker statistics data structure
class TrackerStatistics {
  final String name;
  final int totalAllocations;
  final int totalDeallocations;
  final int currentObjects;
  final int peakObjects;
  final double averageObjectSize;
  final int memoryUsage;
  
  TrackerStatistics({
    required this.name,
    required this.totalAllocations,
    required this.totalDeallocations,
    required this.currentObjects,
    required this.peakObjects,
    required this.averageObjectSize,
    required this.memoryUsage,
  });
}

/// Memory performance statistics data structure
class MemoryPerformanceStatistics {
  final int totalOptimizations;
  final int totalGCCalls;
  final double averageOptimizationTime;
  final List<MemoryMetric> metrics;
  
  MemoryPerformanceStatistics({
    required this.totalOptimizations,
    required this.totalGCCalls,
    required this.averageOptimizationTime,
    required this.metrics,
  });
  
  Map<String, dynamic> toJson() => {
    'totalOptimizations': totalOptimizations,
    'totalGCCalls': totalGCCalls,
    'averageOptimizationTime': averageOptimizationTime,
    'metrics': metrics.map((m) => {
      'type': m.type,
      'value': m.value,
      'timestamp': m.timestamp.toIso8601String(),
    }).toList(),
  };
}
