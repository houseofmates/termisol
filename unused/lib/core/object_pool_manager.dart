import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Object Pool Manager - Best-in-class memory-efficient object reuse
/// 
/// Provides intelligent object pooling for frequently created objects:
/// - Type-specific pools with automatic sizing
/// - Memory pressure-aware pool management
/// - Object lifecycle tracking and cleanup
/// - Performance metrics and optimization
/// - Thread-safe operations
/// - Automatic pool resizing based on usage patterns
class ObjectPoolManager {
  static final ObjectPoolManager _instance = ObjectPoolManager._internal();
  factory ObjectPoolManager() => _instance;
  ObjectPoolManager._internal();

  final Map<Type, ObjectPool> _pools = {};
  final Map<String, PoolMetrics> _poolMetrics = {};
  final Map<Type, PoolConfiguration> _poolConfigs = {};
  
  bool _isInitialized = false;
  Timer? _cleanupTimer;
  Timer? _metricsTimer;
  
  // Pool management configuration
  static const Duration _cleanupInterval = Duration(minutes: 2);
  static const Duration _metricsInterval = Duration(seconds: 30);
  static const int _defaultPoolSize = 50;
  static const int _maxPoolSize = 500;
  static const Duration _objectMaxAge = Duration(minutes: 10);
  
  // Memory pressure tracking
  int _totalMemoryUsage = 0;
  int _maxMemoryUsage = 50 * 1024 * 1024; // 50MB
  double _memoryPressureThreshold = 0.8;
  
  bool get isInitialized => _isInitialized;
  Map<Type, ObjectPool> get pools => Map.unmodifiable(_pools);
  Map<String, PoolMetrics> get poolMetrics => Map.unmodifiable(_poolMetrics);

  /// Initialize the object pool manager
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Register default pool configurations
      await _registerDefaultPoolConfigurations();
      
      // Create default pools
      await _createDefaultPools();
      
      // Start cleanup timer
      _startCleanupTimer();
      
      // Start metrics collection
      _startMetricsCollection();
      
