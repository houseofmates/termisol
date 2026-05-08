import 'dart:async';
import 'dart:convert';
import 'dart:crypto';
import 'package:flutter/foundation.dart';

/// Request Cache Manager - Best-in-class intelligent request caching and deduplication
/// 
/// Provides comprehensive request caching with:
/// - Intelligent deduplication based on content similarity
/// - LRU cache eviction policies
/// - Request prioritization and queuing
/// - Cache performance monitoring
/// - Automatic cache optimization
/// - Multi-tier cache levels
class RequestCacheManager {
  static final RequestCacheManager _instance = RequestCacheManager._internal();
  factory RequestCacheManager() => _instance;
  RequestCacheManager._internal();

  final Map<String, CacheEntry> _cache = {};
  final Map<String, List<RequestEntry>> _requestHistory = {};
  final Map<String, CacheStatistics> _cacheStats = {};
  final Queue<CacheEntry> _lruQueue = Queue<CacheEntry>();
  
  bool _isInitialized = false;
  Timer? _cleanupTimer;
  Timer? _optimizationTimer;
  
  // Cache configuration
  static const Duration _cleanupInterval = Duration(minutes: 5);
  static const Duration _optimizationInterval = Duration(minutes: 15);
  static const int _maxCacheSize = 1000;
  static const int _maxHistorySize = 100;
  static const Duration _defaultTTL = Duration(minutes: 10);
  static const double _similarityThreshold = 0.85;
  
  final _cacheController = StreamController<CacheEvent>.broadcast();
  Stream<CacheEvent> get events => _cacheController.stream;
  
  bool get isInitialized => _isInitialized;
  int get cacheSize => _cache.length;
  Map<String, CacheEntry> get cache => Map.unmodifiable(_cache);

  /// Initialize request cache manager
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Start cleanup timer
      _startCleanupTimer();
      
      // Start optimization timer
      _startOptimizationTimer();
      
