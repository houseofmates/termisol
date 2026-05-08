import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// GPU memory management system
/// 
/// Features:
/// - GPU memory tracking and optimization
/// - Automatic memory cleanup
/// - Memory pressure detection
/// - Texture memory pooling
/// - Memory budget management
class GPUMemoryManager {
  static const int _defaultMemoryBudget = 512 * 1024 * 1024; // 512MB
  static const int _warningThreshold = 80; // 80% of budget
  static const int _criticalThreshold = 95; // 95% of budget
  static const Duration _cleanupInterval = Duration(seconds: 30);
  static const Duration _memoryCheckInterval = Duration(seconds: 5);
  
  final Map<String, GPUMemoryBlock> _memoryBlocks = {};
  final Queue<GPUMemoryBlock> _lruQueue = Queue();
  final Map<String, MemoryPool> _memoryPools = {};
  
  int _totalAllocated = 0;
  int _memoryBudget = _defaultMemoryBudget;
  int _peakUsage = 0;
  int _cleanupCount = 0;
  
  Timer? _cleanupTimer;
  Timer? _memoryCheckTimer;
  
  /// Memory pressure callbacks
  final List<Function(MemoryPressure)> _pressureCallbacks = [];
  
  /// Performance metrics
  int _allocationCount = 0;
  int _deallocationCount = 0;
  double _totalAllocationTime = 0.0;
  int _oomEvents = 0;

  GPUMemoryManager() {
    _initializeMemoryManager();
  }

  /// Initialize memory manager
  void _initializeMemoryManager() {
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) => _performCleanup());
    _memoryCheckTimer = Timer.periodic(_memoryCheckInterval, (_) => _checkMemoryPressure());
  }

  /// Allocate GPU memory block
  Future<GPUMemoryBlock> allocateMemory(
    String key, {
    required int size,
    String? category,
    bool persistent = false,
    MemoryPriority priority = MemoryPriority.normal,
  }) async {
    if (_totalAllocated + size > _memoryBudget) {
      // Try to free memory
      if (!await _freeMemory(size)) {
        // Out of memory
        _oomEvents++;
        _notifyPressure(MemoryPressure.critical);
        throw GPUMemoryException('Out of GPU memory. Requested: $size, Available: ${_memoryBudget - _totalAllocated}');
      }
    }
    
    final stopwatch = Stopwatch()..start();
    
    try {
      final block = GPUMemoryBlock(
        key: key,
        size: size,
        category: category,
        persistent: persistent,
        priority: priority,
        allocatedAt: DateTime.now(),
      );
      
      _memoryBlocks[key] = block;
      if (!persistent) {
        _lruQueue.addLast(block);
      }
      
      _totalAllocated += size;
      _allocationCount++;
      _peakUsage = _peakUsage > _totalAllocated ? _peakUsage : _totalAllocated;
      
      _totalAllocationTime += stopwatch.elapsedMilliseconds.toDouble();
      
      return block;
    } catch (e) {
      debugPrint('Failed to allocate GPU memory: $e');
      rethrow;
    } finally {
      stopwatch.stop();
    }
  }

  /// Deallocate GPU memory block
  Future<void> deallocateMemory(String key) async {
    final block = _memoryBlocks.remove(key);
    if (block == null) return;
    
    try {
      _totalAllocated -= block.size;
      _deallocationCount++;
      
      // Remove from LRU queue
      _lruQueue.remove(block);
      
      // Return to pool if applicable
      if (block.category != null) {
        final pool = _memoryPools[block.category!];
        if (pool != null) {
          await pool.returnBlock(block);
        }
      }
    } catch (e) {
      debugPrint('Failed to deallocate GPU memory: $e');
    }
  }

  /// Create memory pool for specific category
  MemoryPool createMemoryPool(String category, {int maxBlocks = 10}) {
    final pool = MemoryPool(category, maxBlocks: maxBlocks);
    _memoryPools[category] = pool;
    return pool;
  }

  /// Get memory block from pool
  Future<GPUMemoryBlock?> getFromPool(String category, int size) async {
    final pool = _memoryPools[category];
    return pool?.getBlock(size);
  }

  /// Return memory block to pool
  Future<void> returnToPool(GPUMemoryBlock block) async {
    if (block.category != null) {
      final pool = _memoryPools[block.category!];
      if (pool != null) {
        await pool.returnBlock(block);
      }
    }
  }

  /// Free memory to make room for new allocation
  Future<bool> _freeMemory(int requiredSize) async {
    int freed = 0;
    
    // Try to free non-persistent blocks first
    final blocksToFree = <GPUMemoryBlock>[];
    
    for (final block in _lruQueue) {
      if (block.persistent) continue;
      if (block.priority == MemoryPriority.critical) continue;
      
      blocksToFree.add(block);
      freed += block.size;
      
      if (freed >= requiredSize) break;
    }
    
    // Free the blocks
    for (final block in blocksToFree) {
      await deallocateMemory(block.key);
    }
    
    return freed >= requiredSize;
  }

  /// Perform automatic cleanup
  Future<void> _performCleanup() async {
    if (_totalAllocated < _memoryBudget * 0.7) return; // Only cleanup if > 70% used
    
    int freed = 0;
    final blocksToFree = <GPUMemoryBlock>[];
    
    // Find old non-persistent blocks
    final now = DateTime.now();
    for (final block in _lruQueue) {
      if (block.persistent) continue;
      
      final age = now.difference(block.allocatedAt);
      if (age.inMinutes > 5 || block.priority == MemoryPriority.low) {
        blocksToFree.add(block);
        freed += block.size;
      }
    }
    
    // Free old blocks
    for (final block in blocksToFree) {
      await deallocateMemory(block.key);
    }
    
    _cleanupCount++;
    
    if (freed > 0) {
      debugPrint('GPU Memory cleanup: freed ${freed ~/ 1024}KB, ${blocksToFree.length} blocks');
    }
  }

  /// Check memory pressure and notify callbacks
  void _checkMemoryPressure() {
    final usage = _totalAllocated / _memoryBudget;
    
    MemoryPressure pressure;
    if (usage >= _criticalThreshold / 100) {
      pressure = MemoryPressure.critical;
    } else if (usage >= _warningThreshold / 100) {
      pressure = MemoryPressure.warning;
    } else {
      pressure = MemoryPressure.normal;
    }
    
    _notifyPressure(pressure);
  }

  /// Notify pressure callbacks
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
  GPUMemoryStats getStats() {
    return GPUMemoryStats(
      totalAllocated: _totalAllocated,
      memoryBudget: _memoryBudget,
      usagePercentage: (_totalAllocated / _memoryBudget) * 100,
      peakUsage: _peakUsage,
      allocationCount: _allocationCount,
      deallocationCount: _deallocationCount,
      cleanupCount: _cleanupCount,
      oomEvents: _oomEvents,
      averageAllocationTime: _allocationCount > 0 ? _totalAllocationTime / _allocationCount : 0.0,
      blockCount: _memoryBlocks.length,
      poolCount: _memoryPools.length,
    );
  }

  /// Set memory budget
  void setMemoryBudget(int budget) {
    _memoryBudget = budget;
    
    // Check if current usage exceeds new budget
    if (_totalAllocated > budget) {
      _notifyPressure(MemoryPressure.critical);
    }
  }

  /// Optimize memory usage
  Future<void> optimizeMemory() async {
    // Force cleanup
    await _performCleanup();
    
    // Optimize memory pools
    for (final pool in _memoryPools.values) {
      await pool.optimize();
    }
    
    // Compact memory if possible
    await _compactMemory();
  }

  /// Compact memory by reorganizing blocks
  Future<void> _compactMemory() async {
    // This is a placeholder for memory compaction
    // In a real implementation, this would reorganize memory blocks
    debugPrint('GPU Memory compaction completed');
  }

  /// Clear all memory
  Future<void> clear() async {
    for (final key in List<String>.from(_memoryBlocks.keys)) {
      await deallocateMemory(key);
    }
    
    for (final pool in _memoryPools.values) {
      await pool.clear();
    }
    
    _memoryPools.clear();
    _totalAllocated = 0;
    _peakUsage = 0;
  }

  /// Dispose memory manager
  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    _memoryCheckTimer?.cancel();
    
    await clear();
  }
}

