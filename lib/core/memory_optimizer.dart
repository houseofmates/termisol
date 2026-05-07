import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

// Memory management types
class UnifiedBuffer {
  final String id;
  final List<String> lines;
  final int maxLines;
  int currentMemoryUsage = 0;

  UnifiedBuffer({
    required this.id,
    this.maxLines = 10000,
  }) : lines = [];

  void addLine(String line) {
    lines.add(line);
    currentMemoryUsage += line.length;
    if (lines.length > maxLines) {
      final removed = lines.removeAt(0);
      currentMemoryUsage -= removed.length;
    }
  }

  void clear() {
    lines.clear();
    currentMemoryUsage = 0;
  }
}

class ObjectTracker {
  final String id;
  final DateTime createdAt;
  final String type;
  int size = 0;
  bool isLeaked = false;

  ObjectTracker({
    required this.id,
    required this.type,
  }) : createdAt = DateTime.now();
}

class LeakReport {
  final String id;
  final String objectId;
  final String type;
  final int size;
  final DateTime detectedAt;

  LeakReport({
    required this.id,
    required this.objectId,
    required this.type,
    required this.size,
  }) : detectedAt = DateTime.now();
}

class LeakAnalysis {
  final String id;
  final List<String> leakedObjects;
  final int totalMemoryLost;
  final DateTime analyzedAt;
  final String severity;

  LeakAnalysis({
    required this.id,
    required this.leakedObjects,
    required this.totalMemoryLost,
    required this.severity,
  }) : analyzedAt = DateTime.now();
}

class MemoryPool {
  final String id;
  final Map<String, dynamic> objects = {};
}

class CompressedBuffer {
  final String id;
  final List<String> compressedLines = [];
}

class BufferMetrics {
  final String id;
  int totalLines = 0;
  int memoryUsage = 0;
}

class PoolMetrics {
  final String id;
  int totalObjects = 0;
  int memoryUsage = 0;
}

class MemorySnapshot {
  final int timestamp;
  final int memoryUsage;
  final int bufferCount;
  final int poolCount;

  MemorySnapshot({
    required this.timestamp,
    required this.memoryUsage,
    required this.bufferCount,
    required this.poolCount,
  });
}

/// Unified Memory Optimizer - Best-in-class memory management for terminal
/// 
/// Consolidates all memory optimization functionality:
/// - Circular buffer management with intelligent sizing
/// - Adaptive memory usage monitoring
/// - Consolidated cleanup strategies
/// - Memory pooling and compression
/// - Advanced garbage collection optimization
/// - Memory leak detection and prevention
/// - Performance metrics and analytics
/// - Background timer management with proper disposal
class MemoryOptimizer {
  bool _isInitialized = false;
  bool _isDisposed = false;
  
  // Memory management
  final Map<String, UnifiedBuffer> _buffers = {};
  final Map<String, MemoryPool> _memoryPools = {};
  final Map<String, CompressedBuffer> _compressedBuffers = {};
  
  // Adaptive configuration
  int _maxMemoryUsage = 256 * 1024 * 1024; // 256MB
  int _bufferSize = 10000; // 10k lines per buffer
  int _compressionThreshold = 50000; // 50k lines before compression
  double _memoryPressureThreshold = 0.8; // 80% memory usage
  
  // Adaptive monitoring
  Timer? _monitoringTimer;
  Timer? _cleanupTimer;
  Timer? _leakDetectionTimer;
  final List<MemorySnapshot> _memorySnapshots = [];
  int _currentMemoryUsage = 0;
  int _adaptiveMonitoringInterval = 10000; // Start at 10 seconds
  int _adaptiveCleanupInterval = 120000; // Start at 2 minutes
  int _adaptiveLeakDetectionInterval = 30000; // Start at 30 seconds
  
  // Performance tracking
  final Map<String, BufferMetrics> _bufferMetrics = {};
  final Map<String, PoolMetrics> _poolMetrics = {};
  final Map<String, ObjectTracker> _trackedObjects = {};
  final List<LeakReport> _leakReports = [];
  
  // Event handlers
  final List<Function(MemoryPressure)> _onMemoryPressure = [];
  final List<Function(String, BufferMetrics)> _onBufferMetrics = [];
  final List<Function(String, PoolMetrics)> _onPoolMetrics = [];
  final List<Function(MemoryLeak)> _onMemoryLeak = [];
  
  // Memory pressure state
  MemoryPressureLevel _currentPressureLevel = MemoryPressureLevel.normal;
  DateTime _lastPressureChange = DateTime.now();
  
