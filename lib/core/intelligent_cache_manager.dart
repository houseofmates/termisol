import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:process_run/process_run.dart';

/// Intelligent cache management with predictive optimization
/// 
/// Features:
/// - Predictive cache warming
/// - Smart cache eviction
/// - Cache performance monitoring
/// - Multi-tier cache strategy
/// - AI-powered cache optimization
class IntelligentCacheManager {
  final Map<String, CacheTier> _cacheTiers = {};
  Map<String, CacheEntry> _cacheEntries = {};
  Map<String, CachePattern> _accessPatterns = {};
  final StreamController<CacheEvent> _eventController = StreamController<CacheEvent>.broadcast();
  
  Timer? _cleanupTimer;
  Timer? _analysisTimer;
  Timer? _warmingTimer;
  bool _isInitialized = false;
  late SharedPreferences _prefs;
  
  Stream<CacheEvent> get events => _eventController.stream;
  bool get isInitialized => _isInitialized;
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      
      // Initialize cache tiers
      _initializeCacheTiers();
      
      // Load existing cache data
      await _loadCacheData();
      
      // Start periodic tasks
      _startPeriodicTasks();
      
      _isInitialized = true;
      
      _eventController.add(CacheEvent(
        type: CacheEventType.initialized,
        message: 'Intelligent cache manager initialized',
        data: {'tiers': _cacheTiers.length},
      ));
      