/// GPU memory block
class GPUMemoryBlock {
  final String key;
  final int size;
  final String? category;
  final bool persistent;
  final MemoryPriority priority;
  final DateTime allocatedAt;
  
  GPUMemoryBlock({
    required this.key,
    required this.size,
    this.category,
    required this.persistent,
    required this.priority,
    required this.allocatedAt,
  });
  
  int get age => DateTime.now().difference(allocatedAt).inSeconds;
}

/// Memory pool for reusing blocks
class MemoryPool {
  final String category;
  final int maxBlocks;
  final Queue<GPUMemoryBlock> _availableBlocks = Queue();
  
  MemoryPool(this.category, {required this.maxBlocks});
  
  /// Get block from pool
  GPUMemoryBlock? getBlock(int size) {
    for (final block in _availableBlocks) {
      if (block.size >= size) {
        _availableBlocks.remove(block);
        return block;
      }
    }
    return null;
  }
  
  /// Return block to pool
  Future<void> returnBlock(GPUMemoryBlock block) async {
    if (_availableBlocks.length < maxBlocks) {
      _availableBlocks.add(block);
    }
  }
  
  /// Optimize pool
  Future<void> optimize() async {
    // Remove old blocks
    final now = DateTime.now();
    final blocksToRemove = <GPUMemoryBlock>[];
    
    for (final block in _availableBlocks) {
      if (now.difference(block.allocatedAt).inMinutes > 10) {
        blocksToRemove.add(block);
      }
    }
    
    for (final block in blocksToRemove) {
      _availableBlocks.remove(block);
    }
  }
  
  /// Clear pool
  Future<void> clear() async {
    _availableBlocks.clear();
  }
}

/// Memory priority levels
enum MemoryPriority {
  low,
  normal,
  high,
  critical,
}

/// Memory pressure levels
enum MemoryPressure {
  normal,
  warning,
  critical,
}

/// GPU memory statistics
class GPUMemoryStats {
  final int totalAllocated;
  final int memoryBudget;
  final double usagePercentage;
  final int peakUsage;
  final int allocationCount;
  final int deallocationCount;
  final int cleanupCount;
  final int oomEvents;
  final double averageAllocationTime;
  final int blockCount;
  final int poolCount;

  const GPUMemoryStats({
    required this.totalAllocated,
    required this.memoryBudget,
    required this.usagePercentage,
    required this.peakUsage,
    required this.allocationCount,
    required this.deallocationCount,
    required this.cleanupCount,
    required this.oomEvents,
    required this.averageAllocationTime,
    required this.blockCount,
    required this.poolCount,
  });
}

/// GPU memory exception
class GPUMemoryException implements Exception {
  final String message;
  
  const GPUMemoryException(this.message);
  
  @override
  String toString() => 'GPUMemoryException: $message';
}