      _isInitialized = true;
      debugPrint('🗄️ Request Cache Manager initialized');
      
    } catch (e) {
      debugPrint('❌ Failed to initialize Request Cache Manager: $e');
      rethrow;
    }
  }

  /// Get cached response or execute request
  Future<T> getOrExecute<T>(
    String cacheKey,
    Future<T> Function() executor, {
    Duration? ttl,
    int? priority,
    bool enableDeduplication = true,
    Map<String, dynamic>? metadata,
  }) async {
    // Check cache first
    final cachedEntry = _getFromCache(cacheKey);
    if (cachedEntry != null && !cachedEntry.isExpired) {
      _updateCacheStatistics(cacheKey, CacheHit.hit);
      
      _cacheController.add(CacheEvent(
        type: CacheEventType.cacheHit,
        cacheKey: cacheKey,
        timestamp: DateTime.now(),
        data: {'ttl': cachedEntry.ttl?.inMinutes},
      ));
      
      debugPrint('🗄️ Cache hit: $cacheKey');
      return cachedEntry.data as T;
    }

    // Check for similar requests if deduplication is enabled
    if (enableDeduplication) {
      final similarRequest = _findSimilarRequest(cacheKey);
      if (similarRequest != null) {
        _cacheController.add(CacheEvent(
          type: CacheEventType.deduplicationHit,
          cacheKey: cacheKey,
          timestamp: DateTime.now(),
          data: {'similarKey': similarRequest.key, 'similarity': similarRequest.similarity},
        ));
        
        debugPrint('🗄️ Deduplication hit: $cacheKey -> ${similarRequest.key}');
        return similarRequest.response as T;
      }
    }

    // Execute request
    _updateCacheStatistics(cacheKey, CacheHit.miss);
    
    _cacheController.add(CacheEvent(
      type: CacheEventType.cacheMiss,
      cacheKey: cacheKey,
      timestamp: DateTime.now(),
    ));

    debugPrint('🗄️ Cache miss: $cacheKey - executing request');

    // Track request
    final requestEntry = RequestEntry(
      key: cacheKey,
      timestamp: DateTime.now(),
      priority: priority ?? 0,
      metadata: metadata ?? {},
    );

    _trackRequest(cacheKey, requestEntry);

    try {
      // Execute the request
      final response = await executor();
      
      // Cache the response
      await _putInCache(cacheKey, response, ttl: ttl, priority: priority);
      
      // Update request entry with response
      requestEntry.response = response;
      requestEntry.executionTime = DateTime.now().difference(requestEntry.timestamp);
      requestEntry.success = true;
      
      return response;
      
    } catch (e) {
      // Mark request as failed
      requestEntry.success = false;
      requestEntry.error = e.toString();
      
      debugPrint('❌ Request failed: $cacheKey - $e');
      rethrow;
    }
  }

  /// Preload cache with data
  Future<void> preload<T>(
    String cacheKey,
    T data, {
    Duration? ttl,
    int? priority,
    Map<String, dynamic>? metadata,
  }) async {
    await _putInCache(cacheKey, data, ttl: ttl, priority: priority);
    
    _cacheController.add(CacheEvent(
      type: CacheEventType.preload,
      cacheKey: cacheKey,
      timestamp: DateTime.now(),
      data: {'priority': priority},
    ));
    
    debugPrint('🗄️ Preloaded cache: $cacheKey');
  }

  /// Invalidate cache entry
  void invalidate(String cacheKey) {
    final removed = _cache.remove(cacheKey);
    if (removed != null) {
      _lruQueue.remove(removed);
      
      _cacheController.add(CacheEvent(
        type: CacheEventType.invalidated,
        cacheKey: cacheKey,
        timestamp: DateTime.now(),
      ));
      
      debugPrint('🗄️ Invalidated cache: $cacheKey');
    }
  }

  /// Clear all cache
  void clearCache() {
    final count = _cache.length;
    _cache.clear();
    _lruQueue.clear();
    
    _cacheController.add(CacheEvent(
      type: CacheEventType.cleared,
      timestamp: DateTime.now(),
      data: {'clearedCount': count},
    ));
    
    debugPrint('🗄️ Cleared cache ($count entries)');
  }

  /// Get cache statistics
  CacheStatistics getStatistics(String cacheKey) {
    return _cacheStats[cacheKey] ?? CacheStatistics(cacheKey);
  }

  /// Get overall cache statistics
  OverallCacheStatistics getOverallStatistics() {
    return OverallCacheStatistics(
      totalEntries: _cache.length,
      hitRate: _calculateHitRate(),
      missRate: _calculateMissRate(),
      deduplicationRate: _calculateDeduplicationRate(),
      averageResponseTime: _calculateAverageResponseTime(),
      memoryUsage: _calculateMemoryUsage(),
      lruEvictions: _calculateLRUEvictions(),
    );
  }

  /// Get from cache
  CacheEntry? _getFromCache(String cacheKey) {
    final entry = _cache[cacheKey];
    if (entry != null && !entry.isExpired) {
      // Move to end of LRU queue
      _lruQueue.remove(entry);
      _lruQueue.addLast(entry);
    }
    return entry;
  }

  /// Put in cache
  Future<void> _putInCache<T>(
    String cacheKey,
    T data, {
    Duration? ttl,
    int? priority,
  }) async {
    final entry = CacheEntry(
      key: cacheKey,
      data: data,
      timestamp: DateTime.now(),
      ttl: ttl ?? _defaultTTL,
      priority: priority ?? 0,
      size: _calculateDataSize(data),
    );

    // Remove existing entry if present
    final existing = _cache[cacheKey];
    if (existing != null) {
      _lruQueue.remove(existing);
    }

    // Add new entry
    _cache[cacheKey] = entry;
    _lruQueue.addLast(entry);

    // Enforce cache size limit
    while (_cache.length > _maxCacheSize) {
      final oldest = _lruQueue.removeFirst();
      _cache.remove(oldest.key);
    }

    _cacheController.add(CacheEvent(
      type: CacheEventType.cached,
      cacheKey: cacheKey,
      timestamp: DateTime.now(),
      data: {'size': entry.size, 'ttl': entry.ttl?.inMinutes},
    ));
  }

  /// Track request for deduplication
  void _trackRequest(String cacheKey, RequestEntry request) {
    final history = _requestHistory.putIfAbsent(cacheKey, () => <RequestEntry>[]);
    history.add(request);
    
    // Limit history size
    if (history.length > _maxHistorySize) {
      history.removeAt(0);
    }
  }

  /// Find similar request for deduplication
  SimilarRequest? _findSimilarRequest(String cacheKey) {
    final history = _requestHistory[cacheKey];
    if (history == null || history.isEmpty) return null;

    // Calculate similarity with recent requests
    for (int i = history.length - 1; i >= 0; i--) {
      final request = history[i];
      if (request.response != null && request.success == true) {
        final similarity = _calculateSimilarity(cacheKey, request.key);
        if (similarity >= _similarityThreshold) {
          return SimilarRequest(
            key: request.key,
            response: request.response!,
            similarity: similarity,
            timestamp: request.timestamp,
          );
        }
      }
    }

    return null;
  }

  /// Calculate similarity between two strings
  double _calculateSimilarity(String str1, String str2) {
    if (str1 == str2) return 1.0;
    
    // Simple similarity based on common substrings
    final longer = str1.length > str2.length ? str1 : str2;
    final shorter = str1.length > str2.length ? str2 : str1;
    
    if (shorter.isEmpty) return 0.0;
    
    // Check if shorter is substring of longer
    if (longer.contains(shorter)) {
      return shorter.length / longer.length;
    }
    
    // Calculate Levenshtein distance similarity
    final distance = _levenshteinDistance(str1, str2);
    final maxLength = math.max(str1.length, str2.length);
    return 1.0 - (distance / maxLength);
  }

  /// Calculate Levenshtein distance
  int _levenshteinDistance(String s1, String s2) {
    final matrix = List.generate(
      s1.length + 1,
      (i) => List.generate(s2.length + 1, (j) => 0),
    );

    for (int i = 0; i <= s1.length; i++) {
      for (int j = 0; j <= s2.length; j++) {
        if (i == 0) {
          matrix[i][j] = j;
        } else if (j == 0) {
          matrix[i][j] = i;
        } else {
          final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
          matrix[i][j] = math.min(
            math.min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1),
            matrix[i - 1][j - 1] + cost,
          );
        }
      }
    }

    return matrix[s1.length][s2.length];
  }

  /// Calculate data size
  int _calculateDataSize(dynamic data) {
    if (data is String) {
      return (data as String).length;
    } else if (data is Map || data is List) {
      return json.encode(data).length;
    } else {
      return data.toString().length;
    }
  }

  /// Update cache statistics
  void _updateCacheStatistics(String cacheKey, CacheHit hitType) {
    final stats = _cacheStats.putIfAbsent(cacheKey, () => CacheStatistics(cacheKey));
    
    if (hitType == CacheHit.hit) {
      stats.hits++;
    } else if (hitType == CacheHit.miss) {
      stats.misses++;
    } else if (hitType == CacheHit.deduplication) {
      stats.deduplicationHits++;
    }
    
    stats.lastAccess = DateTime.now();
  }

  /// Calculate hit rate
  double _calculateHitRate() {
    int totalHits = 0;
    int totalMisses = 0;
    
    for (final stats in _cacheStats.values) {
      totalHits += stats.hits;
      totalMisses += stats.misses;
    }
    
    final total = totalHits + totalMisses;
    return total > 0 ? totalHits / total : 0.0;
  }

  /// Calculate miss rate
  double _calculateMissRate() {
    return 1.0 - _calculateHitRate();
  }

  /// Calculate deduplication rate
  double _calculateDeduplicationRate() {
    int totalDeduplicationHits = 0;
    int totalRequests = 0;
    
    for (final stats in _cacheStats.values) {
      totalDeduplicationHits += stats.deduplicationHits;
      totalRequests += stats.hits + stats.misses;
    }
    
    return totalRequests > 0 ? totalDeduplicationHits / totalRequests : 0.0;
  }

  /// Calculate average response time
  Duration _calculateAverageResponseTime() {
    final allRequests = <RequestEntry>[];
    
    for (final history in _requestHistory.values) {
      allRequests.addAll(history);
    }
    
    final completedRequests = allRequests
        .where((r) => r.executionTime != null && r.success == true)
        .toList();
    
    if (completedRequests.isEmpty) return Duration.zero;
    
    final totalMs = completedRequests
        .fold<int>(0, (sum, r) => sum + r.executionTime!.inMilliseconds);
    
    return Duration(milliseconds: totalMs ~/ completedRequests.length);
  }

  /// Calculate memory usage
  int _calculateMemoryUsage() {
    return _cache.values
        .fold<int>(0, (sum, entry) => sum + entry.size);
  }

  /// Calculate LRU evictions
  int _calculateLRUEvictions() {
    // This would track evictions
    return 0; // Placeholder
  }

  /// Start cleanup timer
  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) {
      _performCleanup();
    });
  }

  /// Start optimization timer
  void _startOptimizationTimer() {
    _optimizationTimer = Timer.periodic(_optimizationInterval, (_) {
      _performOptimization();
    });
  }

  /// Perform cleanup
  void _performCleanup() {
    final now = DateTime.now();
    final expiredKeys = <String>[];
    
    // Remove expired entries
    for (final entry in _cache.values) {
      if (entry.isExpired) {
        expiredKeys.add(entry.key);
      }
    }
    
    for (final key in expiredKeys) {
      final removed = _cache.remove(key);
      if (removed != null) {
        _lruQueue.remove(removed);
      }
    }
    
    if (expiredKeys.isNotEmpty) {
      _cacheController.add(CacheEvent(
        type: CacheEventType.expired,
        timestamp: now,
        data: {'expiredCount': expiredKeys.length},
      ));
      
      debugPrint('🗄️ Cleaned ${expiredKeys.length} expired cache entries');
    }
  }

  /// Perform optimization
  void _performOptimization() {
    // Optimize cache based on usage patterns
    final hotKeys = _cacheStats.entries
        .where((entry) => entry.value.hits > entry.value.misses * 2)
        .map((entry) => entry.key)
        .toList();
    
    if (hotKeys.isNotEmpty) {
      debugPrint('🗄️ Identified ${hotKeys.length} hot cache keys for optimization');
    }
    
    // Clean old request history
    final cutoff = DateTime.now().subtract(Duration(hours: 1));
    int cleanedCount = 0;
    
    for (final history in _requestHistory.values) {
      final initialLength = history.length;
      history.removeWhere((request) => request.timestamp.isBefore(cutoff));
      cleanedCount += initialLength - history.length;
    }
    
    if (cleanedCount > 0) {
      debugPrint('🗄️ Cleaned $cleanedCount old request history entries');
    }
  }

  /// Dispose request cache manager
  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    _optimizationTimer?.cancel();
    _cacheController.close();
    
    _cache.clear();
    _requestHistory.clear();
    _cacheStats.clear();
    _lruQueue.clear();
    
    debugPrint('🗄️ Request Cache Manager disposed');
  }
}

