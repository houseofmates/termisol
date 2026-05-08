import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Memory optimizer that monitors and manages memory usage across the application.
/// Implements intelligent caching, garbage collection hints, and memory pressure handling.
class MemoryOptimizer {
  static const Duration monitoringInterval = Duration(seconds: 5);
  static const int maxCacheSize = 50; // Maximum cached items
  static const Duration cacheExpiry = Duration(minutes: 10);
  static const double memoryPressureThreshold = 0.8; // 80% memory usage

  final StreamController<MemoryEvent> _eventController = StreamController.broadcast();
  final Map<String, CacheEntry> _memoryCache = {};
  final Queue<String> _accessOrder = Queue();
  final Map<String, MemoryRegion> _trackedRegions = {};

  Timer? _monitoringTimer;
  bool _aggressiveOptimization = false;
  int _totalAllocatedBytes = 0;
  int _cacheHits = 0;
  int _cacheMisses = 0;
  DateTime? _lastGcHint;

  /// Stream of memory events
  Stream<MemoryEvent> get events => _eventController.stream;

  /// Current memory usage ratio (0.0 to 1.0)
  double get memoryUsageRatio => _estimateMemoryUsage();

  /// Cache hit ratio
  double get cacheHitRatio {
    final total = _cacheHits + _cacheMisses;
    return total > 0 ? _cacheHits / total : 0.0;
  }

  /// Whether aggressive optimization is enabled
  bool get aggressiveOptimization => _aggressiveOptimization;

  /// Total bytes in cache
  int get cacheSizeBytes => _calculateCacheSize();

  MemoryOptimizer() {
    _initialize();
  }

  void _initialize() {
    // Start memory monitoring
    _monitoringTimer = Timer.periodic(monitoringInterval, (_) {
      _monitorMemory();
    });

    // Set up cleanup on low memory
    _setupLowMemoryHandler();

    debugPrint('MemoryOptimizer initialized');
  }

  void _setupLowMemoryHandler() {
    // Note: In Flutter, we can listen to platform messages for memory pressure
    // This is a simplified implementation
    debugPrint('Low memory handler set up');
  }

  /// Store data in memory cache with optional expiry
  void cacheData(String key, dynamic data, {
    Duration? expiry,
    int? sizeBytes,
    CachePriority priority = CachePriority.normal,
  }) {
    final entry = CacheEntry(
      key: key,
      data: data,
      sizeBytes: sizeBytes ?? _estimateDataSize(data),
      expiry: expiry ?? cacheExpiry,
      priority: priority,
      createdAt: DateTime.now(),
    );

    // Remove existing entry if present
    _memoryCache.remove(key);
    _accessOrder.removeWhere((k) => k == key);

    // Add new entry
    _memoryCache[key] = entry;
    _accessOrder.add(key);
    _totalAllocatedBytes += entry.sizeBytes;

    // Enforce cache limits
    _enforceCacheLimits();

    _eventController.add(MemoryEvent.cached(key, entry.sizeBytes));
  }

  /// Retrieve data from cache
  dynamic getCachedData(String key) {
    final entry = _memoryCache[key];

    if (entry == null) {
      _cacheMisses++;
      return null;
    }

    // Check expiry
    if (DateTime.now().difference(entry.createdAt) > entry.expiry) {
      removeFromCache(key);
      _cacheMisses++;
      return null;
    }

    // Update access order for LRU
    _accessOrder.removeWhere((k) => k == key);
    _accessOrder.add(key);

    _cacheHits++;
    _eventController.add(MemoryEvent.cacheHit(key));
    return entry.data;
  }

  /// Remove data from cache
  void removeFromCache(String key) {
    final entry = _memoryCache.remove(key);
    if (entry != null) {
      _accessOrder.removeWhere((k) => k == key);
      _totalAllocatedBytes -= entry.sizeBytes;
      _eventController.add(MemoryEvent.removed(key, entry.sizeBytes));
    }
  }

  /// Clear all cache data
  void clearCache() {
    final clearedBytes = _totalAllocatedBytes;
    _memoryCache.clear();
    _accessOrder.clear();
    _totalAllocatedBytes = 0;
    _cacheHits = 0;
    _cacheMisses = 0;

    _eventController.add(MemoryEvent.cacheCleared(clearedBytes));
    debugPrint('Memory cache cleared: ${clearedBytes} bytes freed');
  }

