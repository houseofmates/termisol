import 'dart:async';
import 'dart:developer' as developer;
import 'dart:collection';
import 'dart:io';
import 'dart:convert';

class IntelligentCaching {
  static const int _maxCacheSize = 1024 * 1024 * 1024; // 1GB
  static const int _maxEntries = 10000;
  static const int _cleanupInterval = 300000; // 5 minutes
  static const int _accessTrackingSize = 1000;
  
  final Map<String, CacheEntry> _cache = {};
  final Map<String, List<CacheEntry>> _versionedCache = {};
  final Map<String, AccessPattern> _accessPatterns = {};
  final Queue<CacheEntry> _lruQueue = Queue();
  final Map<String, CacheStats> _cacheStats = {};
  
  Timer? _cleanupTimer;
  Timer? _optimizationTimer;
  int _totalHits = 0;
  int _totalMisses = 0;
  int _totalEvictions = 0;
  int _currentCacheSize = 0;
  
  final StreamController<CacheEvent> _cacheController = 
      StreamController<CacheEvent>.broadcast();

  void initialize() {
    _startCleanupTimer();
    _startOptimizationTimer();
    developer.log('🧠 Intelligent Caching initialized');
  }

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(
      Duration(milliseconds: _cleanupInterval),
      (_) => _performCleanup(),
    );
  }

  void _startOptimizationTimer() {
    _optimizationTimer = Timer.periodic(
      Duration(minutes: 10),
      (_) => _optimizeCache(),
    );
  }

  Future<T?> get<T>(String key, {String? version}) async {
    final cacheKey = version != null ? '${key}_$version' : key;
    final entry = _cache[cacheKey];
    
    if (entry != null && !entry.isExpired()) {
      _totalHits++;
      _updateAccessPattern(key);
      _updateLRU(entry);
      
      developer.log('🧠 Cache hit: $key');
      
      _emitEvent(CacheEvent(
        type: CacheEventType.hit,
        key: key,
        version: version,
        size: entry.size,
      ));
      
      return entry.data as T?;
    }
    
    _totalMisses++;
    _trackMiss(key);
    
    developer.log('🧠 Cache miss: $key');
    
    _emitEvent(CacheEvent(
      type: CacheEventType.miss,
      key: key,
      version: version,
    ));
    
    return null;
  }

  Future<void> put<T>(
    String key,
    T data, {
    String? version,
    int? ttl,
    int? priority,
    CachePolicy policy = CachePolicy.lru,
    Map<String, dynamic>? metadata,
  }) async {
    final cacheKey = version != null ? '${key}_$version' : key;
    
    // Check if we need to evict entries
    final dataSize = _estimateDataSize(data);
    if (_currentCacheSize + dataSize > _maxCacheSize) {
      await _evictEntries(dataSize);
    }
    
    final entry = CacheEntry(
      key: cacheKey,
      data: data,
      size: dataSize,
      createdAt: DateTime.now(),
      lastAccessed: DateTime.now(),
      ttl: ttl ?? _getDefaultTTL(key),
      priority: priority ?? 0,
      policy: policy,
      metadata: metadata ?? {},
      version: version,
    );
    
    // Add to cache
    _cache[cacheKey] = entry;
    _currentCacheSize += dataSize;
    
    // Add to LRU queue if applicable
    if (policy == CachePolicy.lru) {
      _lruQueue.add(entry);
    }
    
    // Update versioned cache
    if (version != null) {
      _versionedCache.putIfAbsent(
        key,
        () => <CacheEntry>[],
      ).add(entry);
    }
    
    // Update cache stats
    _updateCacheStats(key, entry);
    
    developer.log('🧠 Cached: $key (${dataSize} bytes)');
    
    _emitEvent(CacheEvent(
      type: CacheEventType.added,
      key: key,
      version: version,
      size: dataSize,
      priority: priority,
    ));
  }

  Future<void> putBatch<T>(Map<String, T> entries, {
    CachePolicy policy = CachePolicy.lru,
    int? priority,
  }) async {
    final batchSize = entries.length;
    final totalSize = entries.values
        .map((data) => _estimateDataSize(data))
        .fold(0, (sum, size) => sum + size);
    
    // Check if we need to evict entries
    if (_currentCacheSize + totalSize > _maxCacheSize) {
      await _evictEntries(totalSize);
    }
    
    final addedEntries = <String>[];
    
    for (final entry in entries.entries) {
      final dataSize = _estimateDataSize(entry.value);
      final cacheEntry = CacheEntry(
        key: entry.key,
        data: entry.value,
        size: dataSize,
        createdAt: DateTime.now(),
        lastAccessed: DateTime.now(),
        ttl: _getDefaultTTL(entry.key),
        priority: priority ?? 0,
        policy: policy,
        metadata: {},
        version: null,
      );
      
      _cache[entry.key] = cacheEntry;
      _currentCacheSize += dataSize;
      addedEntries.add(entry.key);
      
      if (policy == CachePolicy.lru) {
        _lruQueue.add(cacheEntry);
      }
      
      _updateCacheStats(entry.key, cacheEntry);
    }
    
    developer.log('🧠 Batch cached: ${addedEntries.length} entries (${totalSize} bytes)');
    
    _emitEvent(CacheEvent(
      type: CacheEventType.batchAdded,
      keys: addedEntries,
      size: totalSize,
    ));
  }

  Future<void> invalidate(String key, {String? version}) async {
    final cacheKey = version != null ? '${key}_$version' : key;
    final entry = _cache.remove(cacheKey);
    
    if (entry != null) {
      _currentCacheSize -= entry.size;
      _totalEvictions++;
      
      // Remove from LRU queue
      _lruQueue.remove(entry);
      
      // Remove from versioned cache
      if (version != null) {
        final versionedEntries = _versionedCache[key];
        if (versionedEntries != null) {
          versionedEntries.remove(entry);
          if (versionedEntries.isEmpty) {
            _versionedCache.remove(key);
          }
        }
      }
      
      developer.log('🧠 Invalidated: $key');
      
      _emitEvent(CacheEvent(
        type: CacheEventType.invalidated,
        key: key,
        version: version,
        size: entry.size,
      ));
    }
  }

  Future<void> invalidatePattern(String pattern) async {
    final regex = RegExp(pattern);
    final keysToRemove = <String>[];
    
    for (final key in _cache.keys.toList()) {
      if (regex.hasMatch(key)) {
        keysToRemove.add(key);
      }
    }
    
    for (final key in keysToRemove) {
      await invalidate(key);
    }
    
    developer.log('🧠 Invalidated pattern: $pattern (${keysToRemove.length} entries)');
  }

  Future<void> clear() async {
    final entryCount = _cache.length;
    final totalSize = _currentCacheSize;
    
    _cache.clear();
    _versionedCache.clear();
    _lruQueue.clear();
    _currentCacheSize = 0;
    _totalEvictions += entryCount;
    
    developer.log('🧠 Cleared cache: $entryCount entries (${totalSize} bytes)');
    
    _emitEvent(CacheEvent(
      type: CacheEventType.cleared,
      entryCount: entryCount,
      size: totalSize,
    ));
  }

  Future<void> _evictEntries(int requiredSpace) async {
    if (requiredSpace <= 0) return;
    
    final entriesToEvict = <CacheEntry>[];
    int freedSpace = 0;
    
    // Sort entries by eviction policy
    final sortedEntries = _cache.values.toList()
      ..sort((a, b) => _compareEvictionPriority(a, b));
    
    for (final entry in sortedEntries) {
      entriesToEvict.add(entry);
      freedSpace += entry.size;
      
      if (freedSpace >= requiredSpace) break;
    }
    
    // Evict entries
    for (final entry in entriesToEvict) {
      _cache.remove(entry.key);
      _lruQueue.remove(entry);
      _currentCacheSize -= entry.size;
      _totalEvictions++;
    }
    
    developer.log('🧠 Evicted ${entriesToEvict.length} entries (${freedSpace} bytes)');
    
    _emitEvent(CacheEvent(
      type: CacheEventType.evicted,
      entryCount: entriesToEvict.length,
      size: freedSpace,
    ));
  }

  int _compareEvictionPriority(CacheEntry a, CacheEntry b) {
    // Higher priority = lower eviction priority
    if (a.priority != b.priority) {
      return b.priority.compareTo(a.priority);
    }
    
    // Lower access frequency = higher eviction priority
    final patternA = _accessPatterns[a.key];
    final patternB = _accessPatterns[b.key];
    
    final frequencyA = patternA?.frequency ?? 0;
    final frequencyB = patternB?.frequency ?? 0;
    
    if (frequencyA != frequencyB) {
      return frequencyA.compareTo(frequencyB);
    }
    
    // Older entries = higher eviction priority
    return a.lastAccessed.compareTo(b.lastAccessed);
  }

  void _updateAccessPattern(String key) {
    final pattern = _accessPatterns.putIfAbsent(
      key,
      () => AccessPattern(key: key),
    );
    
    pattern.recordAccess();
    
    // Keep only recent patterns
    if (_accessPatterns.length > _accessTrackingSize) {
      final oldestKey = _accessPatterns.keys.first;
      _accessPatterns.remove(oldestKey);
    }
  }

  void _trackMiss(String key) {
    final pattern = _accessPatterns.putIfAbsent(
      key,
      () => AccessPattern(key: key),
    );
    
    pattern.recordMiss();
  }

  void _updateLRU(CacheEntry entry) {
    // Move to end of LRU queue
    _lruQueue.remove(entry);
    _lruQueue.add(entry);
  }

  void _updateCacheStats(String key, CacheEntry entry) {
    final stats = _cacheStats.putIfAbsent(
      key,
      () => CacheStats(key: key),
    );
    
    stats.recordAccess(entry.size);
  }

  int _getDefaultTTL(String key) {
    // Default TTL based on key type
    if (key.startsWith('file_')) {
      return 3600000; // 1 hour
    } else if (key.startsWith('command_')) {
      return 1800000; // 30 minutes
    } else if (key.startsWith('texture_')) {
      return 7200000; // 2 hours
    } else {
      return 900000; // 15 minutes
    }
  }

  int _estimateDataSize(dynamic data) {
    if (data is String) {
      return (data as String).length * 2; // UTF-16
    } else if (data is List<int>) {
      return (data as List<int>).length;
    } else if (data is Map) {
      return jsonEncode(data).length;
    } else {
      return 1024; // Default 1KB
    }
  }

  Future<void> _performCleanup() async {
    final now = DateTime.now();
    final entriesToRemove = <String>[];
    
    for (final entry in _cache.entries) {
      final cacheEntry = entry.value;
      
      // Remove expired entries
      if (cacheEntry.isExpired()) {
        entriesToRemove.add(entry.key);
        continue;
      }
      
      // Remove old entries (older than 1 hour)
      if (now.difference(cacheEntry.lastAccessed).inHours > 1) {
        entriesToRemove.add(entry.key);
        continue;
      }
      
      // Remove entries with low access frequency
      final pattern = _accessPatterns[entry.key];
      if (pattern != null && pattern.frequency < 2) {
        entriesToRemove.add(entry.key);
      }
    }
    
    // Remove entries
    for (final key in entriesToRemove) {
      final entry = _cache.remove(key);
      if (entry != null) {
        _currentCacheSize -= entry.size;
        _totalEvictions++;
        
        _lruQueue.remove(entry);
        
        // Remove from versioned cache
        for (final versionedEntries in _versionedCache.values) {
          versionedEntries.remove(entry);
        }
      }
      }
    }
    
    if (entriesToRemove.isNotEmpty) {
      developer.log('🧠 Cleaned up ${entriesToRemove.length} expired/old entries');
      
      _emitEvent(CacheEvent(
        type: CacheEventType.cleanup,
        entryCount: entriesToRemove.length,
      ));
    }
  }

  Future<void> _optimizeCache() async {
    // Analyze access patterns and optimize cache
    final patterns = _accessPatterns.values.toList();
    patterns.sort((a, b) => b.frequency.compareTo(a.frequency));
    
    // Preload frequently accessed items
    final topPatterns = patterns.take(10);
    
    for (final pattern in topPatterns) {
      if (pattern.frequency > 5 && pattern.missRate < 0.2) {
        // This is a high-value pattern, consider preloading
        developer.log('🧠 High-value pattern detected: ${pattern.key} (freq: ${pattern.frequency}, miss rate: ${pattern.missRate})');
      }
    }
    
    // Optimize LRU queue size
    if (_lruQueue.length > _maxEntries) {
      final excess = _lruQueue.length - _maxEntries;
      for (int i = 0; i < excess; i++) {
        final entry = _lruQueue.removeFirst();
        if (entry != null) {
          _cache.remove(entry.key);
          _currentCacheSize -= entry.size;
          _totalEvictions++;
        }
      }
    }
    
    _emitEvent(CacheEvent(
      type: CacheEventType.optimized,
      patternsAnalyzed: patterns.length,
      topPatterns: topPatterns.length,
    ));
  }

  Future<Map<String, dynamic>> getCacheInfo() async {
    final info = <String, dynamic>{};
    
    info['totalEntries'] = _cache.length;
    info['totalSize'] = _currentCacheSize;
    info['maxSize'] = _maxCacheSize;
    info['hitRate'] = _totalHits + _totalMisses > 0 
        ? _totalHits / (_totalHits + _totalMisses) 
        : 0.0;
    info['totalHits'] = _totalHits;
    info['totalMisses'] = _totalMisses;
    info['totalEvictions'] = _totalEvictions;
    info['lruQueueSize'] = _lruQueue.length;
    info['versionedCacheSize'] = _versionedCache.values
        .fold(0, (sum, entries) => sum + entries.length);
    
    // Top accessed keys
    final topKeys = _accessPatterns.values.toList()
      ..sort((a, b) => b.frequency.compareTo(a.frequency))
      .take(10)
      .map((p) => p.key)
      .toList();
    
    info['topKeys'] = topKeys;
    
    return info;
  }

  Future<List<String>> getKeysByPattern(String pattern) async {
    final regex = RegExp(pattern);
    final matchingKeys = <String>[];
    
    for (final key in _cache.keys) {
      if (regex.hasMatch(key)) {
        matchingKeys.add(key);
      }
    }
    
    return matchingKeys;
  }

  Future<Map<String, CacheEntry>> getEntriesByPolicy(CachePolicy policy) async {
    final entries = <String, CacheEntry>{};
    
    for (final entry in _cache.entries) {
      if (entry.value.policy == policy) {
        entries[entry.key] = entry.value;
      }
    }
    
    return entries;
  }

  Future<void> warmup(List<String> keys) async {
    // Preload commonly accessed keys
    for (final key in keys) {
      final entry = _cache[key];
      if (entry == null) {
        // Simulate loading from source
        await Future.delayed(Duration(milliseconds: 50));
        
        developer.log('🧠 Warmed up cache key: $key');
      }
    }
  }

  void _emitEvent(CacheEvent event) {
    _cacheController.add(event);
  }

  Stream<CacheEvent> get cacheEventStream => _cacheController.stream;

  CacheStats getStats() {
    return CacheStats(
      totalHits: _totalHits,
      totalMisses: _totalMisses,
      hitRate: _totalHits + _totalMisses > 0 
          ? _totalHits / (_totalHits + _totalMisses) 
          : 0.0,
      totalEvictions: _totalEvictions,
      currentSize: _currentCacheSize,
      maxSize: _maxCacheSize,
      entryCount: _cache.length,
      lruQueueSize: _lruQueue.length,
    );
  }

  void dispose() {
    _cleanupTimer?.cancel();
    _optimizationTimer?.cancel();
    
    clear();
    _cacheController.close();
    
    developer.log('🧠 Intelligent Caching disposed');
  }
}