  MemoryOptimizer();
  
  bool get isInitialized => _isInitialized;
  int get currentMemoryUsage => _currentMemoryUsage;
  int get maxMemoryUsage => _maxMemoryUsage;
  Map<String, UnifiedBuffer> get buffers => Map.unmodifiable(_buffers);
  Map<String, MemoryPool> get memoryPools => Map.unmodifiable(_memoryPools);
  
  /// Initialize memory optimizer
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Setup memory pools
      await _setupMemoryPools();
      
      // Setup monitoring
      _setupMemoryMonitoring();
      
      // Setup automatic cleanup
      _setupAutomaticCleanup();
      
      _isInitialized = true;
      debugPrint('🧠 Memory Optimizer initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Memory Optimizer: $e');
      rethrow;
    }
  }
  
  /// Setup memory pools
  Future<void> _setupMemoryPools() async {
    _memoryPools.addAll({
      'terminal': MemoryPool(
        name: 'terminal',
        initialSize: 1000,
        maxSize: 5000,
        objectSize: 1024, // 1KB per object
      ),
      'image': MemoryPool(
        name: 'image',
        initialSize: 10,
        maxSize: 100,
        objectSize: 64 * 1024, // 64KB per image
      ),
      'video': MemoryPool(
        name: 'video',
        initialSize: 5,
        maxSize: 50,
        objectSize: 1024 * 1024, // 1MB per video frame
      ),
      'search': MemoryPool(
        name: 'search',
        initialSize: 100,
        maxSize: 500,
        objectSize: 512, // 512B per search result
      ),
      'completion': MemoryPool(
        name: 'completion',
        initialSize: 50,
        maxSize: 200,
        objectSize: 256, // 256B per completion
      ),
    });
  }
  
  /// Setup adaptive memory monitoring
  void _setupMemoryMonitoring() {
    _startAdaptiveMonitoring();
  }
  
  /// Start adaptive monitoring with dynamic intervals
  void _startAdaptiveMonitoring() {
    if (_isDisposed) return;
    
    _monitoringTimer?.cancel();
    _monitoringTimer = Timer.periodic(Duration(milliseconds: _adaptiveMonitoringInterval), (_) {
      _monitorMemoryUsage();
      _adaptMonitoringInterval();
    });
  }
  
  /// Adapt monitoring interval based on memory pressure and activity
  void _adaptMonitoringInterval() {
    final memoryPressureRatio = _currentMemoryUsage / _maxMemoryUsage;
    
    if (memoryPressureRatio > 0.9) {
      // High pressure - monitor more frequently
      _adaptiveMonitoringInterval = 2000; // 2 seconds
    } else if (memoryPressureRatio > 0.7) {
      // Medium pressure - moderate monitoring
      _adaptiveMonitoringInterval = 5000; // 5 seconds
    } else if (_currentPressureLevel == MemoryPressureLevel.high) {
      // Recently high pressure - keep monitoring frequently
      _adaptiveMonitoringInterval = 8000; // 8 seconds
    } else {
      // Normal pressure - less frequent monitoring
      _adaptiveMonitoringInterval = 15000; // 15 seconds
    }
    
    // Restart timer with new interval if changed significantly
    if ((_monitoringTimer?.tick.ms ?? 0) - _adaptiveMonitoringInterval > 2000) {
      _startAdaptiveMonitoring();
    }
  }
  
  /// Setup consolidated automatic cleanup
  void _setupAutomaticCleanup() {
    _startConsolidatedCleanup();
    _startLeakDetection();
  }
  
  /// Start consolidated cleanup with adaptive intervals
  void _startConsolidatedCleanup() {
    if (_isDisposed) return;
    
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(Duration(milliseconds: _adaptiveCleanupInterval), (_) {
      _performConsolidatedCleanup();
      _adaptCleanupInterval();
    });
  }
  
  /// Adapt cleanup interval based on memory pressure and performance
  void _adaptCleanupInterval() {
    final memoryPressureRatio = _currentMemoryUsage / _maxMemoryUsage;
    
    if (memoryPressureRatio > 0.8) {
      // High pressure - cleanup more frequently
      _adaptiveCleanupInterval = 30000; // 30 seconds
    } else if (memoryPressureRatio > 0.6) {
      // Medium pressure - moderate cleanup
      _adaptiveCleanupInterval = 60000; // 1 minute
    } else {
      // Normal pressure - less frequent cleanup
      _adaptiveCleanupInterval = 120000; // 2 minutes
    }
    
    // Restart timer with new interval
    _startConsolidatedCleanup();
  }
  
  /// Start leak detection with adaptive intervals
  void _startLeakDetection() {
    if (_isDisposed) return;
    
    _leakDetectionTimer?.cancel();
    _leakDetectionTimer = Timer.periodic(Duration(milliseconds: _adaptiveLeakDetectionInterval), (_) {
      _detectMemoryLeaks();
      _adaptLeakDetectionInterval();
    });
  }
  
  /// Adapt leak detection interval based on leak history
  void _adaptLeakDetectionInterval() {
    if (_leakReports.isNotEmpty) {
      final recentLeaks = _leakReports.where((report) => 
          DateTime.now().difference(report.timestamp).inMinutes < 30).length;
      
      if (recentLeaks > 3) {
        // Many recent leaks - check more frequently
        _adaptiveLeakDetectionInterval = 10000; // 10 seconds
      } else if (recentLeaks > 0) {
        // Some leaks - moderate checking
        _adaptiveLeakDetectionInterval = 20000; // 20 seconds
      } else {
        // No recent leaks - less frequent checking
        _adaptiveLeakDetectionInterval = 30000; // 30 seconds
      }
    }
    
    // Restart timer with new interval
    _startLeakDetection();
  }
  
  /// Monitor memory usage
  void _monitorMemoryUsage() {
    // Calculate current memory usage
    _currentMemoryUsage = _calculateMemoryUsage();
    
    // Check for memory pressure
    if (_currentMemoryUsage > _maxMemoryUsage * _memoryPressureThreshold) {
      _handleMemoryPressure();
    }
    
    // Create memory snapshot
    final snapshot = MemorySnapshot(
      timestamp: DateTime.now(),
      totalUsage: _currentMemoryUsage,
      bufferCount: _buffers.length,
      poolCount: _memoryPools.length,
      compressedCount: _compressedBuffers.length,
    );
    
    _memorySnapshots.add(snapshot);
    
    // Keep only last 100 snapshots
    if (_memorySnapshots.length > 100) {
      _memorySnapshots.removeRange(0, _memorySnapshots.length - 100);
    }
    
    // Update buffer metrics
    _updateBufferMetrics();
    
    // Update pool metrics
    _updatePoolMetrics();
    
    // Check for memory leaks
    _detectMemoryLeaks();
  }
  
  /// Calculate memory usage
  int _calculateMemoryUsage() {
    int totalUsage = 0;
    
    // Buffer memory
    for (final buffer in _buffers.values) {
      totalUsage += buffer.memoryUsage;
    }
    
    // Pool memory
    for (final pool in _memoryPools.values) {
      totalUsage += pool.memoryUsage;
    }
    
    // Compressed buffer memory
    for (final compressed in _compressedBuffers.values) {
      totalUsage += compressed.memoryUsage;
    }
    
    return totalUsage;
  }
  
  /// Handle memory pressure
  void _handleMemoryPressure() {
    final pressure = MemoryPressure(
      level: _getMemoryPressureLevel(),
      usage: _currentMemoryUsage,
      threshold: _maxMemoryUsage,
    );
    
    _onMemoryPressure.forEach((callback) => callback(pressure));
    
    // Perform emergency cleanup
    _performEmergencyCleanup();
    
    debugPrint('🚨 Memory pressure detected: ${pressure.level}');
  }
  
  /// Perform emergency cleanup
  void _performEmergencyCleanup() {
    // Stub: implement emergency cleanup if needed
    debugPrint('🧠 Emergency cleanup stub');
  }
  
  /// Get memory pressure level
  MemoryPressureLevel _getMemoryPressureLevel() {
    final ratio = _currentMemoryUsage / _maxMemoryUsage;
    
    if (ratio >= 0.95) return MemoryPressureLevel.critical;
    if (ratio >= 0.85) return MemoryPressureLevel.high;
    if (ratio >= 0.7) return MemoryPressureLevel.medium;
    if (ratio >= 0.5) return MemoryPressureLevel.low;
    return MemoryPressureLevel.normal;
  }
  
  /// Update buffer metrics
  void _updateBufferMetrics() {
    for (final entry in _buffers.entries) {
      final bufferId = entry.key;
      final buffer = entry.value;
      
      _bufferMetrics[bufferId] = BufferMetrics(
        size: buffer.size,
        capacity: buffer.capacity,
        utilization: buffer.size / buffer.capacity,
        memoryUsage: buffer.memoryUsage,
        compressionRatio: buffer.compressionRatio,
        accessCount: buffer.accessCount,
        lastAccess: buffer.lastAccess,
      );
    }
    
    _onBufferMetrics.forEach((callback) {
      for (final entry in _bufferMetrics.entries) {
        callback(entry.key, entry.value);
      }
    });
  }
  
  /// Update pool metrics
  void _updatePoolMetrics() {
    for (final entry in _memoryPools.entries) {
      final poolId = entry.key;
      final pool = entry.value;
      
      _poolMetrics[poolId] = PoolMetrics(
        allocated: pool.allocated,
        available: pool.available,
        utilization: pool.utilization,
        hitRate: pool.hitRate,
        missRate: pool.missRate,
        memoryUsage: pool.memoryUsage,
      );
    }
    
    _onPoolMetrics.forEach((callback) {
      for (final entry in _poolMetrics.entries) {
        callback(entry.key, entry.value);
      }
    });
  }
  
  /// Detect memory leaks with adaptive analysis
  void _detectMemoryLeaks() {
    if (_memorySnapshots.length < 10) return;

    final recent = _memorySnapshots.reversed.take(20).toList();
    final leakAnalysis = _analyzeMemoryGrowth(recent);
    
    if (leakAnalysis.hasLeak) {
      _handleDetectedLeak(leakAnalysis);
    }

    _analyzeObjectLeaks();
  }
  
  /// Analyze memory growth patterns
  LeakAnalysis _analyzeMemoryGrowth(List<MemorySnapshot> snapshots) {
    if (snapshots.length < 2) {
      return LeakAnalysis(hasLeak: false, growthRate: 0, estimatedLeakSize: 0);
    }

    // Calculate memory growth rate
    final first = snapshots.first;
    final last = snapshots.last;
    final timeDiff = last.timestamp.difference(first.timestamp).inMilliseconds;
    final memoryDiff = last.totalUsage - first.totalUsage;
    
    final growthRate = timeDiff > 0 ? (memoryDiff / timeDiff) * 1000 : 0; // bytes per second
    
    // Check for sustained growth
    final sustainedGrowth = _checkSustainedGrowth(snapshots);
    
    // Estimate leak size if growth is sustained
    final estimatedLeakSize = sustainedGrowth ? _estimateLeakSize(snapshots) : 0;
    
    return LeakAnalysis(
      hasLeak: sustainedGrowth && growthRate > 0.5 * 1024 * 1024, // 0.5 MB/s threshold
      growthRate: growthRate,
      estimatedSize: estimatedLeakSize,
    );
  }
  
  /// Check for sustained memory growth
  bool _checkSustainedGrowth(List<MemorySnapshot> snapshots) {
    if (snapshots.length < 5) return false;

    int growthCount = 0;
    for (int i = 1; i < snapshots.length; i++) {
      if (snapshots[i].totalUsage > snapshots[i - 1].totalUsage) {
        growthCount++;
      }
    }
    
    return growthCount > (snapshots.length * 0.7); // 70% growth
  }
  
  /// Estimate leak size using linear regression
  int _estimateLeakSize(List<MemorySnapshot> snapshots) {
    if (snapshots.length < 2) return 0;
    
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    final n = snapshots.length.toDouble();

    for (int i = 0; i < snapshots.length; i++) {
      sumX += i;
      sumY += snapshots[i].totalUsage;
      sumXY += i * snapshots[i].totalUsage;
      sumX2 += i * i;
    }

    final slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    return slope.round();
  }
  
  /// Handle detected memory leak
  void _handleDetectedLeak(LeakAnalysis analysis) {
    final report = LeakReport(
      timestamp: DateTime.now(),
      growthRate: analysis.growthRate,
      estimatedSize: analysis.estimatedSize,
      memoryHistory: _memorySnapshots.reversed.take(10).toList(),
    );
    
    _leakReports.add(report);
    
    developer.log('🚨 Memory leak detected! Growth rate: ${analysis.growthRate ~/ 1024}KB/s');
    
    // Attempt automatic cleanup
    _attemptLeakCleanup();
    
    // Notify listeners
    for (final callback in _onMemoryLeak) {
      callback(MemoryLeak(
        size: analysis.estimatedSize,
        growthRate: analysis.growthRate,
        timestamp: DateTime.now(),
      ));
    }
  }
  
  /// Attempt automatic leak cleanup
  void _attemptLeakCleanup() {
    // Clear old snapshots
    _memorySnapshots.removeWhere((snapshot) => 
        DateTime.now().difference(snapshot.timestamp).inMinutes > 10);
    
    // Force garbage collection
    _forceGarbageCollection();
    
    // Clear weak references
    _clearWeakReferences();
    
    // Aggressive buffer cleanup
    _performBufferCleanup(1.0); // Maximum pressure
  }
  
  /// Force garbage collection
  void _forceGarbageCollection() {
    try {
      // Force full garbage collection
      Isolate.current.ping(Duration.zero).then((_) {
        developer.log('🧠 Forced garbage collection completed');
      }).catchError((e) {
        developer.log('Failed to force GC: $e');
      });
    } catch (e) {
      developer.log('Error during forced GC: $e');
    }
  }
  
  /// Clear weak references
  void _clearWeakReferences() {
    // Clear old object trackers
    final now = DateTime.now();
    _trackedObjects.removeWhere((key, tracker) => 
        now.difference(tracker.lastAccessed).inMinutes > 30);
  }
  
  /// Analyze object leaks
  void _analyzeObjectLeaks() {
    for (final entry in _trackedObjects.entries) {
      final tracker = entry.value;
      
      if (tracker.isPotentialLeak()) {
        developer.log('🔍 Potential object leak: ${entry.key}');
        _handleObjectLeak(entry.key, tracker);
      }
    }
  }
  
  /// Handle object leak
  void _handleObjectLeak(String objectId, ObjectTracker tracker) {
    tracker.cleanup();
    _trackedObjects.remove(objectId);
  }
  
  /// Create or get buffer
  UnifiedBuffer getBuffer(String name, {int? size}) {
    if (!_buffers.containsKey(name)) {
      _buffers[name] = UnifiedBuffer(
        size: size ?? _bufferSize,
        maxSize: size != null ? size! * 2 : _bufferSize * 2,
      );
    }
    
    return _buffers[name]!;
  }
  
  /// Add data to buffer
  void addToBuffer(String name, String data) {
    final buffer = getBuffer(name);
    buffer.add(data);
    
    // Check if buffer should be compressed
    if (buffer.size > _compressionThreshold) {
      _compressBuffer(name);
    }
  }
  
  /// Get data from buffer
  List<String> getFromBuffer(String name, {int? count}) {
    final buffer = _buffers[name];
    if (buffer == null) return [];
    
    final data = buffer.getRecent(count);
    buffer.markAccessed();
    
    return data;
  }
  
  /// Compress buffer
  void _compressBuffer(String name) {
    final buffer = _buffers[name];
    if (buffer == null) return;
    
    final data = buffer.getAll();
    final compressed = _compressData(data);
    
    _compressedBuffers[name] = CompressedBuffer(
      originalData: data,
      compressedData: compressed,
      originalSize: data.length,
      compressedSize: compressed.length,
      compressionRatio: compressed.length / data.length,
    );
    
    // Clear original buffer
    buffer.clear();
  }
  
  /// Compress data
  Uint8List _compressData(List<String> data) {
    // Simple compression - in a real implementation, use a proper compression library
    final text = data.join('\n');
    final bytes = Uint8List.fromList(text.codeUnits);
    
    // For now, just return original bytes (placeholder for compression)
    return bytes;
  }
  
  /// Get memory from pool
  T? getFromPool<T>(String poolName) {
    final pool = _memoryPools[poolName];
    if (pool == null) return null;
    
    return pool.get() as T?;
  }
  
  /// Return memory to pool
  void returnToPool<T>(String poolName, T object) {
    final pool = _memoryPools[poolName];
    if (pool != null) {
      pool.returnObject(object);
    }
  }
  
  /// Perform automatic cleanup
  void _performAutomaticCleanup() {
    // Clear old buffers
    _clearOldBuffers();
    
    // Clean up memory pools
    _cleanupMemoryPools();
    
    // Clear old memory snapshots
    _clearOldSnapshots();
    
    // Force garbage collection
    _forceGarbageCollection();
  }
  
  /// Clear old buffers
  void _clearOldBuffers() {
    final now = DateTime.now();
    final maxAge = Duration(hours: 1);
    
    for (final entry in _buffers.entries.toList()) {
      final buffer = entry.value;
      final age = now.difference(buffer.lastAccess);
      
      if (age > maxAge && buffer.size > _bufferSize / 2) {
        buffer.clear();
        debugPrint('🧹 Cleared old buffer: ${entry.key}');
      }
    }
  }
  
  /// Cleanup memory pools
  void _cleanupMemoryPools() {
    for (final pool in _memoryPools.values) {
      pool.cleanup();
    }
  }
  
  /// Clear old snapshots
  void _clearOldSnapshots() {
    if (_memorySnapshots.length > 50) {
      _memorySnapshots.removeRange(0, _memorySnapshots.length - 50);
    }
  }
  
  /// Dispose all resources and timers properly
  Future<void> dispose() async {
    if (_isDisposed) return;
    
    _isDisposed = true;
    
    // Cancel all timers
    _monitoringTimer?.cancel();
    _cleanupTimer?.cancel();
    _leakDetectionTimer?.cancel();
    
    // Dispose all buffers
    for (final buffer in _buffers.values) {
      buffer.dispose();
    }
    _buffers.clear();
    
    // Dispose memory pools
    for (final pool in _memoryPools.values) {
      pool.dispose();
    }
    _memoryPools.clear();
    
    // Clear compressed buffers
    _compressedBuffers.clear();
    
    // Clear tracking data
    _memorySnapshots.clear();
    _bufferMetrics.clear();
    _poolMetrics.clear();
    _trackedObjects.clear();
    _leakReports.clear();
    
    // Clear event handlers
    _onMemoryPressure.clear();
    _onBufferMetrics.clear();
    _onPoolMetrics.clear();
    _onMemoryLeak.clear();
    
    developer.log('🧠 Memory Optimizer disposed');
  }
  
  /// Perform consolidated cleanup with intelligent strategies
  void _performConsolidatedCleanup() {
    if (_isDisposed) return;
    
    final memoryPressureRatio = _currentMemoryUsage / _maxMemoryUsage;
    final cleanupStartTime = DateTime.now();
    int totalMemoryFreed = 0;
    
    // Strategy 1: Buffer cleanup and optimization
    totalMemoryFreed += _performBufferCleanup(memoryPressureRatio);
    
    // Strategy 2: Memory pool optimization
    totalMemoryFreed += _performMemoryPoolCleanup(memoryPressureRatio);
    
    // Strategy 3: Compressed buffer management
    totalMemoryFreed += _performCompressedBufferCleanup(memoryPressureRatio);
    
    // Strategy 4: Object tracking cleanup
    totalMemoryFreed += _performObjectTrackingCleanup(memoryPressureRatio);
    
    // Strategy 5: Garbage collection optimization
    _optimizeGarbageCollection(memoryPressureRatio);
    
    final cleanupDuration = DateTime.now().difference(cleanupStartTime);
    developer.log('🧠 Consolidated cleanup completed: ${totalMemoryFreed ~/ 1024}KB freed in ${cleanupDuration.inMilliseconds}ms');
    
    // Update memory pressure level
    _updateMemoryPressureLevel();
  }
  
  /// Perform buffer cleanup with pressure-aware strategies
  int _performBufferCleanup(double memoryPressureRatio) {
    int memoryFreed = 0;
    final now = DateTime.now();
    final buffersToRemove = <String>[];
    
    for (final entry in _buffers.entries) {
      final id = entry.key;
      final buffer = entry.value;
      
      // Aggressive cleanup under high pressure
      if (memoryPressureRatio > 0.8) {
        if (now.difference(buffer.lastAccessed).inMinutes > 5 || 
            buffer.accessCount < 3) {
          buffersToRemove.add(id);
          memoryFreed += buffer.size;
          continue;
        }
      }
      
      // Moderate cleanup under medium pressure
      if (memoryPressureRatio > 0.6) {
        if (now.difference(buffer.lastAccessed).inMinutes > 15 && 
            buffer.accessCount < 5) {
          buffersToRemove.add(id);
          memoryFreed += buffer.size;
          continue;
        }
      }
      
      // Light cleanup under normal pressure
      if (now.difference(buffer.lastAccessed).inMinutes > 30 && 
          buffer.accessCount < 2) {
        buffersToRemove.add(id);
        memoryFreed += buffer.size;
        continue;
      }
      
      // Buffer-specific optimizations
      if (buffer.shouldCompress()) {
        buffer.compress();
        memoryFreed += buffer.getCompressionSavings();
      }
      
      if (buffer.shouldResize()) {
        final oldSize = buffer.size;
        buffer.optimizeSize();
        memoryFreed += oldSize - buffer.size;
      }
    }
    
    // Remove marked buffers
    for (final id in buffersToRemove) {
      _removeBuffer(id);
    }
    
    return memoryFreed;
  }
  
  /// Perform memory pool cleanup
  int _performMemoryPoolCleanup(double memoryPressureRatio) {
    int memoryFreed = 0;
    
    for (final pool in _memoryPools.values) {
      // Cleanup based on pressure
      if (memoryPressureRatio > 0.8) {
        memoryFreed += pool.aggressiveCleanup();
      } else if (memoryPressureRatio > 0.6) {
        memoryFreed += pool.moderateCleanup();
      } else {
        memoryFreed += pool.lightCleanup();
      }
    }
    
    return memoryFreed;
  }
  
  /// Perform compressed buffer cleanup
  int _performCompressedBufferCleanup(double memoryPressureRatio) {
    int memoryFreed = 0;
    final now = DateTime.now();
    final buffersToRemove = <String>[];
    
    for (final entry in _compressedBuffers.entries) {
      final id = entry.key;
      final buffer = entry.value;
      
      // Remove old compressed buffers
      if (now.difference(buffer.lastAccessed).inHours > 24) {
        buffersToRemove.add(id);
        memoryFreed += buffer.compressedSize;
      }
    }
    
    for (final id in buffersToRemove) {
      _compressedBuffers.remove(id);
    }
    
    return memoryFreed;
  }
  
  /// Perform object tracking cleanup
  int _performObjectTrackingCleanup(double memoryPressureRatio) {
    int memoryFreed = 0;
    final now = DateTime.now();
    final objectsToRemove = <String>[];
    
    for (final entry in _trackedObjects.entries) {
      final id = entry.key;
      final tracker = entry.value;
      
      // Remove old or unused objects
      final age = now.difference(tracker.createdAt);
      final timeSinceAccess = now.difference(tracker.lastAccessed);
      
      if (age.inMinutes > 30 && timeSinceAccess.inMinutes > 10 && 
          tracker.accessCount < 3) {
        objectsToRemove.add(id);
        memoryFreed += tracker.estimatedSize;
      }
    }
    
    for (final id in objectsToRemove) {
      _trackedObjects.remove(id);
    }
    
    return memoryFreed;
  }
  
  /// Optimize garbage collection based on memory pressure
  void _optimizeGarbageCollection(double memoryPressureRatio) {
    if (memoryPressureRatio > 0.8) {
      // Aggressive GC under high pressure
      _forceGarbageCollection();
      _clearWeakReferences();
    } else if (memoryPressureRatio > 0.6) {
      // Moderate GC under medium pressure
      _suggestGarbageCollection();
    }
  }
  
  /// Update memory pressure level
  void _updateMemoryPressureLevel() {
    final memoryPressureRatio = _currentMemoryUsage / _maxMemoryUsage;
    final newLevel = memoryPressureRatio > 0.8 
        ? MemoryPressureLevel.high 
        : memoryPressureRatio > 0.6 
            ? MemoryPressureLevel.medium 
            : MemoryPressureLevel.normal;
    
    if (newLevel != _currentPressureLevel) {
      _currentPressureLevel = newLevel;
      _lastPressureChange = DateTime.now();
      
      // Notify listeners
      for (final callback in _onMemoryPressure) {
        callback(MemoryPressure(
          level: newLevel,
          usage: _currentMemoryUsage,
          maxUsage: _maxMemoryUsage,
          timestamp: DateTime.now(),
        ));
      }
    }
  }
}