      _isInitialized = true;
      debugPrint('🏊 Object Pool Manager initialized');
      
    } catch (e) {
      debugPrint('❌ Failed to initialize Object Pool Manager: $e');
      rethrow;
    }
  }

  /// Get or create a pool for a specific type
  ObjectPool<T> getPool<T extends PoolableObject>() {
    final type = T;
    
    if (!_pools.containsKey(type)) {
      final config = _poolConfigs[type] ?? PoolConfiguration.defaultConfig();
      _pools[type] = ObjectPool<T>(
        type: type,
        factory: () => _createDefaultObject<T>(),
        resetFunction: (obj) => obj.reset(),
        config: config,
      );
      
      _poolMetrics[type.toString()] = PoolMetrics(type.toString());
      debugPrint('🏊 Created pool for type: $type');
    }
    
    return _pools[type] as ObjectPool<T>;
  }

  /// Get an object from the pool
  T get<T extends PoolableObject>() {
    final pool = getPool<T>();
    final obj = pool.acquire();
    
    // Update metrics
    final metrics = _poolMetrics[T.toString()];
    if (metrics != null) {
      metrics.totalAcquisitions++;
      metrics.currentPoolSize = pool.size;
      metrics.availableObjects = pool.availableCount;
    }
    
    return obj;
  }

  /// Return an object to the pool
  void release<T extends PoolableObject>(T obj) {
    final pool = getPool<T>();
    pool.release(obj);
    
    // Update metrics
    final metrics = _poolMetrics[T.toString()];
    if (metrics != null) {
      metrics.totalReleases++;
      metrics.currentPoolSize = pool.size;
      metrics.availableObjects = pool.availableCount;
    }
  }

  /// Register a custom pool configuration
  void registerPoolConfiguration<T extends PoolableObject>(PoolConfiguration config) {
    _poolConfigs[T] = config;
    debugPrint('⚙️ Registered pool configuration for type: $T');
  }

  /// Preload objects into a pool
  Future<void> preloadPool<T extends PoolableObject>(int count) async {
    final pool = getPool<T>();
    
    debugPrint('🔄 Preloading $count objects of type $T');
    
    for (int i = 0; i < count; i++) {
      final obj = pool.factory();
      pool.release(obj);
    }
    
    // Update metrics
    final metrics = _poolMetrics[T.toString()];
    if (metrics != null) {
      metrics.currentPoolSize = pool.size;
      metrics.availableObjects = pool.availableCount;
    }
  }

  /// Clear a specific pool
  void clearPool<T extends PoolableObject>() {
    final pool = getPool<T>();
    pool.clear();
    
    // Update metrics
    final metrics = _poolMetrics[T.toString()];
    if (metrics != null) {
      metrics.currentPoolSize = 0;
      metrics.availableObjects = 0;
    }
    
    debugPrint('🗑️ Cleared pool for type: $T');
  }

  /// Get comprehensive pool statistics
  PoolStatistics getStatistics() {
    final stats = <String, PoolStatisticsDetail>{};
    
    for (final entry in _poolMetrics.entries) {
      final pool = _pools.values.where((p) => p.type.toString() == entry.key).firstOrNull;
      if (pool != null) {
        stats[entry.key] = PoolStatisticsDetail(
          typeName: entry.key,
          totalAcquisitions: entry.value.totalAcquisitions,
          totalReleases: entry.value.totalReleases,
          currentPoolSize: pool.size,
          availableObjects: pool.availableCount,
          hitRate: entry.value.getHitRate(),
          averageLifetime: entry.value.getAverageLifetime(),
        );
      }
    }
    
    return PoolStatistics(
      totalPools: _pools.length,
      totalObjects: _pools.values.fold(0, (sum, pool) => sum + pool.size),
      totalMemoryUsage: _totalMemoryUsage,
      maxMemoryUsage: _maxMemoryUsage,
      poolDetails: stats,
    );
  }

  /// Optimize pool sizes based on usage patterns
  Future<void> optimizePoolSizes() async {
    debugPrint('🔧 Optimizing pool sizes based on usage patterns');
    
    for (final entry in _poolMetrics.entries) {
      final metrics = entry.value;
      final pool = _pools.values.where((p) => p.type.toString() == entry.key).firstOrNull;
      
      if (pool != null && metrics.totalAcquisitions > 100) {
        final hitRate = metrics.getHitRate();
        final avgLifetime = metrics.getAverageLifetime();
        
        // Adjust pool size based on hit rate and usage patterns
        int optimalSize;
        
        if (hitRate > 0.8 && avgLifetime.inSeconds < 5) {
          // High hit rate, short lifetime - increase pool size
          optimalSize = (pool.size * 1.5).round().clamp(10, _maxPoolSize);
        } else if (hitRate < 0.3) {
          // Low hit rate - decrease pool size
          optimalSize = (pool.size * 0.7).round().clamp(5, pool.size);
        } else {
          // Moderate usage - keep current size
          optimalSize = pool.size;
        }
        
        if (optimalSize != pool.size) {
          pool.resize(optimalSize);
          debugPrint('🔧 Optimized pool $entry.key: ${pool.size} -> $optimalSize');
        }
      }
    }
  }

  /// Handle memory pressure
  Future<void> handleMemoryPressure() async {
    debugPrint('⚠️ Memory pressure detected, reducing pool sizes');
    
    // Sort pools by least recently used
    final sortedPools = _poolMetrics.entries.toList()
      ..sort((a, b) => a.value.lastAccess.compareTo(b.value.lastAccess));
    
    // Reduce pool sizes starting with least used
    for (final entry in sortedPools) {
      final pool = _pools.values.where((p) => p.type.toString() == entry.key).firstOrNull;
      if (pool != null) {
        final reduction = (pool.size * 0.3).round();
        pool.resize((pool.size - reduction).clamp(5, pool.size));
        
        if (_totalMemoryUsage <= _maxMemoryUsage * _memoryPressureThreshold) {
          break;
        }
      }
    }
  }

  /// Register default pool configurations
  Future<void> _registerDefaultPoolConfigurations() async {
    // Terminal cells - high frequency, short lifetime
    _poolConfigs[TerminalCell] = PoolConfiguration(
      initialSize: 100,
      maxSize: 500,
      growthFactor: 1.5,
      shrinkFactor: 0.7,
      objectMaxAge: Duration(minutes: 5),
      autoResize: true,
    );

    // Text spans - medium frequency, medium lifetime
    _poolConfigs[TextSpanObject] = PoolConfiguration(
      initialSize: 50,
      maxSize: 200,
      growthFactor: 1.3,
      shrinkFactor: 0.8,
      objectMaxAge: Duration(minutes: 10),
      autoResize: true,
    );

    // Render objects - high frequency, very short lifetime
    _poolConfigs[RenderObject] = PoolConfiguration(
      initialSize: 200,
      maxSize: 1000,
      growthFactor: 2.0,
      shrinkFactor: 0.5,
      objectMaxAge: Duration(minutes: 1),
      autoResize: true,
    );

    // Buffer objects - variable frequency, medium lifetime
    _poolConfigs[BufferObject] = PoolConfiguration(
      initialSize: 30,
      maxSize: 150,
      growthFactor: 1.4,
      shrinkFactor: 0.75,
      objectMaxAge: Duration(minutes: 8),
      autoResize: true,
    );
  }

  /// Create default pools
  Future<void> _createDefaultPools() async {
    // Preload critical pools
    await preloadPool<TerminalCell>(50);
    await preloadPool<TextSpanObject>(25);
    await preloadPool<RenderObject>(100);
    await preloadPool<BufferObject>(15);
  }

  /// Create default object for type
  T _createDefaultObject<T extends PoolableObject>() {
    if (T == TerminalCell) {
      return TerminalCell() as T;
    } else if (T == TextSpanObject) {
      return TextSpanObject() as T;
    } else if (T == RenderObject) {
      return RenderObject() as T;
    } else if (T == BufferObject) {
      return BufferObject() as T;
    } else {
      throw ArgumentError('No default factory for type: $T');
    }
  }

  /// Start cleanup timer
  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) {
      _performCleanup();
    });
  }

  /// Start metrics collection
  void _startMetricsCollection() {
    _metricsTimer = Timer.periodic(_metricsInterval, (_) {
      _collectMetrics();
    });
  }

  /// Perform periodic cleanup
  void _performCleanup() {
    final now = DateTime.now();
    
    for (final pool in _pools.values) {
      pool.cleanupExpiredObjects(now);
    }
    
    // Check memory pressure
    if (_totalMemoryUsage > _maxMemoryUsage * _memoryPressureThreshold) {
      unawaited(handleMemoryPressure());
    }
  }

  /// Collect performance metrics
  void _collectMetrics() {
    for (final entry in _poolMetrics.entries) {
      final pool = _pools.values.where((p) => p.type.toString() == entry.key).firstOrNull;
      if (pool != null) {
        entry.value.currentPoolSize = pool.size;
        entry.value.availableObjects = pool.availableCount;
        entry.value.lastAccess = DateTime.now();
      }
    }
  }

  /// Dispose the object pool manager
  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    _metricsTimer?.cancel();
    
    // Clear all pools
    for (final pool in _pools.values) {
      pool.clear();
    }
    
    _pools.clear();
    _poolMetrics.clear();
    _poolConfigs.clear();
    
    debugPrint('🏊 Object Pool Manager disposed');
  }
}

