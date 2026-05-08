import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/foundation.dart';

/// Dynamic memory allocation system
/// 
/// Features:
/// - Adaptive memory pool sizing
/// - Memory fragmentation prevention
/// - Automatic memory compaction
/// - Memory usage monitoring and optimization
/// - Support for different allocation strategies
class DynamicMemoryAllocator {
  static const int _initialPoolSize = 1024 * 1024; // 1MB
  static const int _maxPoolSize = 64 * 1024 * 1024; // 64MB
  static const int _minBlockSize = 64;
  static const int _maxBlockSize = 1024 * 1024; // 1MB
  static const Duration _compactionInterval = Duration(minutes: 2);
  static const double _fragmentationThreshold = 0.3; // 30% fragmentation
  
  final Map<int, MemoryPool> _pools = {};
  final Map<int, MemoryBlock> _allocatedBlocks = {};
  final Queue<MemoryBlock> _freeBlocks = Queue();
  final Map<String, AllocationStrategy> _strategies = {};
  
  int _totalAllocated = 0;
  int _totalFree = 0;
  int _fragmentationLevel = 0;
  int _compactionCount = 0;
  int _allocationCount = 0;
  int _deallocationCount = 0;
  
  Timer? _compactionTimer;
  
  /// Memory pressure callbacks
  final List<Function(MemoryPressure)> _pressureCallbacks = [];
  
  /// Performance metrics
  double _totalAllocationTime = 0.0;
  double _totalCompactionTime = 0.0;
  int _oomEvents = 0;

  DynamicMemoryAllocator() {
    _initializeAllocator();
  }

  /// Initialize the memory allocator
  void _initializeAllocator() {
    // Create initial memory pools
    _createMemoryPools();
    
    // Setup allocation strategies
    _setupAllocationStrategies();
    
    // Start compaction timer
    _compactionTimer = Timer.periodic(_compactionInterval, (_) => _performCompaction());
  }

  /// Create memory pools for different block sizes
  void _createMemoryPools() {
    // Create pools for different size ranges
    final sizeRanges = [
      64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536,
    ];
    
    for (final size in sizeRanges) {
      _pools[size] = MemoryPool(size, _initialPoolSize ~/ size);
    }
  }

  /// Setup allocation strategies
  void _setupAllocationStrategies() {
    _strategies['first_fit'] = FirstFitStrategy();
    _strategies['best_fit'] = BestFitStrategy();
    _strategies['worst_fit'] = WorstFitStrategy();
    _strategies['buddy'] = BuddySystemStrategy();
  }

  /// Allocate memory block
  Future<MemoryBlock> allocate(
    int size, {
    String? strategy = 'best_fit',
    String? category,
    bool persistent = false,
  }) async {
    if (size <= 0 || size > _maxBlockSize) {
      throw ArgumentError('Invalid block size: $size');
    }
    
    final stopwatch = Stopwatch()..start();
    
    try {
      _allocationCount++;
      
      // Find appropriate pool
      final poolSize = _findPoolSize(size);
      final pool = _pools[poolSize];
      
      if (pool == null) {
        // Create new pool if needed
        final newPool = MemoryPool(poolSize, max(10, _initialPoolSize ~/ poolSize));
        _pools[poolSize] = newPool;
        return await allocate(size, strategy: strategy, category: category);
      }
      
      // Allocate from pool
      final block = await pool.allocate(size, category: category, persistent: persistent);
      if (block == null) {
        // Pool is full, try to expand or compact
        if (!await _expandPool(pool) && !await _performCompaction()) {
          _oomEvents++;
          _notifyPressure(MemoryPressure.critical);
          throw OutOfMemoryException('Failed to allocate $size bytes');
        }
        
        // Retry allocation
        return await allocate(size, strategy: strategy, category: category);
      }
      
      _allocatedBlocks[block.id] = block;
      _totalAllocated += block.size;
      
      _totalAllocationTime += stopwatch.elapsedMilliseconds.toDouble();
      
      return block;
    } catch (e) {
      debugPrint('Failed to allocate memory: $e');
      rethrow;
    } finally {
      stopwatch.stop();
    }
  }