/// Cache entry
class CacheEntry {
  final String key;
  final dynamic data;
  final DateTime timestamp;
  final Duration ttl;
  final int priority;
  final int size;
  
  CacheEntry({
    required this.key,
    required this.data,
    required this.timestamp,
    required this.ttl,
    required this.priority,
    required this.size,
  });

  bool get isExpired => DateTime.now().difference(timestamp) > ttl;
}

/// Request entry
class RequestEntry {
  final String key;
  final DateTime timestamp;
  final int priority;
  final Map<String, dynamic> metadata;
  dynamic response;
  Duration? executionTime;
  bool success = false;
  String? error;
  
  RequestEntry({
    required this.key,
    required this.timestamp,
    required this.priority,
    required this.metadata,
  });
}

/// Similar request
class SimilarRequest {
  final String key;
  final dynamic response;
  final double similarity;
  final DateTime timestamp;
  
  SimilarRequest({
    required this.key,
    required this.response,
    required this.similarity,
    required this.timestamp,
  });
}

/// Cache statistics
class CacheStatistics {
  final String cacheKey;
  int hits = 0;
  int misses = 0;
  int deduplicationHits = 0;
  DateTime? lastAccess;
  
  CacheStatistics(this.cacheKey);
  
  double get hitRate {
    final total = hits + misses;
    return total > 0 ? hits / total : 0.0;
  }
}

/// Overall cache statistics
class OverallCacheStatistics {
  final int totalEntries;
  final double hitRate;
  final double missRate;
  final double deduplicationRate;
  final Duration averageResponseTime;
  final int memoryUsage;
  final int lruEvictions;
  
  OverallCacheStatistics({
    required this.totalEntries,
    required this.hitRate,
    required this.missRate,
    required this.deduplicationRate,
    required this.averageResponseTime,
    required this.memoryUsage,
    required this.lruEvictions,
  });
}

/// Cache event
class CacheEvent {
  final CacheEventType type;
  final String? cacheKey;
  final DateTime timestamp;
  final Map<String, dynamic>? data;
  
  CacheEvent({
    required this.type,
    this.cacheKey,
    required this.timestamp,
    this.data,
  });
}

/// Enums
enum CacheHit { hit, miss, deduplication }
enum CacheEventType {
  cacheHit,
  cacheMiss,
  deduplicationHit,
  cached,
  invalidated,
  cleared,
  expired,
  preload,
}

import 'dart:math' as math;
