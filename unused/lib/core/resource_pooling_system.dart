import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'package:flutter/foundation.dart';

/// Resource pooling system for efficient resource management
/// 
/// Features:
/// - Generic resource pooling with type safety
/// - Automatic pool sizing and optimization
/// - Resource lifecycle management
/// - Performance monitoring and metrics
/// - Support for different pooling strategies
class ResourcePoolingSystem {
  static const int _defaultMaxPoolSize = 100;
  static const Duration _cleanupInterval = Duration(minutes: 5);
  static const Duration _resourceTimeout = Duration(minutes: 10);
  static const double _poolUtilizationThreshold = 0.8;
  
  final Map<String, ResourcePool> _pools = {};
  final Map<Type, PoolFactory> _factories = {};
  final List<PoolMetrics> _metrics = [];
  
  Timer? _cleanupTimer;
  
  int _totalCreated = 0;
  int _totalReused = 0;
  int _totalDestroyed = 0;
  int _activePools = 0;
  
  /// Pool event callbacks
  final List<Function(PoolEvent)> _eventCallbacks = [];

  ResourcePoolingSystem() {
    _initializePoolingSystem();
  }

  /// Initialize the pooling system
  void _initializePoolingSystem() {
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) => _performCleanup());
  }

  /// Register a resource factory
  void registerFactory<T>(PoolFactory<T> factory) {
    _factories[T] = factory;
  }

  /// Create or get a resource pool
  ResourcePool<T> getPool<T>({
    String? name,
    int? maxSize,
    PoolStrategy strategy = PoolStrategy.lifo,
    Duration? timeout,
  }) {
    final poolName = name ?? T.toString();
    
    if (!_pools.containsKey(poolName)) {
      final factory = _factories[T];
      if (factory == null) {
        throw ArgumentError('No factory registered for type $T');
      }
      
      final pool = ResourcePool<T>(
        name: poolName,
        factory: factory,
        maxSize: maxSize ?? _defaultMaxPoolSize,
        strategy: strategy,
        timeout: timeout ?? _resourceTimeout,
      );
      
      _pools[poolName] = pool;
      _activePools++;
      
      _notifyEvent(PoolEvent.created(poolName));
    }
    
    return _pools[poolName] as ResourcePool<T>;
  }

  /// Acquire resource from pool
  Future<T?> acquire<T>({
    String? poolName,
    Map<String, dynamic>? parameters,
  }) async {
    final pool = getPool<T>(name: poolName);
    final resource = await pool.acquire(parameters);
    
    if (resource != null) {
      _totalReused++;
      _notifyEvent(PoolEvent.resourceAcquired(pool.name, resource));
    }
    
    return resource;
  }

  /// Release resource back to pool
  Future<void> release<T>(T resource, {String? poolName}) async {
    final pool = getPool<T>(name: poolName);
    await pool.release(resource);
    _notifyEvent(PoolEvent.resourceReleased(pool.name, resource));
  }

  /// Create resource directly (bypassing pool)
  Future<T> create<T>({Map<String, dynamic>? parameters}) async {
    final factory = _factories[T];
    if (factory == null) {
      throw ArgumentError('No factory registered for type $T');
    }
    
    final resource = await factory.create(parameters);
    _totalCreated++;
    _notifyEvent(PoolEvent.resourceCreated(T.toString(), resource));
    
    return resource;
  }

  /// Destroy resource
  Future<void> destroy<T>(T resource) async {
    final factory = _factories[T];
    if (factory != null) {
      await factory.destroy(resource);
      _totalDestroyed++;
      _notifyEvent(PoolEvent.resourceDestroyed(T.toString(), resource));
    }
  }

  /// Perform cleanup of idle resources
  Future<void> _performCleanup() async {
    for (final pool in _pools.values) {
      await pool.cleanup();
    }
    
    // Remove empty pools
    final emptyPools = <String>[];
    for (final entry in _pools.entries) {
      if (entry.value.isEmpty) {
        emptyPools.add(entry.key);
      }
    }
    
    for (final poolName in emptyPools) {
      _pools.remove(poolName);
      _activePools--;
      _notifyEvent(PoolEvent.destroyed(poolName));
    }
  }

  /// Notify pool event
  void _notifyEvent(PoolEvent event) {
    for (final callback in _eventCallbacks) {
      try {
        callback(event);
      } catch (e) {
        debugPrint('Error in pool event callback: $e');
      }
    }
  }

  /// Add event callback
  void addEventCallback(Function(PoolEvent) callback) {
    _eventCallbacks.add(callback);
  }

  /// Remove event callback
  void removeEventCallback(Function(PoolEvent) callback) {
    _eventCallbacks.remove(callback);
  }

  /// Get pooling statistics
  PoolingStats getStats() {
    int totalAvailable = 0;
    int totalInUse = 0;
    int totalCapacity = 0;
    double totalUtilization = 0.0;
    
    for (final pool in _pools.values) {
      final stats = pool.getStats();
      totalAvailable += stats.available;
      totalInUse += stats.inUse;
      totalCapacity += stats.capacity;
      totalUtilization += stats.utilization;
    }
    
    final averageUtilization = _pools.isNotEmpty ? totalUtilization / _pools.length : 0.0;
    final reuseRate = _totalCreated + _totalReused > 0 
        ? _totalReused / (_totalCreated + _totalReused) 
        : 0.0;
    
    return PoolingStats(
      totalCreated: _totalCreated,
      totalReused: _totalReused,
      totalDestroyed: _totalDestroyed,
      activePools: _activePools,
      totalAvailable: totalAvailable,
      totalInUse: totalInUse,
      totalCapacity: totalCapacity,
      averageUtilization: averageUtilization,
      reuseRate: reuseRate,
    );
  }

  /// Optimize all pools
  Future<void> optimizePools() async {
    for (final pool in _pools.values) {
      await pool.optimize();
    }
  }

  /// Clear all pools
  Future<void> clear() async {
    for (final pool in _pools.values) {
      await pool.clear();
    }
    _pools.clear();
    _activePools = 0;
  }

  /// Dispose pooling system
  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    await clear();
    _factories.clear();
    _eventCallbacks.clear();
  }
}