  /// Deallocate memory block
  Future<void> deallocate(MemoryBlock block) async {
    if (!_allocatedBlocks.containsKey(block.id)) {
      return; // Already deallocated
    }
    
    try {
      _deallocationCount++;
      _totalAllocated -= block.size;
      _totalFree += block.size;
      
      // Return to pool
      final poolSize = _findPoolSize(block.size);
      final pool = _pools[poolSize];
      
      if (pool != null) {
        await pool.deallocate(block);
      }
      
      _allocatedBlocks.remove(block.id);
    } catch (e) {
      debugPrint('Failed to deallocate memory: $e');
    }
  }

  /// Find appropriate pool size for block
  int _findPoolSize(int size) {
    // Find smallest pool that can accommodate the size
    final sortedSizes = _pools.keys.toList()..sort();
    
    for (final poolSize in sortedSizes) {
      if (poolSize >= size) {
        return poolSize;
      }
    }
    
    return _maxBlockSize;
  }

  /// Expand memory pool
  Future<bool> _expandPool(MemoryPool pool) async {
    if (pool.totalSize >= _maxPoolSize) {
      return false;
    }
    
    try {
      final newSize = min(pool.totalSize * 2, _maxPoolSize);
      await pool.expand(newSize);
      return true;
    } catch (e) {
      debugPrint('Failed to expand pool: $e');
      return false;
    }
  }

  /// Perform memory compaction
  Future<bool> _performCompaction() async {
    final stopwatch = Stopwatch()..start();
    
    try {
      // Calculate fragmentation
      _calculateFragmentation();
      
      if (_fragmentationLevel < _fragmentationThreshold) {
        return true; // No compaction needed
      }
      
      // Compact each pool
      bool compacted = false;
      for (final pool in _pools.values) {
        if (await pool.compact()) {
          compacted = true;
        }
      }
      
      if (compacted) {
        _compactionCount++;
        _totalCompactionTime += stopwatch.elapsedMilliseconds.toDouble();
      }
      
      return compacted;
    } catch (e) {
      debugPrint('Failed to perform compaction: $e');
      return false;
    } finally {
      stopwatch.stop();
    }
  }

  /// Calculate memory fragmentation
  void _calculateFragmentation() {
    int totalFree = 0;
    int largestFree = 0;
    final freeBlocks = <int>[];
    
    for (final pool in _pools.values) {
      for (final block in pool.freeBlocks) {
        totalFree += block.size;
        freeBlocks.add(block.size);
        largestFree = max(largestFree, block.size);
      }
    }
    
    if (totalFree == 0) {
      _fragmentationLevel = 0;
      return;
    }
    
    // Fragmentation = 1 - (largest free block / total free)
    _fragmentationLevel = ((1 - (largestFree / totalFree)) * 100).round();
  }

  /// Notify memory pressure
  void _notifyPressure(MemoryPressure pressure) {
    for (final callback in _pressureCallbacks) {
      try {
        callback(pressure);
      } catch (e) {
        debugPrint('Error in memory pressure callback: $e');
      }
    }
  }

  /// Add memory pressure callback
  void addPressureCallback(Function(MemoryPressure) callback) {
    _pressureCallbacks.add(callback);
  }

  /// Remove memory pressure callback
  void removePressureCallback(Function(MemoryPressure) callback) {
    _pressureCallbacks.remove(callback);
  }

  /// Get memory statistics
  MemoryStats getStats() {
    return MemoryStats(
      totalAllocated: _totalAllocated,
      totalFree: _totalFree,
      totalPools: _pools.length,
      allocatedBlocks: _allocatedBlocks.length,
      fragmentationLevel: _fragmentationLevel,
      compactionCount: _compactionCount,
      allocationCount: _allocationCount,
      deallocationCount: _deallocationCount,
      averageAllocationTime: _allocationCount > 0 ? _totalAllocationTime / _allocationCount : 0.0,
      averageCompactionTime: _compactionCount > 0 ? _totalCompactionTime / _compactionCount : 0.0,
      oomEvents: _oomEvents,
      memoryEfficiency: _totalAllocated + _totalFree > 0 ? _totalAllocated / (_totalAllocated + _totalFree) : 0.0,
    );
  }

  /// Optimize memory usage
  Future<void> optimizeMemory() async {
    // Force compaction
    await _performCompaction();
    
    // Optimize pools
    for (final pool in _pools.values) {
      await pool.optimize();
    }
    
    // Remove empty pools
    final emptyPools = <int>[];
    for (final entry in _pools.entries) {
      if (entry.value.isEmpty) {
        emptyPools.add(entry.key);
      }
    }
    
    for (final poolSize in emptyPools) {
      _pools.remove(poolSize);
    }
  }

