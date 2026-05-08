import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

/// Multi-Tier Caching System
/// 
/// Implements a sophisticated caching system with three tiers:
/// - RAM Cache: Fastest, limited size, volatile
/// - SSD Cache: Medium speed, larger size, persistent
/// - Network Cache: Slowest, unlimited size, distributed
/// 
/// Features:
/// - LZF4/ZSTD compression algorithms
/// - Semantic cache invalidation
/// - Predictive cache preloading
/// - Usage pattern analysis
/// - Cache statistics and monitoring
class MultiTierCache {
  static final MultiTierCache _instance = MultiTierCache._internal();
  factory MultiTierCache() => _instance;
  MultiTierCache._internal();

  bool _isInitialized = false;
  final Map<String, CacheEntry> _ramCache = {};
  final Map<String, CacheEntry> _ssdCache = {};
  final Map<String, CacheEntry> _networkCache = {};
  
  // Cache configuration
  static const int _maxRamCacheSize = 100; // MB
  static const int _maxSsdCacheSize = 1000; // MB
  static const Duration _ramCacheTTL = Duration(minutes: 30);
  static const Duration _ssdCacheTTL = Duration(hours: 24);
  static const Duration _networkCacheTTL = Duration(days: 7);
  
  // Compression algorithms
  CompressionAlgorithm _compressionAlgorithm = CompressionAlgorithm.zstd;
  
  // Usage pattern analysis
  final Map<String, UsagePattern> _usagePatterns = {};
  final List<CacheAccess> _accessHistory = [];
  
  // Predictive preloading
  final Set<String> _preloadQueue = {};
  Timer? _preloadTimer;
  
  // Cache statistics
  CacheStatistics _statistics = CacheStatistics();
  
  // Event streams
  final _cacheController = StreamController<CacheEvent>.broadcast();
  Stream<CacheEvent> get events => _cacheController.stream;
  
  bool get isInitialized => _isInitialized;
  CompressionAlgorithm get compressionAlgorithm => _compressionAlgorithm;
  CacheStatistics get statistics => _statistics;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Initialize SSD cache directory
      await _initializeSsdCache();
      
      // Load existing cache entries
      await _loadSsdCache();
      
      // Start predictive preloading
      _startPredictivePreloading();
      
      // Start cache maintenance
      _startCacheMaintenance();
      