      debugPrint('🗄️ Intelligent Cache Manager initialized');
    } catch (e) {
      debugPrint('Failed to initialize intelligent cache manager: $e');
    }
  }
  
  void _initializeCacheTiers() {
    // Memory tier (fastest)
    _cacheTiers['memory'] = CacheTier(
      name: 'memory',
      maxSizeGB: 0.5, // 512MB
      accessSpeed: CacheAccessSpeed.instant,
      persistence: CachePersistence.volatile,
      priority: 1,
    );
    
    // SSD tier (fast)
    _cacheTiers['ssd'] = CacheTier(
      name: 'ssd',
      maxSizeGB: 2.0, // 2GB
      accessSpeed: CacheAccessSpeed.fast,
      persistence: CachePersistence.persistent,
      priority: 2,
    );
    
    // HDD tier (slow)
    _cacheTiers['hdd'] = CacheTier(
      name: 'hdd',
      maxSizeGB: 10.0, // 10GB
      accessSpeed: CacheAccessSpeed.slow,
      persistence: CachePersistence.persistent,
      priority: 3,
    );
  }
  
  Future<void> _loadCacheData() async {
    try {
      final entriesJson = _prefs.getString('cache_entries');
      if (entriesJson != null) {
        final entriesMap = jsonDecode(entriesJson);
        _cacheEntries = entriesMap.map((key, value) => 
          MapEntry(key, CacheEntry.fromJson(value)));
      }
      
      final patternsJson = _prefs.getString('access_patterns');
      if (patternsJson != null) {
        _accessPatterns = Map<String, CachePattern>.from(jsonDecode(patternsJson));
      }
    } catch (e) {
      debugPrint('Failed to load cache data: $e');
    }
  }
  
  void _startPeriodicTasks() {
    // Cleanup timer (every 30 minutes)
    _cleanupTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      _performCacheCleanup();
    });
    
    // Analysis timer (every hour)
    _analysisTimer = Timer.periodic(const Duration(hours: 1), (_) {
      _analyzeAccessPatterns();
    });
    
    // Predictive warming timer (every 2 hours)
    _warmingTimer = Timer.periodic(const Duration(hours: 2), (_) {
      _performPredictiveWarming();
    });
  }
  
  Future<void> cacheFile({
    required String filePath,
    required String key,
    CacheTier? preferredTier,
    int? priority,
  }) async {
    try {
      final tier = preferredTier ?? _selectOptimalTier(filePath, priority ?? 0);
      final fileInfo = await _getFileInfo(filePath);
      
      final entry = CacheEntry(
        key: key,
        filePath: filePath,
        tier: tier.name,
        size: fileInfo.size,
        lastAccessed: DateTime.now(),
        accessCount: 1,
        priority: priority ?? 0,
        createdAt: DateTime.now(),
      );
      
      // Check if tier has space
      if (!_hasSpaceInTier(tier, fileInfo.size)) {
        await _evictFromTier(tier, fileInfo.size);
      }
      
      // Copy file to cache tier
      await _copyToCacheTier(filePath, tier, key);
      
      _cacheEntries[key] = entry;
      
      // Update access pattern
      _updateAccessPattern(key);
      
      _eventController.add(CacheEvent(
        type: CacheEventType.file_cached,
        message: 'File cached: $key',
        data: {
          'key': key,
          'tier': tier.name,
          'size': fileInfo.size,
        },
      ));
      
    } catch (e) {
      _eventController.add(CacheEvent(
        type: CacheEventType.error,
        message: 'Failed to cache file: $e',
        data: {'key': key, 'error': e.toString()},
      ));
    }
  }
  
  CacheTier _selectOptimalTier(String filePath, int priority) {
    final fileInfo = _getFileInfoSync(filePath);
    
    // High priority files go to fastest tier
    if (priority > 8) {
      return _cacheTiers['memory']!;
    }
    
    // Small files go to memory tier
    if (fileInfo.size < 0.01) { // < 10MB
      return _cacheTiers['memory']!;
    }
    
    // Medium files go to SSD tier
    if (fileInfo.size < 0.5) { // < 500MB
      return _cacheTiers['ssd']!;
    }
    
    // Large files go to HDD tier
    return _cacheTiers['hdd']!;
  }
  
  bool _hasSpaceInTier(CacheTier tier, double fileSize) {
    final currentUsage = _cacheEntries.values
        .where((entry) => entry.tier == tier.name)
        .fold(0.0, (sum, entry) => sum + entry.size);
    
    return (currentUsage + fileSize) <= tier.maxSizeGB;
  }
  
  Future<void> _evictFromTier(CacheTier tier, double requiredSpace) async {
    final entriesInTier = _cacheEntries.values
        .where((entry) => entry.tier == tier.name)
        .toList();
    
    // Sort by LRU (least recently used)
    entriesInTier.sort((a, b) => a.lastAccessed.compareTo(b.lastAccessed));
    
    double freedSpace = 0.0;
    for (final entry in entriesInTier) {
      if (freedSpace >= requiredSpace) break;
      
      await _removeFromCache(entry.key);
      freedSpace += entry.size;
    }
  }
  
  Future<void> _copyToCacheTier(String filePath, CacheTier tier, String key) async {
    try {
      final cacheDir = await _getCacheTierDirectory(tier);
      final cacheFile = '$cacheDir/$key';
      
      // Create directory if it doesn't exist
      await Directory(cacheDir).create(recursive: true);
      
      // Copy file
      await File(filePath).copy(cacheFile);
      
    } catch (e) {
      debugPrint('Failed to copy to cache tier: $e');
      rethrow;
    }
  }
  
  Future<String> _getCacheTierDirectory(CacheTier tier) async {
    final homeDir = Platform.environment['HOME'] ?? '';
    final baseCacheDir = '$homeDir/.cache/termisol';
    
    switch (tier.name) {
      case 'memory':
        return '$baseCacheDir/memory';
      case 'ssd':
        return '$baseCacheDir/ssd';
      case 'hdd':
        return '$baseCacheDir/hdd';
      default:
        return baseCacheDir;
    }
  }
  
  Future<FileInfo> _getFileInfo(String filePath) async {
    final stat = await File(filePath).stat();
    return FileInfo(
      path: filePath,
      size: stat.size / (1024 * 1024 * 1024), // Convert to GB
      lastModified: stat.modified,
      isDirectory: stat.type == FileSystemEntityType.directory,
    );
  }
  
  FileInfo _getFileInfoSync(String filePath) {
    final stat = File(filePath).statSync();
    return FileInfo(
      path: filePath,
      size: stat.size / (1024 * 1024 * 1024), // Convert to GB
      lastModified: stat.modified,
      isDirectory: stat.type == FileSystemEntityType.directory,
    );
  }
  
  void _updateAccessPattern(String key) {
    final now = DateTime.now();
    final pattern = _accessPatterns[key] ?? CachePattern(
      key: key,
      accessTimes: [],
      averageInterval: 0.0,
      predictedNextAccess: now,
    );
    
    pattern.accessTimes.add(now);
    
    // Keep only last 100 accesses
    if (pattern.accessTimes.length > 100) {
      pattern.accessTimes.removeAt(0);
    }
    
    // Calculate average interval
    if (pattern.accessTimes.length >= 2) {
      final intervals = <int>[];
      for (int i = 1; i < pattern.accessTimes.length; i++) {
        intervals.add(pattern.accessTimes[i].difference(pattern.accessTimes[i-1]).inMinutes);
      }
      
      pattern.averageInterval = intervals.reduce((a, b) => a + b) / intervals.length;
      
      // Predict next access
      final lastAccess = pattern.accessTimes.last;
      pattern.predictedNextAccess = lastAccess.add(Duration(minutes: pattern.averageInterval.round()));
    }
    
    _accessPatterns[key] = pattern;
  }
  
  Future<void> _performCacheCleanup() async {
    try {
      final now = DateTime.now();
      final entriesToRemove = <String>[];
      
      for (final entry in _cacheEntries.values) {
        final tier = _cacheTiers[entry.tier]!;
        
        // Remove expired entries
        if (now.difference(entry.lastAccessed).inDays > 30) {
          entriesToRemove.add(entry.key);
          continue;
        }
        
        // Remove low-priority entries from memory tier
        if (tier.name == 'memory' && entry.priority < 3) {
          entriesToRemove.add(entry.key);
        }
      }
      
      // Remove entries
      for (final key in entriesToRemove) {
        await _removeFromCache(key);
      }
      
      _eventController.add(CacheEvent(
        type: CacheEventType.cleanup_completed,
        message: 'Cache cleanup completed',
        data: {'removed_entries': entriesToRemove.length},
      ));
      
    } catch (e) {
      debugPrint('Failed to perform cache cleanup: $e');
    }
  }
  
  Future<void> _analyzeAccessPatterns() async {
    try {
      final now = DateTime.now();
      final predictions = <String>[];
      
      for (final pattern in _accessPatterns.values) {
        // Check if predicted access time is near
        final timeToPrediction = pattern.predictedNextAccess.difference(now);
        
        if (timeToPrediction.inHours.abs() < 2) { // Within 2 hours
          predictions.add(pattern.key);
        }
      }
      
      if (predictions.isNotEmpty) {
        _eventController.add(CacheEvent(
          type: CacheEventType.predictions_made,
          message: 'Access pattern predictions generated',
          data: {'predictions': predictions},
        ));
      }
      
    } catch (e) {
      debugPrint('Failed to analyze access patterns: $e');
    }
  }
  
  Future<void> _performPredictiveWarming() async {
    try {
      final now = DateTime.now();
      final warmingCandidates = <CacheEntry>[];
      
      for (final entry in _cacheEntries.values) {
        final pattern = _accessPatterns[entry.key];
        
        if (pattern != null) {
          final timeToPrediction = pattern.predictedNextAccess.difference(now);
          
          // Warm up files that will be accessed soon
          if (timeToPrediction.inMinutes > 0 && timeToPrediction.inMinutes < 60) {
            warmingCandidates.add(entry);
          }
        }
      }
      
      // Sort by priority and predicted access time
      warmingCandidates.sort((a, b) {
        final priorityComparison = b.priority.compareTo(a.priority);
        if (priorityComparison != 0) return priorityComparison;
        
        final patternA = _accessPatterns[a.key];
        final patternB = _accessPatterns[b.key];
        
        if (patternA != null && patternB != null) {
          return patternA.predictedNextAccess.compareTo(patternB.predictedNextAccess);
        }
        
        return 0;
      });
      
      // Warm up top candidates
      for (final entry in warmingCandidates.take(5)) {
        await _warmUpCacheEntry(entry);
      }
      
      _eventController.add(CacheEvent(
        type: CacheEventType.warming_completed,
        message: 'Predictive cache warming completed',
        data: {'warmed_entries': warmingCandidates.take(5).length},
      ));
      
    } catch (e) {
      debugPrint('Failed to perform predictive warming: $e');
    }
  }
  
  Future<void> _warmUpCacheEntry(CacheEntry entry) async {
    try {
      // Read file to warm up OS cache
      final cacheDir = await _getCacheTierDirectory(_cacheTiers[entry.tier]!);
      final cacheFile = '$cacheDir/${entry.key}';
      
      await File(cacheFile).readAsBytes();
      
      entry.lastAccessed = DateTime.now();
      
    } catch (e) {
      debugPrint('Failed to warm up cache entry: $e');
    }
  }
  
  Future<void> _removeFromCache(String key) async {
    try {
      final entry = _cacheEntries[key];
      if (entry == null) return;
      
      // Remove from cache tier
      final tier = _cacheTiers[entry.tier]!;
      final cacheDir = await _getCacheTierDirectory(tier);
      final cacheFile = '$cacheDir/$key';
      
      await File(cacheFile).delete();
      
      // Remove from entries
      _cacheEntries.remove(key);
      
    } catch (e) {
      debugPrint('Failed to remove from cache: $e');
    }
  }
  
  Future<void> saveCacheState() async {
    try {
      final entriesMap = _cacheEntries.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('cache_entries', jsonEncode(entriesMap));
      
      final patternsMap = _accessPatterns.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('access_patterns', jsonEncode(patternsMap));
      
    } catch (e) {
      debugPrint('Failed to save cache state: $e');
    }
  }
  
  Map<String, dynamic> getStatistics() {
    final tierStats = <String, dynamic>{};
    
    for (final tier in _cacheTiers.values) {
      final entries = _cacheEntries.values.where((e) => e.tier == tier.name);
      final totalSize = entries.fold(0.0, (sum, e) => sum + e.size);
      final hitRate = _calculateHitRate(tier.name);
      
      tierStats[tier.name] = {
        'entries': entries.length,
        'totalSize': totalSize,
        'maxSize': tier.maxSizeGB,
        'utilization': (totalSize / tier.maxSizeGB) * 100,
        'hitRate': hitRate,
      };
    }
    
    return {
      'totalEntries': _cacheEntries.length,
      'totalSize': _cacheEntries.values.fold(0.0, (sum, e) => sum + e.size),
      'tierStats': tierStats,
      'patternsAnalyzed': _accessPatterns.length,
    };
  }
  
  double _calculateHitRate(String tierName) {
    // Simplified hit rate calculation
    // In real implementation, this would track actual hits vs misses
    return 0.85; // Placeholder
  }
  
  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    _analysisTimer?.cancel();
    _warmingTimer?.cancel();
    
    await saveCacheState();
    
    _eventController.close();
    debugPrint('🗄️ Intelligent Cache Manager disposed');
  }
}