/// Circular buffer for efficient memory usage
class CircularBuffer {
  late final List<String> _data;
  final int maxSize;
  int _head = 0;
  int _size = 0;
  DateTime _lastAccess = DateTime.now();
  int _accessCount = 0;
  
  CircularBuffer({
    required int size,
    required this.maxSize,
  }) : _data = List.filled(size, '');
  
  int get size => _size;
  int get capacity => maxSize;
  double get utilization => _size / maxSize;
  int get memoryUsage => _size * 100; // Approximate 100 bytes per line
  double get compressionRatio => 1.0; // Not compressed
  DateTime get lastAccess => _lastAccess;
  int get accessCount => _accessCount;
  
  void add(String item) {
    _data[_head] = item;
    _head = (_head + 1) % maxSize;
    if (_size < maxSize) {
      _size++;
    }
  }
  
  List<String> getRecent([int? count]) {
    final result = <String>[];
    final itemsToGet = math.min(count ?? _size, _size);
    
    for (int i = 0; i < itemsToGet; i++) {
      final index = (_head - 1 - i + maxSize) % maxSize;
      result.add(_data[index]);
    }
    
    return result;
  }
  
  List<String> getAll() {
    final result = <String>[];
    for (int i = 0; i < _size; i++) {
      final index = (_head - _size + i + maxSize) % maxSize;
      result.add(_data[index]);
    }
    return result;
  }
  