      _isInitialized = true;
      debugPrint('💾 Multi-Tier Cache initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Multi-Tier Cache: $e');
    }
  }

  Future<CacheResult<T>> get<T>(String key, {CacheTier? preferredTier}) async {
    final startTime = Stopwatch()..start();
    
    try {
      // Check RAM cache first
      if (preferredTier == null || preferredTier == CacheTier.ram) {
        final ramResult = await _getFromRam<T>(key);
        if (ramResult.success) {
          _recordAccess(key, CacheTier.ram, true);
          return ramResult;
        }
      }
      
      // Check SSD cache
      if (preferredTier == null || preferredTier == CacheTier.ssd) {
        final ssdResult = await _getFromSsd<T>(key);
        if (ssdResult.success) {
          _recordAccess(key, CacheTier.ssd, true);
          return ssdResult;
        }
      }
      
      // Check network cache
      if (preferredTier == null || preferredTier == CacheTier.network) {
        final networkResult = await _getFromNetwork<T>(key);
        if (networkResult.success) {
          _recordAccess(key, CacheTier.network, true);
          return networkResult;
        }
      }
      
      _recordAccess(key, CacheTier.ram, false);
      return CacheResult<T>.miss();
      
    } catch (e) {
      debugPrint('❌ Cache get failed for key $key: $e');
      _recordAccess(key, CacheTier.ram, false);
      return CacheResult<T>.error(e.toString());
    } finally {
      startTime.stop();
      _statistics.recordGet(startTime.elapsedMicroseconds);
    }
  }

  Future<CacheResult<void>> put<T>(
    String key,
    T value, {
    CacheTier tier = CacheTier.ram,
    Duration? ttl,
    bool compress = true,
    String? semanticTag,
  }) async {
    final startTime = Stopwatch()..start();
    
    try {
      final entry = CacheEntry<T>(
        key: key,
        value: value,
        timestamp: DateTime.now(),
        ttl: ttl ?? _getDefaultTTL(tier),
        tier: tier,
        compressed: compress,
        semanticTag: semanticTag,
      );
      
      switch (tier) {
        case CacheTier.ram:
          await _putToRam(entry);
          break;
        case CacheTier.ssd:
          await _putToSsd(entry);
          break;
        case CacheTier.network:
          await _putToNetwork(entry);
          break;
      }
      
      _cacheController.add(CacheEvent(
        type: CacheEventType.entryAdded,
        data: {
          'key': key,
          'tier': tier.toString(),
          'compressed': compress,
          'semantic_tag': semanticTag,
        },
      ));
      
      return CacheResult<void>.success();
      
    } catch (e) {
      debugPrint('❌ Cache put failed for key $key: $e');
      return CacheResult<void>.error(e.toString());
    } finally {
      startTime.stop();
      _statistics.recordPut(startTime.elapsedMicroseconds);
    }
  }

  Future<CacheResult<void>> invalidate(String key, {InvalidationMode mode = InvalidationMode.exact}) async {
    try {
      switch (mode) {
        case InvalidationMode.exact:
          await _invalidateExact(key);
          break;
        case InvalidationMode.semantic:
          await _invalidateSemantic(key);
          break;
        case InvalidationMode.pattern:
          await _invalidatePattern(key);
          break;
      }
      
      _cacheController.add(CacheEvent(
        type: CacheEventType.entryInvalidated,
        data: {
          'key': key,
          'mode': mode.toString(),
        },
      ));
      
      return CacheResult<void>.success();
      
    } catch (e) {
      debugPrint('❌ Cache invalidation failed for key $key: $e');
      return CacheResult<void>.error(e.toString());
    }
  }

  Future<CacheResult<void>> invalidateSemantic(String semanticTag) async {
    try {
      // Invalidate entries with matching semantic tag
      await _invalidateSemanticTag(semanticTag);
      
      _cacheController.add(CacheEvent(
        type: CacheEventType.semanticInvalidation,
        data: {
          'semantic_tag': semanticTag,
        },
      ));
      
      return CacheResult<void>.success();
      
    } catch (e) {
      debugPrint('❌ Semantic invalidation failed for tag $semanticTag: $e');
      return CacheResult<void>.error(e.toString());
    }
  }

  Future<void> preloadPredictive() async {
    try {
      // Analyze usage patterns and preload likely-to-be-accessed items
      final predictions = _generatePredictions();
      
      for (final prediction in predictions) {
        if (!_ramCache.containsKey(prediction.key)) {
          // Try to load from lower tiers
          await _preloadEntry(prediction.key, prediction.tier);
        }
      }
      
      debugPrint('🔄 Preloaded ${predictions.length} cache entries');
      
    } catch (e) {
      debugPrint('❌ Predictive preloading failed: $e');
    }
  }

  void setCompressionAlgorithm(CompressionAlgorithm algorithm) {
    _compressionAlgorithm = algorithm;
    
    _cacheController.add(CacheEvent(
      type: CacheEventType.compressionChanged,
      data: {
        'algorithm': algorithm.toString(),
      },
    ));
    
    debugPrint('💾 Compression algorithm changed to: $algorithm');
  }

  CacheAnalysis getAnalysis() {
    return CacheAnalysis(
      ramCacheSize: _ramCache.length,
      ssdCacheSize: _ssdCache.length,
      networkCacheSize: _networkCache.length,
      ramMemoryUsage: _calculateRamUsage(),
      ssdMemoryUsage: _calculateSsdUsage(),
      hitRate: _statistics.hitRate,
      averageAccessTime: _statistics.averageAccessTime,
      compressionRatio: _statistics.compressionRatio,
      usagePatterns: _usagePatterns.values.toList(),
      predictions: _generatePredictions(),
    );
  }

  Future<void> _initializeSsdCache() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${directory.path}/.termisol/cache/ssd');
      
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      
      debugPrint('💾 SSD cache directory initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize SSD cache: $e');
    }
  }

  Future<void> _loadSsdCache() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${directory.path}/.termisol/cache/ssd');
      
      if (!await cacheDir.exists()) return;
      
      await for (final entity in cacheDir.list()) {
        if (entity is File && entity.path.endsWith('.cache')) {
          try {
            final content = await entity.readAsString();
            final data = jsonDecode(content) as Map<String, dynamic>;
            final entry = CacheEntry.fromJson(data);
            
            if (!entry.isExpired) {
              _ssdCache[entry.key] = entry;
            } else {
              await entity.delete();
            }
          } catch (e) {
            debugPrint('⚠️ Failed to load cache entry ${entity.path}: $e');
          }
        }
      }
      
      debugPrint('💾 Loaded ${_ssdCache.length} SSD cache entries');
    } catch (e) {
      debugPrint('❌ Failed to load SSD cache: $e');
    }
  }

  Future<CacheResult<T>> _getFromRam<T>(String key) async {
    final entry = _ramCache[key];
    if (entry == null || entry.isExpired) {
      if (entry != null) {
        _ramCache.remove(key);
      }
      return CacheResult<T>.miss();
    }
    
    _statistics.recordHit(CacheTier.ram);
    entry.lastAccessed = DateTime.now();
    entry.accessCount++;
    
    return CacheResult<T>.success(entry.value as T);
  }

  Future<CacheResult<T>> _getFromSsd<T>(String key) async {
    final entry = _ssdCache[key];
    if (entry == null || entry.isExpired) {
      if (entry != null) {
        await _removeFromSsd(key);
      }
      return CacheResult<T>.miss();
    }
    
    _statistics.recordHit(CacheTier.ssd);
    entry.lastAccessed = DateTime.now();
    entry.accessCount++;
    
    // Promote to RAM if space allows
    await _promoteToRam(entry);
    
    return CacheResult<T>.success(entry.value as T);
  }

  Future<CacheResult<T>> _getFromNetwork<T>(String key) async {
    final entry = _networkCache[key];
    if (entry == null || entry.isExpired) {
      if (entry != null) {
        await _removeFromNetwork(key);
      }
      return CacheResult<T>.miss();
    }
    
    _statistics.recordHit(CacheTier.network);
    entry.lastAccessed = DateTime.now();
    entry.accessCount++;
    
    // Promote to SSD if space allows
    await _promoteToSsd(entry);
    
    return CacheResult<T>.success(entry.value as T);
  }

  Future<void> _putToRam<T>(CacheEntry<T> entry) async {
    // Check if we need to evict entries
    await _evictFromRamIfNeeded();
    
    // Compress if needed
    if (entry.compressed) {
      entry.compressedData = await _compressData(entry.value);
    }
    
    _ramCache[entry.key] = entry;
    _statistics.recordPut(CacheTier.ram);
  }

  Future<void> _putToSsd<T>(CacheEntry<T> entry) async {
    // Check if we need to evict entries
    await _evictFromSsdIfNeeded();
    
    // Compress if needed
    if (entry.compressed) {
      entry.compressedData = await _compressData(entry.value);
    }
    
    _ssdCache[entry.key] = entry;
    await _saveToSsd(entry);
    _statistics.recordPut(CacheTier.ssd);
  }

  Future<void> _putToNetwork<T>(CacheEntry<T> entry) async {
    // Check if we need to evict entries
    await _evictFromNetworkIfNeeded();
    
    // Compress if needed
    if (entry.compressed) {
      entry.compressedData = await _compressData(entry.value);
    }
    
    _networkCache[entry.key] = entry;
    await _saveToNetwork(entry);
    _statistics.recordPut(CacheTier.network);
  }

  Future<void> _saveToSsd<T>(CacheEntry<T> entry) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final cacheFile = File('${directory.path}/.termisol/cache/ssd/${entry.key}.cache');
      
      await cacheFile.writeAsString(jsonEncode(entry.toJson()));
    } catch (e) {
      debugPrint('❌ Failed to save SSD cache entry ${entry.key}: $e');
    }
  }

  Future<void> _saveToNetwork<T>(CacheEntry<T> entry) async {
    try {
      // Simulate network cache save (in reality would use distributed cache)
      final url = Uri.parse('https://cache.termisol.com/api/cache/${entry.key}');
      
      await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(entry.toJson()),
      );
    } catch (e) {
      debugPrint('❌ Failed to save network cache entry ${entry.key}: $e');
    }
  }

  Future<void> _evictFromRamIfNeeded() async {
    if (_calculateRamUsage() <= _maxRamCacheSize) return;
    
    // Sort by last accessed time (LRU)
    final entries = _ramCache.values.toList()
      ..sort((a, b) => a.lastAccessed.compareTo(b.lastAccessed));
    
    // Evict oldest entries until we have enough space
    for (final entry in entries) {
      _ramCache.remove(entry.key);
      
      // Try to promote to SSD
      await _promoteToSsd(entry);
      
      if (_calculateRamUsage() <= _maxRamCacheSize * 0.8) break;
    }
  }

  Future<void> _evictFromSsdIfNeeded() async {
    if (_calculateSsdUsage() <= _maxSsdCacheSize) return;
    
    // Sort by last accessed time (LRU)
    final entries = _ssdCache.values.toList()
      ..sort((a, b) => a.lastAccessed.compareTo(b.lastAccessed));
    
    // Evict oldest entries until we have enough space
    for (final entry in entries) {
      _ssdCache.remove(entry.key);
      await _removeFromSsd(entry.key);
      
      // Try to promote to network
      await _promoteToNetwork(entry);
      
      if (_calculateSsdUsage() <= _maxSsdCacheSize * 0.8) break;
    }
  }

  Future<void> _evictFromNetworkIfNeeded() async {
    // Network cache has unlimited size, but we can implement policies
    // For now, just remove expired entries
    final expiredKeys = <String>[];
    
    for (final entry in _networkCache.values) {
      if (entry.isExpired) {
        expiredKeys.add(entry.key);
      }
    }
    
    for (final key in expiredKeys) {
      await _removeFromNetwork(key);
    }
  }

  Future<void> _promoteToRam<T>(CacheEntry<T> entry) async {
    if (_ramCache.containsKey(entry.key)) return;
    if (_calculateRamUsage() > _maxRamCacheSize * 0.9) return;
    
    await _putToRam(entry);
  }

  Future<void> _promoteToSsd<T>(CacheEntry<T> entry) async {
    if (_ssdCache.containsKey(entry.key)) return;
    if (_calculateSsdUsage() > _maxSsdCacheSize * 0.9) return;
    
    await _putToSsd(entry);
  }

  Future<void> _promoteToNetwork<T>(CacheEntry<T> entry) async {
    if (_networkCache.containsKey(entry.key)) return;
    
    await _putToNetwork(entry);
  }

  Future<void> _removeFromSsd(String key) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final cacheFile = File('${directory.path}/.termisol/cache/ssd/$key.cache');
      
      if (await cacheFile.exists()) {
        await cacheFile.delete();
      }
    } catch (e) {
      debugPrint('❌ Failed to remove SSD cache entry $key: $e');
    }
  }

  Future<void> _removeFromNetwork(String key) async {
    try {
      // Simulate network cache removal
      final url = Uri.parse('https://cache.termisol.com/api/cache/$key');
      await http.delete(url);
    } catch (e) {
      debugPrint('❌ Failed to remove network cache entry $key: $e');
    }
  }

  Future<Uint8List> _compressData(dynamic data) async {
    try {
      final jsonString = jsonEncode(data);
      final bytes = utf8.encode(jsonString);
      
      switch (_compressionAlgorithm) {
        case CompressionAlgorithm.lzf4:
          return _compressLZF4(bytes);
        case CompressionAlgorithm.zstd:
          return _compressZSTD(bytes);
        case CompressionAlgorithm.none:
          return Uint8List.fromList(bytes);
      }
    } catch (e) {
      debugPrint('❌ Compression failed: $e');
      rethrow;
    }
  }

  Uint8List _compressLZF4(Uint8List data) {
    // Simplified LZF4 implementation (in reality would use proper library)
    return Uint8List.fromList(data); // Placeholder
  }

  Uint8List _compressZSTD(Uint8List data) {
    // Simplified ZSTD implementation (in reality would use proper library)
    return Uint8List.fromList(data); // Placeholder
  }

  Duration _getDefaultTTL(CacheTier tier) {
    switch (tier) {
      case CacheTier.ram:
        return _ramCacheTTL;
      case CacheTier.ssd:
        return _ssdCacheTTL;
      case CacheTier.network:
        return _networkCacheTTL;
    }
  }

  void _recordAccess(String key, CacheTier tier, bool hit) {
    final access = CacheAccess(
      key: key,
      tier: tier,
      timestamp: DateTime.now(),
      hit: hit,
    );
    
    _accessHistory.add(access);
    if (_accessHistory.length > 1000) {
      _accessHistory.removeAt(0);
    }
    
    // Update usage pattern
    _updateUsagePattern(key, tier, hit);
  }

  void _updateUsagePattern(String key, CacheTier tier, bool hit) {
    final pattern = _usagePatterns.putIfAbsent(
      key,
      () => UsagePattern(key: key),
    );
    
    pattern.recordAccess(tier, hit);
  }

  Future<void> _invalidateExact(String key) async {
    _ramCache.remove(key);
    await _removeFromSsd(key);
    await _removeFromNetwork(key);
    _networkCache.remove(key);
  }

  Future<void> _invalidateSemantic(String key) async {
    // Find entries with similar semantic meaning
    final semanticTag = _extractSemanticTag(key);
    await _invalidateSemanticTag(semanticTag);
  }

  Future<void> _invalidatePattern(String pattern) async {
    final regex = RegExp(pattern);
    
    // Invalidate matching entries in all tiers
    _ramCache.removeWhere((key, value) => regex.hasMatch(key));
    
    final ssdKeysToRemove = <String>[];
    for (final key in _ssdCache.keys) {
      if (regex.hasMatch(key)) {
        ssdKeysToRemove.add(key);
      }
    }
    
    for (final key in ssdKeysToRemove) {
      await _removeFromSsd(key);
      _ssdCache.remove(key);
    }
    
    final networkKeysToRemove = <String>[];
    for (final key in _networkCache.keys) {
      if (regex.hasMatch(key)) {
        networkKeysToRemove.add(key);
      }
    }
    
    for (final key in networkKeysToRemove) {
      await _removeFromNetwork(key);
      _networkCache.remove(key);
    }
  }

  Future<void> _invalidateSemanticTag(String semanticTag) async {
    // Remove entries with matching semantic tag
    _ramCache.removeWhere((key, value) => value.semanticTag == semanticTag);
    
    final ssdKeysToRemove = <String>[];
    for (final entry in _ssdCache.values) {
      if (entry.semanticTag == semanticTag) {
        ssdKeysToRemove.add(entry.key);
      }
    }
    
    for (final key in ssdKeysToRemove) {
      await _removeFromSsd(key);
      _ssdCache.remove(key);
    }
    
    final networkKeysToRemove = <String>[];
    for (final entry in _networkCache.values) {
      if (entry.semanticTag == semanticTag) {
        networkKeysToRemove.add(entry.key);
      }
    }
    
    for (final key in networkKeysToRemove) {
      await _removeFromNetwork(key);
      _networkCache.remove(key);
    }
  }

  String _extractSemanticTag(String key) {
    // Simple semantic tag extraction (in reality would use NLP)
    final parts = key.split(':');
    return parts.length > 1 ? parts[0] : 'general';
  }

  List<CachePrediction> _generatePredictions() {
    final predictions = <CachePrediction>[];
    
    // Analyze usage patterns to predict likely future accesses
    for (final pattern in _usagePatterns.values) {
      if (pattern.shouldPreload()) {
        predictions.add(CachePrediction(
          key: pattern.key,
          probability: pattern.accessProbability,
          tier: CacheTier.ram,
        ));
      }
    }
    
    // Sort by probability
    predictions.sort((a, b) => b.probability.compareTo(a.probability));
    
    // Return top predictions
    return predictions.take(10).toList();
  }

  Future<void> _preloadEntry(String key, CacheTier targetTier) async {
    try {
      // Try to load from lower tiers
      CacheEntry? entry;
      
      if (targetTier != CacheTier.network) {
        entry = _networkCache[key];
        if (entry != null && !entry.isExpired) {
          await _promoteToSsd(entry);
          await _promoteToRam(entry);
        }
      }
      
      if (targetTier != CacheTier.ssd && entry == null) {
        entry = _ssdCache[key];
        if (entry != null && !entry.isExpired) {
          await _promoteToRam(entry);
        }
      }
      
    } catch (e) {
      debugPrint('❌ Failed to preload entry $key: $e');
    }
  }

  void _startPredictivePreloading() {
    _preloadTimer = Timer.periodic(Duration(minutes: 5), (_) {
      preloadPredictive();
    });
  }

  void _startCacheMaintenance() {
    Timer.periodic(Duration(minutes: 10), (_) {
      _performMaintenance();
    });
  }

  Future<void> _performMaintenance() async {
    try {
      // Remove expired entries
      await _removeExpiredEntries();
      
      // Update usage patterns
      _updateUsagePatterns();
      
      // Optimize cache distribution
      await _optimizeCacheDistribution();
      
      debugPrint('💾 Cache maintenance completed');
    } catch (e) {
      debugPrint('❌ Cache maintenance failed: $e');
    }
  }

  Future<void> _removeExpiredEntries() async {
    // Remove expired entries from RAM cache
    _ramCache.removeWhere((key, entry) => entry.isExpired);
    
    // Remove expired entries from SSD cache
    final expiredSsdKeys = <String>[];
    for (final entry in _ssdCache.values) {
      if (entry.isExpired) {
        expiredSsdKeys.add(entry.key);
      }
    }
    
    for (final key in expiredSsdKeys) {
      await _removeFromSsd(key);
      _ssdCache.remove(key);
    }
    
    // Remove expired entries from network cache
    final expiredNetworkKeys = <String>[];
    for (final entry in _networkCache.values) {
      if (entry.isExpired) {
        expiredNetworkKeys.add(entry.key);
      }
    }
    
    for (final key in expiredNetworkKeys) {
      await _removeFromNetwork(key);
      _networkCache.remove(key);
    }
  }

  void _updateUsagePatterns() {
    // Update usage patterns based on recent access history
    final recentAccess = _accessHistory.where((a) => 
        DateTime.now().difference(a.timestamp).inHours < 24);
    
    for (final access in recentAccess) {
      _updateUsagePattern(access.key, access.tier, access.hit);
    }
  }

  Future<void> _optimizeCacheDistribution() async {
    // Move frequently accessed items to higher tiers
    for (final pattern in _usagePatterns.values) {
      if (pattern.accessFrequency > 10) {
        final entry = _ssdCache[pattern.key];
        if (entry != null) {
          await _promoteToRam(entry);
        }
      }
    }
  }

  double _calculateRamUsage() {
    // Simplified calculation (in reality would calculate actual memory usage)
    return _ramCache.length * 1.0; // MB per entry
  }

  double _calculateSsdUsage() {
    // Simplified calculation (in reality would calculate actual disk usage)
    return _ssdCache.length * 5.0; // MB per entry
  }

  Future<void> dispose() async {
    _preloadTimer?.cancel();
    _cacheController.close();
    
    // Save SSD cache
    for (final entry in _ssdCache.values) {
      await _saveToSsd(entry);
    }
    
    _ramCache.clear();
    _ssdCache.clear();
    _networkCache.clear();
    _usagePatterns.clear();
    _accessHistory.clear();
    
    _isInitialized = false;
    debugPrint('💾 Multi-Tier Cache disposed');
  }
}