  void _enforceCacheLimits() {
    // Remove expired entries
    final expiredKeys = <String>[];
    final now = DateTime.now();

    for (final entry in _memoryCache.values) {
      if (now.difference(entry.createdAt) > entry.expiry) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      removeFromCache(key);
    }

    // Enforce size limits using LRU eviction
    while (_memoryCache.length > maxCacheSize || _totalAllocatedBytes > _getMaxCacheBytes()) {
      if (_accessOrder.isEmpty) break;

      final lruKey = _accessOrder.removeFirst();
      removeFromCache(lruKey);
    }
  }

  int _getMaxCacheBytes() {
    // Allow up to 50MB cache on desktop, 25MB on mobile
    final isDesktop = defaultTargetPlatform == TargetPlatform.linux ||
                      defaultTargetPlatform == TargetPlatform.windows ||
                      defaultTargetPlatform == TargetPlatform.macOS;

    return isDesktop ? 50 * 1024 * 1024 : 25 * 1024 * 1024;
  }

  int _estimateDataSize(dynamic data) {
    // Rough estimation based on data type
    if (data == null) return 0;

    if (data is String) {
      return data.length * 2; // UTF-16 estimate
    } else if (data is List) {
      return data.length * 8; // Pointer size estimate
    } else if (data is Map) {
      return data.length * 16; // Key-value pair estimate
    } else {
      return 64; // Default object size
    }
  }

  double _estimateMemoryUsage() {
    // Simplified memory usage estimation
    // In a real implementation, this would use platform-specific APIs
    final cacheUsage = _totalAllocatedBytes / (100 * 1024 * 1024); // Assume 100MB heap
    return cacheUsage.clamp(0.0, 1.0);
  }

  void _monitorMemory() {
    final usageRatio = memoryUsageRatio;

    if (usageRatio > memoryPressureThreshold) {
      _handleMemoryPressure(usageRatio);
    }

    _eventController.add(MemoryEvent.memoryUsage(usageRatio, _totalAllocatedBytes));
  }

  void _handleMemoryPressure(double usageRatio) {
    debugPrint('Memory pressure detected: ${(usageRatio * 100).toStringAsFixed(1)}%');

    // Enable aggressive optimization
    _aggressiveOptimization = true;

    // Clear low-priority cache entries
    final lowPriorityKeys = _memoryCache.entries
        .where((entry) => entry.value.priority == CachePriority.low)
        .map((entry) => entry.key)
        .toList();

    for (final key in lowPriorityKeys) {
      removeFromCache(key);
    }

    // Suggest garbage collection
    _suggestGarbageCollection();

    _eventController.add(MemoryEvent.memoryPressure(usageRatio));
  }

  void _suggestGarbageCollection() {
    // In Flutter/Dart, we can't force GC, but we can hint at it
    // by allocating and discarding some memory to trigger it
    if (_lastGcHint == null || DateTime.now().difference(_lastGcHint!) > Duration(minutes: 1)) {
      try {
        // Hint at GC by creating and discarding objects
        final hint = List.filled(1000, null);
        // Let it go out of scope immediately
        hint.clear();
      } catch (e) {
        // Ignore errors in hinting
      }

      _lastGcHint = DateTime.now();
      debugPrint('GC hint sent');
    }
  }

  /// Register a memory region for tracking
  void registerMemoryRegion(String regionId, int initialSizeBytes) {
    _trackedRegions[regionId] = MemoryRegion(
      id: regionId,
      allocatedBytes: initialSizeBytes,
      peakBytes: initialSizeBytes,
      allocations: 1,
    );

    _eventController.add(MemoryEvent.regionRegistered(regionId, initialSizeBytes));
  }

  /// Update memory region allocation
  void updateMemoryRegion(String regionId, int newSizeBytes) {
    final region = _trackedRegions[regionId];
    if (region != null) {
      final oldSize = region.allocatedBytes;
      region.allocatedBytes = newSizeBytes;
      region.allocations++;
      region.peakBytes = region.peakBytes > newSizeBytes ? region.peakBytes : newSizeBytes;

      _eventController.add(MemoryEvent.regionUpdated(regionId, oldSize, newSizeBytes));
    }
  }

  /// Unregister a memory region
  void unregisterMemoryRegion(String regionId) {
    final region = _trackedRegions.remove(regionId);
    if (region != null) {
      _eventController.add(MemoryEvent.regionUnregistered(regionId, region.allocatedBytes));
    }
  }