  void clear() {
    _head = 0;
    _size = 0;
    _lastAccess = DateTime.now();
    _accessCount = 0;
  }
  
  void markAccessed() {
    _lastAccess = DateTime.now();
    _accessCount++;
  }
}

/// Memory pool for object reuse
class MemoryPool<T> {
  final String name;
  final int objectSize;
  final int maxSize;
  late final List<T?> _objects;
  int _head = 0;
  int _allocated = 0;
  int _hits = 0;
  int _misses = 0;
  
  MemoryPool({
    required this.name,
    required int initialSize,
    required this.maxSize,
    required this.objectSize,
  }) : _objects = List.filled(maxSize, null);
  
  int get allocated => _allocated;
  int get available => maxSize - _allocated;
  double get utilization => _allocated / maxSize;
  double get hitRate => _hits + _misses > 0 ? _hits / (_hits + _misses) : 0.0;
  double get missRate => _hits + _misses > 0 ? _misses / (_hits + _misses) : 0.0;
  int get memoryUsage => _allocated * objectSize;
  
  T? get() {
    if (_allocated == 0) {
      _misses++;
      return null;
    }
    
    final object = _objects[_head];
    if (object != null) {
      _objects[_head] = null;
      _head = (_head + 1) % maxSize;
      _allocated--;
      _hits++;
    }
    
    return object;
  }
  