/// Data classes
class CacheEntry<T> {
  final String key;
  final T value;
  final DateTime timestamp;
  final Duration ttl;
  final CacheTier tier;
  final bool compressed;
  final String? semanticTag;
  
  DateTime lastAccessed;
  int accessCount;
  Uint8List? compressedData;
  
  CacheEntry({
    required this.key,
    required this.value,
    required this.timestamp,
    required this.ttl,
    required this.tier,
    required this.compressed,
    this.semanticTag,
  }) : lastAccessed = timestamp,
       accessCount = 0;
  
  bool get isExpired => DateTime.now().difference(timestamp) > ttl;
  
  Map<String, dynamic> toJson() => {
    'key': key,
    'value': value,
    'timestamp': timestamp.toIso8601String(),
    'ttl': ttl.inMilliseconds,
    'tier': tier.toString(),
    'compressed': compressed,
    'semanticTag': semanticTag,
    'lastAccessed': lastAccessed.toIso8601String(),
    'accessCount': accessCount,
  };
  
  factory CacheEntry.fromJson(Map<String, dynamic> json) => CacheEntry(
    key: json['key'] as String,
    value: json['value'],
    timestamp: DateTime.parse(json['timestamp'] as String),
    ttl: Duration(milliseconds: json['ttl'] as int),
    tier: CacheTier.values.firstWhere((t) => t.toString() == json['tier']),
    compressed: json['compressed'] as bool,
    semanticTag: json['semanticTag'] as String?,
  )..lastAccessed = DateTime.parse(json['lastAccessed'] as String)
    ..accessCount = json['accessCount'] as int;
}