/// Generic resource pool
class ResourcePool<T> {
  final String name;
  final PoolFactory<T> factory;
  final int maxSize;
  final PoolStrategy strategy;
  final Duration timeout;
  
  final Queue<PooledResource<T>> _available = Queue();
  final Set<PooledResource<T>> _inUse = {};
  
  int _created = 0;
  int _acquired = 0;
  int _released = 0;
  int _destroyed = 0;

  ResourcePool({
    required this.name,
    required this.factory,
    required this.maxSize,
    required this.strategy,
    required this.timeout,
  });

  /// Acquire resource from pool
  Future<T?> acquire([Map<String, dynamic>? parameters]) async {
    _acquired++;
    
    // Try to get from available pool
    PooledResource<T>? pooledResource;
    
    switch (strategy) {
      case PoolStrategy.fifo:
        pooledResource = _available.isNotEmpty ? _available.removeFirst() : null;
        break;
      case PoolStrategy.lifo:
        pooledResource = _available.isNotEmpty ? _available.removeLast() : null;
        break;
      case PoolStrategy.random:
        if (_available.isNotEmpty) {
          final index = Random().nextInt(_available.length);
          pooledResource = _available.elementAt(index);
          _available.remove(pooledResource);
        }
        break;
    }
    
    // Create new resource if needed
    if (pooledResource == null) {
      if (_inUse.length + _available.length >= maxSize) {
        return null; // Pool is full
      }
      
      final resource = await factory.create(parameters);
      pooledResource = PooledResource<T>(
        resource: resource,
        createdAt: DateTime.now(),
        lastUsed: DateTime.now(),
      );
      _created++;
    }
    
    // Validate and reset resource
    if (await _validateResource(pooledResource)) {
      await factory.reset(pooledResource.resource);
      pooledResource.lastUsed = DateTime.now();
      _inUse.add(pooledResource);
      return pooledResource.resource;
    } else {
      // Resource is invalid, destroy it
      await factory.destroy(pooledResource.resource);
      _destroyed++;
      return await acquire(parameters); // Try again
    }
  }

  /// Release resource back to pool
  Future<void> release(T resource) async {
    _released++;
    
    // Find the pooled resource
    PooledResource<T>? pooledResource;
    for (final pr in _inUse) {
      if (identical(pr.resource, resource)) {
        pooledResource = pr;
        break;
      }
    }
    
    if (pooledResource == null) return;
    
    _inUse.remove(pooledResource);
    
    // Check if resource is still valid
    if (await _validateResource(pooledResource)) {
      await factory.cleanup(pooledResource.resource);
      pooledResource.lastUsed = DateTime.now();
      
      // Add back to available pool
      if (_available.length < maxSize) {
        _available.add(pooledResource);
      } else {
        // Pool is full, destroy the resource
        await factory.destroy(pooledResource.resource);
        _destroyed++;
      }
    } else {
      // Resource is invalid, destroy it
      await factory.destroy(pooledResource.resource);
      _destroyed++;
    }
  }

  /// Validate resource
  Future<bool> _validateResource(PooledResource<T> pooledResource) async {
    // Check timeout
    if (DateTime.now().difference(pooledResource.lastUsed) > timeout) {
      return false;
    }
    
    // Use factory validation
    return await factory.validate(pooledResource.resource);
  }

  /// Cleanup idle resources
  Future<void> cleanup() async {
    final now = DateTime.now();
    final toRemove = <PooledResource<T>>[];
    
    // Remove expired resources from available pool
    for (final resource in _available) {
      if (now.difference(resource.lastUsed) > timeout) {
        toRemove.add(resource);
      }
    }
    
    for (final resource in toRemove) {
      _available.remove(resource);
      await factory.destroy(resource.resource);
      _destroyed++;
    }
  }