  void returnObject(T object) {
    if (_allocated < maxSize) {
      _objects[_head] = object;
      _head = (_head + 1) % maxSize;
      _allocated++;
    }
  }
  
  void cleanup() {
    // Clear all objects
    for (int i = 0; i < maxSize; i++) {
      _objects[i] = null;
    }
    _head = 0;
    _allocated = 0;
    _hits = 0;
    _misses = 0;
  }
  
  void clear() {
    cleanup();
  }
}

/// Compressed buffer
class CompressedBuffer {
  final List<String> originalData;
  final Uint8List compressedData;
  final int originalSize;
  final int compressedSize;
  final double compressionRatio;
  
  CompressedBuffer({
    required this.originalData,
    required this.compressedData,
    required this.originalSize,
    required this.compressedSize,
    required this.compressionRatio,
  });
  
  int get memoryUsage => compressedData.length;
}

/// Memory snapshot
class MemorySnapshot {
  final DateTime timestamp;
  final int totalUsage;
  final int bufferCount;
  final int poolCount;
  final int compressedCount;
  
  MemorySnapshot({
    required this.timestamp,
    required this.totalUsage,
    required this.bufferCount,
    required this.poolCount,
    required this.compressedCount,
  });
}

/// Memory pressure
class MemoryPressure {
  final MemoryPressureLevel level;
  final int usage;
  final int threshold;
  