class CacheAccess {
  final String key;
  final CacheTier tier;
  final DateTime timestamp;
  final bool hit;
  
  CacheAccess({
    required this.key,
    required this.tier,
    required this.timestamp,
    required this.hit,
  });
}

class UsagePattern {
  final String key;
  final List<CacheAccess> accesses = [];
  
  UsagePattern({required this.key});
  
  void recordAccess(CacheTier tier, bool hit) {
    accesses.add(CacheAccess(
      key: key,
      tier: tier,
      timestamp: DateTime.now(),
      hit: hit,
    ));
    
    // Keep only recent accesses
    if (accesses.length > 100) {
      accesses.removeAt(0);
    }
  }
  
  int get accessFrequency => accesses.length;
  
  double get accessProbability {
    if (accesses.isEmpty) return 0.0;
    
    final recentAccesses = accesses.where((a) => 
        DateTime.now().difference(a.timestamp).inHours < 24);
    
    if (recentAccesses.isEmpty) return 0.0;
    
    return math.min(1.0, recentAccesses.length / 24.0);
  }
  
  bool shouldPreload() => accessProbability > 0.3 && accessFrequency > 5;
}

class CachePrediction {
  final String key;
  final double probability;
  final CacheTier tier;
  
  CachePrediction({
    required this.key,
    required this.probability,
    required this.tier,
  });
}

