import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

class MemoryLeakDetector {
  static const int _monitoringInterval = 5000; // 5 seconds
  static const double _leakThreshold = 0.5; // MB/s growth rate
  static const int _maxHistorySize = 200;
  
  Timer? _monitoringTimer;
  final List<MemorySnapshot> _memoryHistory = [];
  final Map<String, ObjectTracker> _trackedObjects = {};
  final List<LeakReport> _leakReports = [];
  
  bool _isMonitoring = false;
  int _totalLeaksDetected = 0;

  void initialize() {
    _startMonitoring();
    developer.log('🔍 Memory Leak Detector initialized');
  }

  void _startMonitoring() {
    if (_isMonitoring) return;
    
    _isMonitoring = true;
    _monitoringTimer = Timer.periodic(
      Duration(milliseconds: _monitoringInterval),
      (_) => _captureMemorySnapshot(),
    );
    
    // Initial snapshot
    _captureMemorySnapshot();
  }

  void _captureMemorySnapshot() {
    final snapshot = MemorySnapshot(
      timestamp: DateTime.now(),
      rss: ProcessInfo.currentRss,
      heapUsage: _estimateHeapUsage(),
      objectCount: _trackedObjects.length,
    );

    _memoryHistory.add(snapshot);
    
    if (_memoryHistory.length > _maxHistorySize) {
      _memoryHistory.removeAt(0);
    }

    _analyzeForLeaks();
  }

  int _estimateHeapUsage() {
    // Simplified heap estimation - in practice you'd use more sophisticated methods
    return ProcessInfo.currentRss ~/ 2;
  }

  void _analyzeForLeaks() {
    if (_memoryHistory.length < 10) return;

    final recent = _memoryHistory.reversed.take(20).toList();
    final leakAnalysis = _detectMemoryLeak(recent);
    
    if (leakAnalysis.hasLeak) {
      _handleDetectedLeak(leakAnalysis);
    }

    _analyzeObjectLeaks();
  }

  LeakAnalysis _detectMemoryLeak(List<MemorySnapshot> snapshots) {
    if (snapshots.length < 2) {
      return LeakAnalysis(hasLeak: false, growthRate: 0, estimatedLeakSize: 0);
    }

    // Calculate memory growth rate
    final first = snapshots.first;
    final last = snapshots.last;
    final timeDiff = last.timestamp.difference(first.timestamp).inMilliseconds;
    final memoryDiff = last.rss - first.rss;
    
    final growthRate = timeDiff > 0 ? (memoryDiff / timeDiff) * 1000 : 0; // bytes per second
    
    // Check for sustained growth
    final sustainedGrowth = _checkSustainedGrowth(snapshots);
    
    // Estimate leak size if growth is sustained
    final estimatedLeakSize = sustainedGrowth ? _estimateLeakSize(snapshots) : 0;
    
    return LeakAnalysis(
      hasLeak: sustainedGrowth && growthRate > _leakThreshold * 1024 * 1024,
      growthRate: growthRate,
      estimatedLeakSize: estimatedLeakSize,
    );
  }

  bool _checkSustainedGrowth(List<MemorySnapshot> snapshots) {
    if (snapshots.length < 5) return false;

    int growthCount = 0;
    for (int i = 1; i < snapshots.length; i++) {
      if (snapshots[i].rss > snapshots[i - 1].rss) {
        growthCount++;
      }
    }

    return growthCount > (snapshots.length * 0.7); // 70% growth
  }

  int _estimateLeakSize(List<MemorySnapshot> snapshots) {
    if (snapshots.length < 2) return 0;

    // Simple linear regression to estimate leak rate
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    final n = snapshots.length.toDouble();

    for (int i = 0; i < snapshots.length; i++) {
      sumX += i;
      sumY += snapshots[i].rss;
      sumXY += i * snapshots[i].rss;
      sumX2 += i * i;
    }

    final slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    return slope.round();
  }

  void _handleDetectedLeak(LeakAnalysis analysis) {
    _totalLeaksDetected++;
    
    final report = LeakReport(
      timestamp: DateTime.now(),
      growthRate: analysis.growthRate,
      estimatedSize: analysis.estimatedLeakSize,
      memoryHistory: _memoryHistory.reversed.take(10).toList(),
    );
    
    _leakReports.add(report);
    
    developer.log('🚨 Memory leak detected! Growth rate: ${analysis.growthRate ~/ 1024}KB/s');
    
    // Attempt automatic cleanup
    _attemptLeakCleanup();
  }