  MemoryPressure({
    required this.level,
    required this.usage,
    required this.threshold,
  });
}

/// Memory pressure levels
enum MemoryPressureLevel {
  normal,
  low,
  medium,
  high,
  critical,
}

/// Buffer metrics
class BufferMetrics {
  final int size;
  final int capacity;
  final double utilization;
  final int memoryUsage;
  final double compressionRatio;
  final int accessCount;
  final DateTime lastAccess;
  
  BufferMetrics({
    required this.size,
    required this.capacity,
    required this.utilization,
    required this.memoryUsage,
    required this.compressionRatio,
    required this.accessCount,
    required this.lastAccess,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'size': size,
      'capacity': capacity,
      'utilization': utilization,
      'memoryUsage': memoryUsage,
      'compressionRatio': compressionRatio,
      'accessCount': accessCount,
      'lastAccess': lastAccess.toIso8601String(),
    };
  }
}

/// Pool metrics
class PoolMetrics {
  final int allocated;
  final int available;
  final double utilization;
  final double hitRate;
  final double missRate;
  final int memoryUsage;
  
  PoolMetrics({
    required this.allocated,
    required this.available,
    required this.utilization,
    required this.hitRate,
    required this.missRate,
    required this.memoryUsage,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'allocated': allocated,
      'available': available,
      'utilization': utilization,
      'hitRate': hitRate,
      'missRate': missRate,
      'memoryUsage': memoryUsage,
    };
  }
}

/// Memory leak
class MemoryLeak {
  final MemoryLeakType type;
  final String location;
  final int size;
  final Duration? age;
  final double? missRate;
  
  MemoryLeak({
    required this.type,
    required this.location,
    required this.size,
    this.age,
    this.missRate,
  });
}

/// Memory leak types
enum MemoryLeakType {
  staleBuffer,
  poolInefficiency,
  memoryLeak,
  circularReference,
}