  /// Get memory statistics
  Map<String, dynamic> getMemoryStats() {
    return {
      'memoryUsageRatio': memoryUsageRatio,
      'cacheSizeBytes': cacheSizeBytes,
      'cacheHitRatio': cacheHitRatio,
      'totalCacheEntries': _memoryCache.length,
      'aggressiveOptimization': _aggressiveOptimization,
      'trackedRegions': _trackedRegions.length,
      'totalTrackedBytes': _trackedRegions.values.fold(0, (sum, r) => sum + r.allocatedBytes),
      'lastGcHint': _lastGcHint?.toIso8601String(),
    };
  }

  /// Force memory optimization
  void optimizeMemory() {
    clearCache();
    _suggestGarbageCollection();
    _aggressiveOptimization = false; // Reset after manual optimization

    _eventController.add(MemoryEvent.optimizationTriggered());
    debugPrint('Memory optimization completed');
  }

  /// Enable or disable aggressive optimization
  void setAggressiveOptimization(bool enabled) {
    _aggressiveOptimization = enabled;
    debugPrint('Aggressive optimization ${enabled ? 'enabled' : 'disabled'}');
  }

  int _calculateCacheSize() {
    return _memoryCache.values.fold(0, (sum, entry) => sum + entry.sizeBytes);
  }

  /// Dispose resources
  void dispose() {
    _monitoringTimer?.cancel();
    clearCache();
    _trackedRegions.clear();
    _eventController.close();
    debugPrint('MemoryOptimizer disposed');
  }
}

/// Cache entry with metadata
class CacheEntry {
  final String key;
  final dynamic data;
  final int sizeBytes;
  final Duration expiry;
  final CachePriority priority;
  final DateTime createdAt;

  const CacheEntry({
    required this.key,
    required this.data,
    required this.sizeBytes,
    required this.expiry,
    required this.priority,
    required this.createdAt,
  });
}

/// Memory region for tracking allocations
class MemoryRegion {
  final String id;
  int allocatedBytes;
  int peakBytes;
  int allocations;

  MemoryRegion({
    required this.id,
    required this.allocatedBytes,
    required this.peakBytes,
    required this.allocations,
  });
}

/// Memory event types
class MemoryEvent {
  final MemoryEventType type;
  final String? key;
  final int? bytes;
  final int? oldBytes;
  final double? ratio;

  const MemoryEvent._(this.type, {this.key, this.bytes, this.oldBytes, this.ratio});

  factory MemoryEvent.cached(String key, int bytes) {
    return MemoryEvent._(MemoryEventType.cached, key: key, bytes: bytes);
  }

  factory MemoryEvent.cacheHit(String key) {
    return MemoryEvent._(MemoryEventType.cacheHit, key: key);
  }

  factory MemoryEvent.removed(String key, int bytes) {
    return MemoryEvent._(MemoryEventType.removed, key: key, bytes: bytes);
  }

  factory MemoryEvent.cacheCleared(int bytes) {
    return MemoryEvent._(MemoryEventType.cacheCleared, bytes: bytes);
  }

  factory MemoryEvent.memoryUsage(double ratio, int bytes) {
    return MemoryEvent._(MemoryEventType.memoryUsage, ratio: ratio, bytes: bytes);
  }

  factory MemoryEvent.memoryPressure(double ratio) {
    return MemoryEvent._(MemoryEventType.memoryPressure, ratio: ratio);
  }

  factory MemoryEvent.regionRegistered(String regionId, int bytes) {
    return MemoryEvent._(MemoryEventType.regionRegistered, key: regionId, bytes: bytes);
  }

  factory MemoryEvent.regionUpdated(String regionId, int oldBytes, int newBytes) {
    return MemoryEvent._(MemoryEventType.regionUpdated, key: regionId, bytes: newBytes, oldBytes: oldBytes);
  }

  factory MemoryEvent.regionUnregistered(String regionId, int bytes) {
    return MemoryEvent._(MemoryEventType.regionUnregistered, key: regionId, bytes: bytes);
  }

  factory MemoryEvent.optimizationTriggered() {
    return MemoryEvent._(MemoryEventType.optimizationTriggered);
  }
}

/// Cache priority levels
enum CachePriority {
  low,
  normal,
  high,
  critical,
}

/// Memory event types
enum MemoryEventType {
  cached,
  cacheHit,
  removed,
  cacheCleared,
  memoryUsage,
  memoryPressure,
  regionRegistered,
  regionUpdated,
  regionUnregistered,
  optimizationTriggered,
}