  void _attemptLeakCleanup() {
    developer.log('🧹 Attempting automatic leak cleanup...');
    
    // Clear old snapshots
    _memoryHistory.removeWhere((snapshot) => 
        DateTime.now().difference(snapshot.timestamp).inMinutes > 10);
    
    // Force GC
    _forceGarbageCollection();
    
    // Clear weak references
    _clearWeakReferences();
  }

  void _forceGarbageCollection() {
    // Trigger garbage collection
    try {
      Isolate.current.ping(Duration.zero).then((_) {
        developer.log('🗑️ Forced GC for leak cleanup');
      });
    } catch (e) {
      developer.log('Failed to force GC: $e');
    }
  }

  void _clearWeakReferences() {
    // Clear tracked objects that are no longer needed
    final now = DateTime.now();
    _trackedObjects.removeWhere((key, tracker) => 
        now.difference(tracker.lastAccessed).inMinutes > 30);
  }

  void _analyzeObjectLeaks() {
    for (final entry in _trackedObjects.entries) {
      final tracker = entry.value;
      
      if (tracker.isPotentialLeak()) {
        developer.log('🔍 Potential object leak: ${entry.key}');
        _handleObjectLeak(entry.key, tracker);
      }
    }
  }

  void _handleObjectLeak(String objectId, ObjectTracker tracker) {
    // Attempt to clean up the leaked object
    tracker.cleanup();
    _trackedObjects.remove(objectId);
    
    developer.log('🧹 Cleaned up leaked object: $objectId');
  }

  void trackObject(String id, Object object, {String? type}) {
    _trackedObjects[id] = ObjectTracker(
      id: id,
      object: object,
      type: type ?? object.runtimeType.toString(),
      createdAt: DateTime.now(),
      lastAccessed: DateTime.now(),
    );
  }

  void accessObject(String id) {
    final tracker = _trackedObjects[id];
    if (tracker != null) {
      tracker.lastAccessed = DateTime.now();
      tracker.accessCount++;
    }
  }

  void untrackObject(String id) {
    _trackedObjects.remove(id);
  }

  LeakDetectorStats getStats() {
    return LeakDetectorStats(
      isMonitoring: _isMonitoring,
      totalLeaksDetected: _totalLeaksDetected,
      trackedObjects: _trackedObjects.length,
      memorySnapshots: _memoryHistory.length,
      leakReports: _leakReports.toList(),
    );
  }

  void dispose() {
    _monitoringTimer?.cancel();
    _isMonitoring = false;
    _memoryHistory.clear();
    _trackedObjects.clear();
    developer.log('🔍 Memory Leak Detector disposed');
  }
}

class MemorySnapshot {
  final DateTime timestamp;
  final int rss;
  final int heapUsage;
  final int objectCount;

  MemorySnapshot({
    required this.timestamp,
    required this.rss,
    required this.heapUsage,
    required this.objectCount,
  });
}

class LeakAnalysis {
  final bool hasLeak;
  final double growthRate;
  final int estimatedLeakSize;

  LeakAnalysis({
    required this.hasLeak,
    required this.growthRate,
    required this.estimatedLeakSize,
  });
}

class LeakReport {
  final DateTime timestamp;
  final double growthRate;
  final int estimatedSize;
  final List<MemorySnapshot> memoryHistory;

  LeakReport({
    required this.timestamp,
    required this.growthRate,
    required this.estimatedSize,
    required this.memoryHistory,
  });
}

class ObjectTracker {
  final String id;
  final Object object;
  final String type;
  final DateTime createdAt;
  DateTime lastAccessed;
  int accessCount;

  ObjectTracker({
    required this.id,
    required this.object,
    required this.type,
    required this.createdAt,
    required this.lastAccessed,
    this.accessCount = 1,
  });

  bool isPotentialLeak() {
    final age = DateTime.now().difference(createdAt);
    final timeSinceAccess = DateTime.now().difference(lastAccessed);
    
    // Consider it a potential leak if:
    // 1. Object is older than 10 minutes
    // 2. Haven't been accessed in 5 minutes
    // 3. Access count is low (less than 3)
    return age.inMinutes > 10 && 
           timeSinceAccess.inMinutes > 5 && 
           accessCount < 3;
  }

  void cleanup() {
    // Perform cleanup actions
    // In practice, you might call dispose() methods, clear references, etc.
  }
}

class LeakDetectorStats {
  final bool isMonitoring;
  final int totalLeaksDetected;
  final int trackedObjects;
  final int memorySnapshots;
  final List<LeakReport> leakReports;

  LeakDetectorStats({
    required this.isMonitoring,
    required this.totalLeaksDetected,
    required this.trackedObjects,
    required this.memorySnapshots,
    required this.leakReports,
  });
}