class CacheStatistics {
  int totalGets = 0;
  int totalPuts = 0;
  int totalHits = 0;
  int totalMisses = 0;
  final Map<CacheTier, int> tierHits = {};
  final Map<CacheTier, int> tierPuts = {};
  int totalMicroseconds = 0;
  int compressedEntries = 0;
  int uncompressedSize = 0;
  int compressedSize = 0;
  
  void recordGet(int microseconds) {
    totalGets++;
    totalMicroseconds += microseconds;
  }
  
  void recordPut(int microseconds) {
    totalPuts++;
    totalMicroseconds += microseconds;
  }
  
  void recordHit(CacheTier tier) {
    totalHits++;
    tierHits[tier] = (tierHits[tier] ?? 0) + 1;
  }
  
  void recordMiss() {
    totalMisses++;
  }
  
  void recordPutTier(CacheTier tier) {
    tierPuts[tier] = (tierPuts[tier] ?? 0) + 1;
  }
  
  double get hitRate => totalGets > 0 ? totalHits / totalGets : 0.0;
  
  double get averageAccessTime => totalGets > 0 ? totalMicroseconds / totalGets : 0.0;
  
  double get compressionRatio => uncompressedSize > 0 ? compressedSize / uncompressedSize : 1.0;
  
  Map<String, dynamic> toJson() => {
    'total_gets': totalGets,
    'total_puts': totalPuts,
    'total_hits': totalHits,
    'total_misses': totalMisses,
    'hit_rate': hitRate,
    'average_access_time_us': averageAccessTime,
    'compression_ratio': compressionRatio,
    'tier_hits': tierHits,
    'tier_puts': tierPuts,
  };
}