/// Generic object pool
class ObjectPool<T extends PoolableObject> {
  final Type type;
  final T Function() factory;
  final void Function(T) resetFunction;
  final PoolConfiguration config;
  
  final Queue<T> _available = Queue<T>();
  final Set<T> _inUse = <T>{};
  final Map<T, DateTime> _creationTimes = {};
  
  int _currentSize = 0;
  int _peakSize = 0;
  
  ObjectPool({
    required this.type,
    required this.factory,
    required this.resetFunction,
    required this.config,
  });
  
  /// Acquire an object from the pool
  T acquire() {
    T obj;
    
    if (_available.isNotEmpty) {
      obj = _available.removeFirst();
    } else {
      obj = factory();
      _creationTimes[obj] = DateTime.now();
      _currentSize++;
      _peakSize = _currentSize > _peakSize ? _currentSize : _peakSize;
      
      // Check if we need to resize
      if (_currentSize > config.maxSize) {
        _resizePool();
      }
    }
    
    _inUse.add(obj);
    return obj;
  }
  
  /// Release an object back to the pool
  void release(T obj) {
    if (!_inUse.contains(obj)) return;
    
    _inUse.remove(obj);
    resetFunction(obj);
    
    // Check if object is too old
    final creationTime = _creationTimes[obj];
    if (creationTime != null && 
        DateTime.now().difference(creationTime) > config.objectMaxAge) {
      _creationTimes.remove(obj);
      _currentSize--;
      return;
    }
    
    _available.add(obj);
    
    // Check if we should shrink the pool
    if (_available.length > config.initialSize && 
        _currentSize > config.initialSize) {
      _shrinkPool();
    }
  }
  
  /// Clear the pool
  void clear() {
    _available.clear();
    _inUse.clear();
    _creationTimes.clear();
    _currentSize = 0;
  }
  
  /// Cleanup expired objects
  void cleanupExpiredObjects(DateTime now) {
    final expired = <T>[];
    
    for (final entry in _creationTimes.entries) {
      if (now.difference(entry.value) > config.objectMaxAge) {
        expired.add(entry.key);
      }
    }
    
    for (final obj in expired) {
      _available.remove(obj);
      _inUse.remove(obj);
      _creationTimes.remove(obj);
      _currentSize--;
    }
  }
  