class CacheEntry {
  final String key;
  final dynamic data;
  final int size;
  final DateTime createdAt;
  final DateTime lastAccessed;
  final int ttl;
  final int priority;
  final CachePolicy policy;
  final Map<String, dynamic> metadata;
  final String? version;

  CacheEntry({
    required this.key,
    required this.data,
    required this.size,
    required this.createdAt,
    required this.lastAccessed,
    required this.ttl,
    required this.priority,
    required this.policy,
    required this.metadata,
    this.version,
  });

  bool isExpired() {
    return DateTime.now().difference(createdAt).inMilliseconds > ttl;
  }
}

class AccessPattern {
  final String key;
  int frequency = 0;
  int misses = 0;
  DateTime lastAccess = DateTime.now();

  AccessPattern({required this.key});

  void recordAccess() {
    frequency++;
    lastAccess = DateTime.now();
  }

  void recordMiss() {
    misses++;
  }

  double get missRate {
    return frequency + misses > 0 ? misses / (frequency + misses) : 0.0;
  }
}

class CacheStats {
  final String key;
  int totalAccesses = 0;
  int totalSize = 0;
  int minSize = 0;
  int maxSize = 0;
  DateTime lastAccess = DateTime.now();

  CacheStats({required this.key});

  void recordAccess(int size) {
    totalAccesses++;
    totalSize += size;
    lastAccess = DateTime.now();
    
    if (minSize == 0 || size < minSize) {
      minSize = size;
    }
    
    if (size > maxSize) {
      maxSize = size;
    }
  }

  double get averageSize {
    return totalAccesses > 0 ? totalSize / totalAccesses : 0.0;
  }
}

enum CachePolicy {
  lru,
  lfu, // Least Frequently Used
  fifo,
  priority,
}

enum CacheEventType {
  hit,
  miss,
  added,
  batchAdded,
  invalidated,
  evicted,
  cleared,
  cleanup,
  optimized,
}

class CacheEvent {
  final CacheEventType type;
  final String? key;
  final String? version;
  final List<String>? keys;
  final int? size;
  final int? priority;
  final int? entryCount;
  final int? patternsAnalyzed;
  final int? topPatterns;

  CacheEvent({
    required this.type,
    this.key,
    this.version,
    this.keys,
    this.size,
    this.priority,
    this.entryCount,
    this.patternsAnalyzed,
    this.topPatterns,
  });
}