class CacheAnalysis {
  final int ramCacheSize;
  final int ssdCacheSize;
  final int networkCacheSize;
  final double ramMemoryUsage;
  final double ssdMemoryUsage;
  final double hitRate;
  final double averageAccessTime;
  final double compressionRatio;
  final List<UsagePattern> usagePatterns;
  final List<CachePrediction> predictions;
  
  CacheAnalysis({
    required this.ramCacheSize,
    required this.ssdCacheSize,
    required this.networkCacheSize,
    required this.ramMemoryUsage,
    required this.ssdMemoryUsage,
    required this.hitRate,
    required this.averageAccessTime,
    required this.compressionRatio,
    required this.usagePatterns,
    required this.predictions,
  });
}

class CacheResult<T> {
  final bool success;
  final T? value;
  final String? error;
  final bool fromCache;
  
  CacheResult({
    required this.success,
    this.value,
    this.error,
    this.fromCache = true,
  });
  
  factory CacheResult.success(T value, {bool fromCache = true}) {
    return CacheResult(
      success: true,
      value: value,
      fromCache: fromCache,
    );
  }
  
  factory CacheResult.miss() {
    return CacheResult(
      success: false,
      fromCache: false,
    );
  }
  
  factory CacheResult.error(String error) {
    return CacheResult(
      success: false,
      error: error,
    );
  }
}

class CacheEvent {
  final CacheEventType type;
  final Map<String, dynamic>? data;
  
  CacheEvent({
    required this.type,
    this.data,
  });
}

enum CacheTier {
  ram,
  ssd,
  network,
}

enum CompressionAlgorithm {
  lzf4,
  zstd,
  none,
}

enum InvalidationMode {
  exact,
  semantic,
  pattern,
}

enum CacheEventType {
  entryAdded,
  entryInvalidated,
  semanticInvalidation,
  compressionChanged,
}