  /// Optimize pool
  Future<void> optimize() async {
    // Adjust pool size based on usage patterns
    final utilization = getStats().utilization;
    
    if (utilization > 0.9 && maxSize < 200) {
      // Pool is heavily utilized, consider increasing size
      debugPrint('Pool $name is highly utilized (${(utilization * 100).toStringAsFixed(1)}%)');
    } else if (utilization < 0.2 && maxSize > 10) {
      // Pool is underutilized, consider decreasing size
      debugPrint('Pool $name is underutilized (${(utilization * 100).toStringAsFixed(1)}%)');
    }
  }

  /// Clear pool
  Future<void> clear() async {
    // Destroy all available resources
    for (final resource in _available) {
      await factory.destroy(resource.resource);
      _destroyed++;
    }
    
    // Note: Resources in use are not destroyed here
    _available.clear();
  }

  /// Check if pool is empty
  bool get isEmpty => _available.isEmpty && _inUse.isEmpty;

  /// Get pool statistics
  PoolStats getStats() {
    final capacity = maxSize;
    final available = _available.length;
    final inUse = _inUse.length;
    final utilization = capacity > 0 ? (inUse + available) / capacity : 0.0;
    
    return PoolStats(
      totalCreated: _created,
      totalReused: _acquired - _created,
      totalDestroyed: _destroyed,
      activePools: 1,
      totalAvailable: available,
      totalInUse: inUse,
      totalCapacity: capacity,
      averageUtilization: utilization,
      reuseRate: _acquired > 0 ? (_acquired - _created) / _acquired : 0.0,
    );
  }
}

/// Pooled resource wrapper
class PooledResource<T> {
  final T resource;
  final DateTime createdAt;
  DateTime lastUsed;

  PooledResource({
    required this.resource,
    required this.createdAt,
    required this.lastUsed,
  });
}

/// Pool factory interface
abstract class PoolFactory<T> {
  Future<T> create([Map<String, dynamic>? parameters]);
  Future<void> destroy(T resource);
  Future<bool> validate(T resource);
  Future<void> reset(T resource);
  Future<void> cleanup(T resource);
}

/// Pooling strategies
enum PoolStrategy {
  fifo,
  lifo,
  random,
}

/// Pool events
class PoolEvent {
  final PoolEventType type;
  final String poolName;
  final dynamic resource;

  const PoolEvent(this.type, this.poolName, this.resource);

  factory PoolEvent.created(String poolName) => PoolEvent(PoolEventType.created, poolName, null);
  factory PoolEvent.destroyed(String poolName) => PoolEvent(PoolEventType.destroyed, poolName, null);
  factory PoolEvent.resourceAcquired(String poolName, dynamic resource) => 
      PoolEvent(PoolEventType.resourceAcquired, poolName, resource);
  factory PoolEvent.resourceReleased(String poolName, dynamic resource) => 
      PoolEvent(PoolEventType.resourceReleased, poolName, resource);
  factory PoolEvent.resourceCreated(String poolName, dynamic resource) => 
      PoolEvent(PoolEventType.resourceCreated, poolName, resource);
  factory PoolEvent.resourceDestroyed(String poolName, dynamic resource) => 
      PoolEvent(PoolEventType.resourceDestroyed, poolName, resource);
}

enum PoolEventType {
  created,
  destroyed,
  resourceAcquired,
  resourceReleased,
  resourceCreated,
  resourceDestroyed,
}

/// Pooling statistics
class PoolingStats {
  final int totalCreated;
  final int totalReused;
  final int totalDestroyed;
  final int activePools;
  final int totalAvailable;
  final int totalInUse;
  final int totalCapacity;
  final double averageUtilization;
  final double reuseRate;

  const PoolingStats({
    required this.totalCreated,
    required this.totalReused,
    required this.totalDestroyed,
    required this.activePools,
    required this.totalAvailable,
    required this.totalInUse,
    required this.totalCapacity,
    required this.averageUtilization,
    required this.reuseRate,
  });
}

/// Example factory for database connections - demonstrates resource pooling pattern
class DatabaseConnectionFactory implements PoolFactory<DatabaseConnection> {
  @override
  Future<DatabaseConnection> create([Map<String, dynamic>? parameters]) async {
    final connection = DatabaseConnection();
    await connection.connect(parameters?['host'], parameters?['port'] ?? 5432);
    return connection;
  }

  @override
  Future<void> destroy(DatabaseConnection resource) async {
    await resource.disconnect();
  }

  @override
  Future<bool> validate(DatabaseConnection resource) async {
    return await resource.isConnected();
  }

  @override
  Future<void> reset(DatabaseConnection resource) async {
    await resource.reset();
  }

  @override
  Future<void> cleanup(DatabaseConnection resource) async {
    await resource.cleanup();
  }
}

/// Example database connection class - shows pooled resource implementation
class DatabaseConnection {
  bool _connected = false;
  
  Future<void> connect(String host, int port) async {
    _connected = true;
  }
  
  Future<void> disconnect() async {
    _connected = false;
  }
  
  Future<bool> isConnected() async => _connected;
  
  Future<void> reset() async {
    // Reset connection state
  }
  
  Future<void> cleanup() async {
    // Cleanup connection
  }
}