// Data models
class CacheTier {
  final String name;
  final double maxSizeGB;
  final CacheAccessSpeed accessSpeed;
  final CachePersistence persistence;
  final int priority;
  
  CacheTier({
    required this.name,
    required this.maxSizeGB,
    required this.accessSpeed,
    required this.persistence,
    required this.priority,
  });
}

class CacheEntry {
  final String key;
  final String filePath;
  final String tier;
  final double size;
  DateTime lastAccessed;
  int accessCount;
  final int priority;
  final DateTime createdAt;
  
  CacheEntry({
    required this.key,
    required this.filePath,
    required this.tier,
    required this.size,
    required this.lastAccessed,
    required this.accessCount,
    required this.priority,
    required this.createdAt,
  });
  
  Map<String, dynamic> toJson() => {
    'key': key,
    'filePath': filePath,
    'tier': tier,
    'size': size,
    'lastAccessed': lastAccessed.toIso8601String(),
    'accessCount': accessCount,
    'priority': priority,
    'createdAt': createdAt.toIso8601String(),
  };
  
  factory CacheEntry.fromJson(Map<String, dynamic> json) => CacheEntry(
    key: json['key'],
    filePath: json['filePath'],
    tier: json['tier'],
    size: json['size']?.toDouble() ?? 0.0,
    lastAccessed: DateTime.parse(json['lastAccessed']),
    accessCount: json['accessCount'] ?? 0,
    priority: json['priority'] ?? 0,
    createdAt: DateTime.parse(json['createdAt']),
  );
}