  /// Clear all allocated memory
  Future<void> clear() async {
    for (final block in List<MemoryBlock>.from(_allocatedBlocks.values)) {
      await deallocate(block);
    }
    
    for (final pool in _pools.values) {
      await pool.clear();
    }
    
    _totalAllocated = 0;
    _totalFree = 0;
    _fragmentationLevel = 0;
  }

  /// Dispose memory allocator
  Future<void> dispose() async {
    _compactionTimer?.cancel();
    await clear();
    _pressureCallbacks.clear();
  }
}

/// Memory pool for managing blocks of specific size
class MemoryPool {
  final int blockSize;
  int totalSize;
  final List<MemoryBlock> freeBlocks = [];
  final List<MemoryBlock> allocatedBlocks = [];
  Uint8List? _memory;

  MemoryPool(this.blockSize, this.totalSize) {
    _memory = Uint8List(totalSize);
    _initializeBlocks();
  }

  /// Initialize blocks in pool
  void _initializeBlocks() {
    final blockCount = totalSize ~/ blockSize;
    
    for (int i = 0; i < blockCount; i++) {
      final block = MemoryBlock(
        id: '${blockSize}_$i',
        offset: i * blockSize,
        size: blockSize,
        pool: this,
      );
      
      freeBlocks.add(block);
    }
  }

  /// Allocate block from pool
  Future<MemoryBlock?> allocate(
    int size, {
    String? category,
    bool persistent = false,
  }) async {
    if (size > blockSize) return null;
    
    if (freeBlocks.isEmpty) return null;
    
    final block = freeBlocks.removeLast();
    block.allocated = true;
    block.category = category;
    block.persistent = persistent;
    block.allocatedAt = DateTime.now();
    
    allocatedBlocks.add(block);
    
    return block;
  }

  /// Deallocate block back to pool
  Future<void> deallocate(MemoryBlock block) async {
    if (!allocatedBlocks.contains(block)) return;
    
    block.allocated = false;
    block.category = null;
    block.persistent = false;
    
    allocatedBlocks.remove(block);
    freeBlocks.add(block);
  }

  /// Expand pool size
  Future<void> expand(int newSize) async {
    if (newSize <= totalSize) return;
    
    final oldMemory = _memory;
    final oldSize = totalSize;
    
    _memory = Uint8List(newSize);
    totalSize = newSize;
    
    // Copy old memory
    if (oldMemory != null) {
      _memory!.setRange(0, oldSize, oldMemory);
    }
    
    // Create new blocks
    final newBlockCount = (newSize - oldSize) ~/ blockSize;
    final startBlockIndex = oldSize ~/ blockSize;
    
    for (int i = 0; i < newBlockCount; i++) {
      final block = MemoryBlock(
        id: '${blockSize}_${startBlockIndex + i}',
        offset: (startBlockIndex + i) * blockSize,
        size: blockSize,
        pool: this,
      );
      
      freeBlocks.add(block);
    }
  }

  /// Compact pool memory
  Future<bool> compact() async {
    // Simple compaction: move all allocated blocks to the beginning
    allocatedBlocks.sort((a, b) => a.offset.compareTo(b.offset));
    
    bool compacted = false;
    int currentOffset = 0;
    
    for (final block in allocatedBlocks) {
      if (block.offset != currentOffset) {
        // Move block data
        if (_memory != null) {
          final blockData = _memory!.sublist(block.offset, block.offset + block.size);
          _memory!.setRange(currentOffset, currentOffset + block.size, blockData);
        }
        
        block.offset = currentOffset;
        compacted = true;
      }
      
      currentOffset += block.size;
    }
    
    return compacted;
  }

  /// Optimize pool
  Future<void> optimize() async {
    // Remove old non-persistent blocks
    final now = DateTime.now();
    final blocksToFree = <MemoryBlock>[];
    
    for (final block in allocatedBlocks) {
      if (!block.persistent && now.difference(block.allocatedAt).inMinutes > 5) {
        blocksToFree.add(block);
      }
    }
    
    for (final block in blocksToFree) {
      await deallocate(block);
    }
  }

  /// Clear pool
  Future<void> clear() async {
    for (final block in List<MemoryBlock>.from(allocatedBlocks)) {
      await deallocate(block);
    }
    
    freeBlocks.clear();
    _initializeBlocks();
  }