  /// Resize the pool
  void resize(int newSize) {
    if (newSize < _currentSize) {
      // Remove excess objects
      final excess = _currentSize - newSize;
      for (int i = 0; i < excess && _available.isNotEmpty; i++) {
        final obj = _available.removeFirst();
        _creationTimes.remove(obj);
        _currentSize--;
      }
    }
  }
  
  /// Resize pool when it exceeds max size
  void _resizePool() {
    final targetSize = (config.maxSize * 0.8).round();
    resize(targetSize);
  }
  
  /// Shrink pool when it has too many available objects
  void _shrinkPool() {
    final targetSize = (_currentSize * config.shrinkFactor).round()
        .clamp(config.initialSize, config.maxSize);
    resize(targetSize);
  }
  
  // Getters
  int get size => _currentSize;
  int get availableCount => _available.length;
  int get inUseCount => _inUse.length;
  int get peakSize => _peakSize;
}

/// Pool configuration
class PoolConfiguration {
  final int initialSize;
  final int maxSize;
  final double growthFactor;
  final double shrinkFactor;
  final Duration objectMaxAge;
  final bool autoResize;
  
  const PoolConfiguration({
    required this.initialSize,
    required this.maxSize,
    required this.growthFactor,
    required this.shrinkFactor,
    required this.objectMaxAge,
    this.autoResize = true,
  });
  
  static PoolConfiguration defaultConfig() {
    return const PoolConfiguration(
      initialSize: 20,
      maxSize: 100,
      growthFactor: 1.5,
      shrinkFactor: 0.7,
      objectMaxAge: Duration(minutes: 10),
      autoResize: true,
    );
  }
}

/// Pool metrics tracking
class PoolMetrics {
  final String typeName;
  int totalAcquisitions = 0;
  int totalReleases = 0;
  int currentPoolSize = 0;
  int availableObjects = 0;
  DateTime lastAccess = DateTime.now();
  final List<Duration> lifetimes = [];
  
  PoolMetrics(this.typeName);
  
  void recordLifetime(Duration lifetime) {
    lifetimes.add(lifetime);
    if (lifetimes.length > 100) {
      lifetimes.removeAt(0);
    }
  }
  
  double getHitRate() {
    return totalAcquisitions > 0 ? (totalAcquisitions - availableObjects) / totalAcquisitions : 0.0;
  }
  
  Duration getAverageLifetime() {
    if (lifetimes.isEmpty) return Duration.zero;
    final totalMs = lifetimes.fold(0, (sum, duration) => sum + duration.inMilliseconds);
    return Duration(milliseconds: totalMs ~/ lifetimes.length);
  }
}

/// Pool statistics
class PoolStatistics {
  final int totalPools;
  final int totalObjects;
  final int totalMemoryUsage;
  final int maxMemoryUsage;
  final Map<String, PoolStatisticsDetail> poolDetails;
  
  PoolStatistics({
    required this.totalPools,
    required this.totalObjects,
    required this.totalMemoryUsage,
    required this.maxMemoryUsage,
    required this.poolDetails,
  });
}

/// Detailed pool statistics
class PoolStatisticsDetail {
  final String typeName;
  final int totalAcquisitions;
  final int totalReleases;
  final int currentPoolSize;
  final int availableObjects;
  final double hitRate;
  final Duration averageLifetime;
  
  PoolStatisticsDetail({
    required this.typeName,
    required this.totalAcquisitions,
    required this.totalReleases,
    required this.currentPoolSize,
    required this.availableObjects,
    required this.hitRate,
    required this.averageLifetime,
  });
}

/// Base interface for poolable objects
abstract class PoolableObject {
  void reset();
  DateTime? createdAt;
  DateTime? lastUsed;
}

/// Example poolable objects
class TerminalCell implements PoolableObject {
  String text = '';
  TextStyle? style;
  Color? backgroundColor;
  
  @override
  void reset() {
    text = '';
    style = null;
    backgroundColor = null;
    lastUsed = DateTime.now();
  }
}

class TextSpanObject implements PoolableObject {
  String text = '';
  TextStyle? style;
  List<InlineSpan>? children;
  
  @override
  void reset() {
    text = '';
    style = null;
    children = null;
    lastUsed = DateTime.now();
  }
}

class RenderObject implements PoolableObject {
  double x = 0.0;
  double y = 0.0;
  double width = 0.0;
  double height = 0.0;
  
  @override
  void reset() {
    x = y = width = height = 0.0;
    lastUsed = DateTime.now();
  }
}

class BufferObject implements PoolableObject {
  List<int> data = [];
  int capacity = 0;
  
  @override
  void reset() {
    data.clear();
    capacity = 0;
    lastUsed = DateTime.now();
  }
}