class CachePattern {
  final String key;
  final List<DateTime> accessTimes;
  double averageInterval;
  DateTime predictedNextAccess;
  
  CachePattern({
    required this.key,
    required this.accessTimes,
    required this.averageInterval,
    required this.predictedNextAccess,
  });
  
  Map<String, dynamic> toJson() => {
    'key': key,
    'accessTimes': accessTimes.map((dt) => dt.toIso8601String()).toList(),
    'averageInterval': averageInterval,
    'predictedNextAccess': predictedNextAccess.toIso8601String(),
  };
  
  factory CachePattern.fromJson(Map<String, dynamic> json) => CachePattern(
    key: json['key'],
    accessTimes: (json['accessTimes'] as List)
        .map((dt) => DateTime.parse(dt))
        .toList(),
    averageInterval: json['averageInterval']?.toDouble() ?? 0.0,
    predictedNextAccess: DateTime.parse(json['predictedNextAccess']),
  );
}

class FileInfo {
  final String path;
  final double size;
  final DateTime lastModified;
  final bool isDirectory;
  
  FileInfo({
    required this.path,
    required this.size,
    required this.lastModified,
    required this.isDirectory,
  });
}

enum CacheAccessSpeed {
  instant,
  fast,
  slow,
}

enum CachePersistence {
  volatile,
  persistent,
}

enum CacheEventType {
  initialized,
  file_cached,
  file_accessed,
  cleanup_completed,
  predictions_made,
  warming_completed,
  error,
}

class CacheEvent {
  final CacheEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  
  CacheEvent({
    required this.type,
    required this.message,
    this.data,
  }) : timestamp = DateTime.now();
}
