import 'dart:async';
import 'dart:developer' as developer;
import 'dart:collection';
import 'dart:typed_data';

class MemoryPooling {
  static const int _smallObjectSize = 64;
  static const int _mediumObjectSize = 256;
  static const int _largeObjectSize = 1024;
  static const int _maxPoolSize = 1000;
  
  final Queue<ByteBuffer> _smallPool = Queue();
  final Queue<ByteBuffer> _mediumPool = Queue();
  final Queue<ByteBuffer> _largePool = Queue();
  final Map<String, MemoryPool> _customPools = {};
  
  int _totalAllocations = 0;
  int _totalDeallocations = 0;
  int _poolHits = 0;
  int _poolMisses = 0;
  
  void initialize() {
    _preallocatePools();
    developer.log('🧠 Memory Pooling initialized');
  }

  void _preallocatePools() {
    // Pre-allocate buffers for each pool size
    for (int i = 0; i < _maxPoolSize ~/ 3; i++) {
      _smallPool.add(ByteBuffer.allocate(_smallObjectSize));
      _mediumPool.add(ByteBuffer.allocate(_mediumObjectSize));
      _largePool.add(ByteBuffer.allocate(_largeObjectSize));
    }
  }

  ByteBuffer allocate(int size) {
    _totalAllocations++;
    
    // Determine appropriate pool based on size
    if (size <= _smallObjectSize) {
      return _allocateFromPool(_smallPool, 'small', size);
    } else if (size <= _mediumObjectSize) {
      return _allocateFromPool(_mediumPool, 'medium', size);
    } else if (size <= _largeObjectSize) {
      return _allocateFromPool(_largePool, 'large', size);
    } else {
      // For large objects, use custom pool or allocate directly
      return _allocateCustom(size);
    }
  }

  ByteBuffer _allocateFromPool(Queue<ByteBuffer> pool, String poolName, int size) {
    if (pool.isNotEmpty) {
      _poolHits++;
      final buffer = pool.removeFirst();
      developer.log('🧠 Pool hit: $poolName (${buffer.lengthInBytes} bytes requested, ${size} bytes used)');
      return buffer;
    } else {
      _poolMisses++;
      // Allocate new buffer if pool is empty
      final buffer = ByteBuffer.allocate(size);
      developer.log('🧠 Pool miss: $poolName - allocated new buffer (${size} bytes)');
      return buffer;
    }
  }

  ByteBuffer _allocateCustom(int size) {
    final poolKey = 'custom_$size';
    final pool = _customPools.putIfAbsent(
      poolKey,
      () => MemoryPool(size: size, maxSize: 100),
    );
    
    return pool.allocate();
  }

  void deallocate(ByteBuffer buffer) {
    _totalDeallocations++;
    
    final size = buffer.lengthInBytes;
    
    // Return to appropriate pool based on size
    if (size <= _smallObjectSize) {
      _deallocateToPool(_smallPool, 'small', buffer);
    } else if (size <= _mediumObjectSize) {
      _deallocateToPool(_mediumPool, 'medium', buffer);
    } else if (size <= _largeObjectSize) {
      _deallocateToPool(_largePool, 'large', buffer);
    } else {
      _deallocateCustom(buffer);
    }
  }

  void _deallocateToPool(Queue<ByteBuffer> pool, String poolName, ByteBuffer buffer) {
    if (pool.length < _maxPoolSize ~/ 3) {
      // Clear buffer and return to pool
      final byteData = buffer.asByteData();
      for (int i = 0; i < byteData.lengthInBytes; i++) {
        byteData.setUint8(i, 0);
      }
      pool.add(buffer);
      developer.log('🧠 Returned to pool: $poolName (${buffer.lengthInBytes} bytes)');
    } else {
      // Pool is full, let GC handle it
      developer.log('🧠 Pool full: $poolName - letting GC handle');
    }
  }

  void _deallocateCustom(ByteBuffer buffer) {
    final size = buffer.lengthInBytes;
    final poolKey = 'custom_$size';
    final pool = _customPools[poolKey];
    
    if (pool != null) {
      pool.deallocate(buffer);
    }
  }

  void createCustomPool(String name, int size, {int maxSize = 100}) {
    final pool = MemoryPool(size: size, maxSize: maxSize);
    _customPools[name] = pool;
    developer.log('🧠 Created custom pool: $name (${size} bytes, max ${maxSize} objects)');
  }

  void preallocatePool(String name, int count) {
    final pool = _customPools[name];
    if (pool == null) return;
    
    for (int i = 0; i < count; i++) {
      pool.allocate();
    }
    
    developer.log('🧠 Pre-allocated $count objects in pool: $name');
  }

  void optimizePools() {
    // Clean up underutilized custom pools
    final poolsToCleanup = <String>[];
    
    for (final entry in _customPools.entries) {
      final pool = entry.value;
      if (pool.utilization < 0.1) { // Less than 10% utilization
        poolsToCleanup.add(entry.key);
      }
    }
    
    for (final poolName in poolsToCleanup) {
      _customPools.remove(poolName);
      developer.log('🧠 Cleaned up underutilized pool: $poolName');
    }
  }

  MemoryPoolStats getStats() {
    return MemoryPoolStats(
      totalAllocations: _totalAllocations,
      totalDeallocations: _totalDeallocations,
      poolHits: _poolHits,
      poolMisses: _poolMisses,
      hitRate: _totalAllocations > 0 ? _poolHits / _totalAllocations : 0.0,
      smallPoolSize: _smallPool.length,
      mediumPoolSize: _mediumPool.length,
      largePoolSize: _largePool.length,
      customPoolsCount: _customPools.length,
    );
  }

  void dispose() {
    _smallPool.clear();
    _mediumPool.clear();
    _largePool.clear();
    _customPools.clear();
    
    developer.log('🧠 Memory Pooling disposed');
  }
}

class MemoryPool {
  final int size;
  final int maxSize;
  final Queue<ByteBuffer> _pool = Queue();
  int _allocatedCount = 0;
  int _deallocatedCount = 0;

  MemoryPool({
    required this.size,
    required this.maxSize,
  });

  ByteBuffer allocate() {
    _allocatedCount++;
    
    if (_pool.isNotEmpty) {
      return _pool.removeFirst();
    } else {
      return ByteBuffer.allocate(size);
    }
  }

  void deallocate(ByteBuffer buffer) {
    _deallocatedCount++;
    
    if (_pool.length < maxSize) {
      // Clear buffer and return to pool
      final byteData = buffer.asByteData();
      for (int i = 0; i < byteData.lengthInBytes; i++) {
        byteData.setUint8(i, 0);
      }
      _pool.add(buffer);
    }
  }

  double get utilization {
    final totalObjects = _allocatedCount;
    final pooledObjects = _pool.length;
    return totalObjects > 0 ? pooledObjects / totalObjects : 0.0;
  }

  int get allocatedCount => _allocatedCount;
  int get deallocatedCount => _deallocatedCount;
  int get poolSize => _pool.length;
}

class MemoryPoolStats {
  final int totalAllocations;
  final int totalDeallocations;
  final int poolHits;
  final int poolMisses;
  final double hitRate;
  final int smallPoolSize;
  final int mediumPoolSize;
  final int largePoolSize;
  final int customPoolsCount;

  MemoryPoolStats({
    required this.totalAllocations,
    required this.totalDeallocations,
    required this.poolHits,
    required this.poolMisses,
    required this.hitRate,
    required this.smallPoolSize,
    required this.mediumPoolSize,
    required this.largePoolSize,
    required this.customPoolsCount,
  });
}