  /// Check if pool is empty
  bool get isEmpty => allocatedBlocks.isEmpty && freeBlocks.isEmpty;

  /// Get pool statistics
  PoolStats getStats() {
    return PoolStats(
      blockSize: blockSize,
      totalSize: totalSize,
      allocatedBlocks: allocatedBlocks.length,
      freeBlocks: freeBlocks.length,
      utilization: totalSize > 0 ? (allocatedBlocks.length * blockSize) / totalSize : 0.0,
    );
  }
}

/// Memory block
class MemoryBlock {
  final String id;
  int offset;
  final int size;
  final MemoryPool pool;
  
  bool allocated = false;
  String? category;
  bool persistent = false;
  DateTime allocatedAt = DateTime.now();

  MemoryBlock({
    required this.id,
    required this.offset,
    required this.size,
    required this.pool,
  });

  /// Get pointer to memory (simplified)
  Uint8List? get pointer {
    if (!allocated || pool._memory == null) return null;
    return Uint8List.view(
      pool._memory!.buffer,
      pool._memory!.offsetInBytes + offset,
      size,
    );
  }
}

/// Allocation strategy interface
abstract class AllocationStrategy {
  Future<MemoryBlock?> allocate(int size, List<MemoryBlock> freeBlocks);
}

/// First-fit allocation strategy
class FirstFitStrategy implements AllocationStrategy {
  @override
  Future<MemoryBlock?> allocate(int size, List<MemoryBlock> freeBlocks) async {
    for (final block in freeBlocks) {
      if (block.size >= size) {
        return block;
      }
    }
    return null;
  }
}

/// Best-fit allocation strategy
class BestFitStrategy implements AllocationStrategy {
  @override
  Future<MemoryBlock?> allocate(int size, List<MemoryBlock> freeBlocks) async {
    MemoryBlock? bestFit;
    
    for (final block in freeBlocks) {
      if (block.size >= size) {
        if (bestFit == null || block.size < bestFit.size) {
          bestFit = block;
        }
      }
    }
    
    return bestFit;
  }
}

/// Worst-fit allocation strategy
class WorstFitStrategy implements AllocationStrategy {
  @override
  Future<MemoryBlock?> allocate(int size, List<MemoryBlock> freeBlocks) async {
    MemoryBlock? worstFit;
    
    for (final block in freeBlocks) {
      if (block.size >= size) {
        if (worstFit == null || block.size > worstFit.size) {
          worstFit = block;
        }
      }
    }
    
    return worstFit;
  }
}

/// Buddy system allocation strategy
class BuddySystemStrategy implements AllocationStrategy {
  @override
  Future<MemoryBlock?> allocate(int size, List<MemoryBlock> freeBlocks) async {
    // Simplified buddy system - just return first fit
    return FirstFitStrategy().allocate(size, freeBlocks);
  }
}

/// Memory pressure levels
enum MemoryPressure {
  normal,
  warning,
  critical,
}

/// Memory statistics
class MemoryStats {
  final int totalAllocated;
  final int totalFree;
  final int totalPools;
  final int allocatedBlocks;
  final int fragmentationLevel;
  final int compactionCount;
  final int allocationCount;
  final int deallocationCount;
  final double averageAllocationTime;
  final double averageCompactionTime;
  final int oomEvents;
  final double memoryEfficiency;

  const MemoryStats({
    required this.totalAllocated,
    required this.totalFree,
    required this.totalPools,
    required this.allocatedBlocks,
    required this.fragmentationLevel,
    required this.compactionCount,
    required this.allocationCount,
    required this.deallocationCount,
    required this.averageAllocationTime,
    required this.averageCompactionTime,
    required this.oomEvents,
    required this.memoryEfficiency,
  });
}

/// Pool statistics
class PoolStats {
  final int blockSize;
  final int totalSize;
  final int allocatedBlocks;
  final int freeBlocks;
  final double utilization;

  const PoolStats({
    required this.blockSize,
    required this.totalSize,
    required this.allocatedBlocks,
    required this.freeBlocks,
    required this.utilization,
  });
}

/// Out of memory exception
class OutOfMemoryException implements Exception {
  final String message;
  
  const OutOfMemoryException(this.message);
  
  @override
  String toString() => 'OutOfMemoryException: $message';
}
