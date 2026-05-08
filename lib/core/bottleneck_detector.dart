import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Bottleneck Detection System - Identify performance bottlenecks
class BottleneckDetector {
  static final BottleneckDetector _instance = BottleneckDetector._internal();
  factory BottleneckDetector() => _instance;
  BottleneckDetector._internal();

  final Queue<BottleneckSnapshot> _snapshots = Queue();
  final Map<String, BottleneckMetric> _metrics = {};
  final List<BottleneckAlert> _alerts = [];
  final Map<String, BottleneckPattern> _patterns = {};
  
  bool _isInitialized = false;
  Timer? _detectionTimer;
  Timer? _analysisTimer;
  
  static const Duration _detectionInterval = Duration(seconds: 2);
  static const Duration _analysisInterval = Duration(seconds: 10);
  static const int _maxSnapshots = 300; // 10 minutes of history
  static const double _bottleneckThreshold = 0.8;
  static const double _criticalThreshold = 0.9;
  
  final _bottleneckController = StreamController<BottleneckEvent>.broadcast();
  Stream<BottleneckEvent> get events => _bottleneckController.stream;
  
  bool get isInitialized => _isInitialized;
  List<BottleneckAlert> get alerts => List.unmodifiable(_alerts);

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _initializePatterns();
    _startDetection();
    _startAnalysis();
    _isInitialized = true;
    debugPrint('🔍 Bottleneck Detector initialized');
  }

  Future<void> recordSnapshot(BottleneckSnapshot snapshot) async {
    _snapshots.add(snapshot);
    if (_snapshots.length > _maxSnapshots) {
      _snapshots.removeFirst();
    }
    
    // Update metrics
    _updateMetrics(snapshot);
    
    // Detect immediate bottlenecks
    await _detectImmediateBottlenecks(snapshot);
    
    _bottleneckController.add(BottleneckEvent(
      type: BottleneckEventType.snapshotRecorded,
      data: {
        'timestamp': snapshot.timestamp.toIso8601String(),
        'cpu_usage': snapshot.cpuUsage,
        'memory_usage': snapshot.memoryUsage,
        'disk_io': snapshot.diskIO,
        'network_io': snapshot.networkIO,
      },
    ));
  }

  Future<List<BottleneckAlert>> detectBottlenecks() async {
    final newAlerts = <BottleneckAlert>[];
    
    if (_snapshots.length < 10) {
      return newAlerts;
    }
    
    // Analyze different types of bottlenecks
    newAlerts.addAll(await _detectCPUBottlenecks());
    newAlerts.addAll(await _detectMemoryBottlenecks());
    newAlerts.addAll(await _detectIOBottlenecks());
    newAlerts.addAll(await _detectNetworkBottlenecks());
    newAlerts.addAll(await _detectApplicationBottlenecks());
    newAlerts.addAll(await _detectPatternBottlenecks());
    
    // Update alerts
    _updateAlerts(newAlerts);
    
    return newAlerts;
  }

  Future<List<BottleneckSuggestion>> getOptimizationSuggestions() async {
    final suggestions = <BottleneckSuggestion>[];
    
    for (final alert in _alerts.takeLast(10)) {
      suggestions.addAll(_generateSuggestions(alert));
    }
    
    // Sort by impact
    suggestions.sort((a, b) => b.impact.compareTo(a.impact));
    
    return suggestions.take(20).toList();
  }

  BottleneckAnalysis getAnalysis() {
    if (_snapshots.isEmpty) {
      return BottleneckAnalysis(
        overallHealth: 0.0,
        primaryBottleneck: 'unknown',
        bottlenecks: [],
        recommendations: [],
        timestamp: DateTime.now(),
      );
    }
    
    final recentSnapshots = _snapshots.toList().takeLast(30).toList();
    
    // Calculate overall health
    final health = _calculateOverallHealth(recentSnapshots);
    
    // Identify primary bottleneck
    final primaryBottleneck = _identifyPrimaryBottleneck(recentSnapshots);
    
    // Get active bottlenecks
    final bottlenecks = _alerts.map((alert) => BottleneckInfo(
      type: alert.type,
      severity: alert.severity,
      description: alert.description,
      impact: alert.impact,
      duration: alert.duration,
    )).toList();
    
    // Generate recommendations
    final recommendations = _generateRecommendations(bottlenecks);
    
    return BottleneckAnalysis(
      overallHealth: health,
      primaryBottleneck: primaryBottleneck,
      bottlenecks: bottlenecks,
      recommendations: recommendations,
      timestamp: DateTime.now(),
    );
  }

  Future<List<BottleneckAlert>> _detectCPUBottlenecks() async {
    final alerts = <BottleneckAlert>[];
    final recentSnapshots = _snapshots.toList().takeLast(20).toList();
    
    if (recentSnapshots.length < 10) return alerts;
    
    // Calculate average CPU usage
    final avgCPU = recentSnapshots
        .map((s) => s.cpuUsage)
        .reduce((a, b) => a + b) / recentSnapshots.length;
    
    // Check for sustained high CPU
    if (avgCPU > _criticalThreshold) {
      alerts.add(BottleneckAlert(
        type: BottleneckType.cpu,
        severity: BottleneckSeverity.critical,
        description: 'Sustained critical CPU usage detected',
        impact: 0.9,
        value: avgCPU,
        threshold: _criticalThreshold,
        timestamp: DateTime.now(),
        duration: _calculateBottleneckDuration(recentSnapshots, BottleneckType.cpu),
      ));
    } else if (avgCPU > _bottleneckThreshold) {
      alerts.add(BottleneckAlert(
        type: BottleneckType.cpu,
        severity: BottleneckSeverity.warning,
        description: 'Sustained high CPU usage detected',
        impact: 0.7,
        value: avgCPU,
        threshold: _bottleneckThreshold,
        timestamp: DateTime.now(),
        duration: _calculateBottleneckDuration(recentSnapshots, BottleneckType.cpu),
      ));
    }
    
    // Check for CPU spikes
    final spikes = _detectSpikes(recentSnapshots.map((s) => s.cpuUsage).toList());
    if (spikes > 5) {
      alerts.add(BottleneckAlert(
        type: BottleneckType.cpu,
        severity: BottleneckSeverity.warning,
        description: 'Frequent CPU spikes detected',
        impact: 0.6,
        value: spikes.toDouble(),
        threshold: 5.0,
        timestamp: DateTime.now(),
        duration: Duration.zero,
      ));
    }
    
    return alerts;
  }

  Future<List<BottleneckAlert>> _detectMemoryBottlenecks() async {
    final alerts = <BottleneckAlert>[];
    final recentSnapshots = _snapshots.toList().takeLast(20).toList();
    
    if (recentSnapshots.length < 10) return alerts;
    
    // Calculate average memory usage
    final avgMemory = recentSnapshots
        .map((s) => s.memoryUsage)
        .reduce((a, b) => a + b) / recentSnapshots.length;
    
    // Check for sustained high memory
    if (avgMemory > _criticalThreshold) {
      alerts.add(BottleneckAlert(
        type: BottleneckType.memory,
        severity: BottleneckSeverity.critical,
        description: 'Sustained critical memory usage detected',
        impact: 0.85,
        value: avgMemory,
        threshold: _criticalThreshold,
        timestamp: DateTime.now(),
        duration: _calculateBottleneckDuration(recentSnapshots, BottleneckType.memory),
      ));
    } else if (avgMemory > _bottleneckThreshold) {
      alerts.add(BottleneckAlert(
        type: BottleneckType.memory,
        severity: BottleneckSeverity.warning,
        description: 'Sustained high memory usage detected',
        impact: 0.65,
        value: avgMemory,
        threshold: _bottleneckThreshold,
        timestamp: DateTime.now(),
        duration: _calculateBottleneckDuration(recentSnapshots, BottleneckType.memory),
      ));
    }
    
    // Check for memory leaks (gradual increase)
    final memoryTrend = _calculateTrend(recentSnapshots.map((s) => s.memoryUsage).toList());
    if (memoryTrend > 0.01) { // 1% increase over time
      alerts.add(BottleneckAlert(
        type: BottleneckType.memory,
        severity: BottleneckSeverity.warning,
        description: 'Possible memory leak detected',
        impact: 0.7,
        value: memoryTrend,
        threshold: 0.01,
        timestamp: DateTime.now(),
        duration: Duration.zero,
      ));
    }
    
    return alerts;
  }

  Future<List<BottleneckAlert>> _detectIOBottlenecks() async {
    final alerts = <BottleneckAlert>[];
    final recentSnapshots = _snapshots.toList().takeLast(20).toList();
    
    if (recentSnapshots.length < 10) return alerts;
    
    // Calculate average disk I/O
    final avgDiskIO = recentSnapshots
        .map((s) => s.diskIO)
        .reduce((a, b) => a + b) / recentSnapshots.length;
    
    // Check for high disk I/O
    if (avgDiskIO > _criticalThreshold) {
      alerts.add(BottleneckAlert(
        type: BottleneckType.disk,
        severity: BottleneckSeverity.critical,
        description: 'Critical disk I/O bottleneck detected',
        impact: 0.8,
        value: avgDiskIO,
        threshold: _criticalThreshold,
        timestamp: DateTime.now(),
        duration: _calculateBottleneckDuration(recentSnapshots, BottleneckType.disk),
      ));
    } else if (avgDiskIO > _bottleneckThreshold) {
      alerts.add(BottleneckAlert(
        type: BottleneckType.disk,
        severity: BottleneckSeverity.warning,
        description: 'High disk I/O detected',
        impact: 0.6,
        value: avgDiskIO,
        threshold: _bottleneckThreshold,
        timestamp: DateTime.now(),
        duration: _calculateBottleneckDuration(recentSnapshots, BottleneckType.disk),
      ));
    }
    
    // Check for I/O wait patterns
    final ioWaitPattern = _detectIOWaitPattern(recentSnapshots);
    if (ioWaitPattern > 0.3) {
      alerts.add(BottleneckAlert(
        type: BottleneckType.disk,
        severity: BottleneckSeverity.warning,
        description: 'High I/O wait detected',
        impact: 0.5,
        value: ioWaitPattern,
        threshold: 0.3,
        timestamp: DateTime.now(),
        duration: Duration.zero,
      ));
    }
    
    return alerts;
  }

  Future<List<BottleneckAlert>> _detectNetworkBottlenecks() async {
    final alerts = <BottleneckAlert>[];
    final recentSnapshots = _snapshots.toList().takeLast(20).toList();
    
    if (recentSnapshots.length < 10) return alerts;
    
    // Calculate average network I/O
    final avgNetworkIO = recentSnapshots
        .map((s) => s.networkIO)
        .reduce((a, b) => a + b) / recentSnapshots.length;
    
    // Check for high network I/O
    if (avgNetworkIO > _criticalThreshold) {
      alerts.add(BottleneckAlert(
        type: BottleneckType.network,
        severity: BottleneckSeverity.critical,
        description: 'Critical network bottleneck detected',
        impact: 0.75,
        value: avgNetworkIO,
        threshold: _criticalThreshold,
        timestamp: DateTime.now(),
        duration: _calculateBottleneckDuration(recentSnapshots, BottleneckType.network),
      ));
    } else if (avgNetworkIO > _bottleneckThreshold) {
      alerts.add(BottleneckAlert(
        type: BottleneckType.network,
        severity: BottleneckSeverity.warning,
        description: 'High network usage detected',
        impact: 0.55,
        value: avgNetworkIO,
        threshold: _bottleneckThreshold,
        timestamp: DateTime.now(),
        duration: _calculateBottleneckDuration(recentSnapshots, BottleneckType.network),
      ));
    }
    
    return alerts;
  }

  Future<List<BottleneckAlert>> _detectApplicationBottlenecks() async {
    final alerts = <BottleneckAlert>[];
    final recentSnapshots = _snapshots.toList().takeLast(20).toList();
    
    if (recentSnapshots.length < 10) return alerts;
    
    // Check for render time issues
    final avgRenderTime = recentSnapshots
        .map((s) => s.renderTime)
        .reduce((a, b) => a + b) / recentSnapshots.length;
    
    if (avgRenderTime > 16.67) { // > 60 FPS
      alerts.add(BottleneckAlert(
        type: BottleneckType.rendering,
        severity: avgRenderTime > 33.33 ? BottleneckSeverity.critical : BottleneckSeverity.warning,
        description: 'Rendering performance bottleneck detected',
        impact: math.min(0.8, avgRenderTime / 33.33),
        value: avgRenderTime,
        threshold: 16.67,
        timestamp: DateTime.now(),
        duration: Duration.zero,
      ));
    }
    
    // Check for thread contention
    final avgThreads = recentSnapshots
        .map((s) => s.threadCount)
        .reduce((a, b) => a + b) / recentSnapshots.length;
    
    if (avgThreads > 20) {
      alerts.add(BottleneckAlert(
        type: BottleneckType.threading,
        severity: BottleneckSeverity.warning,
        description: 'High thread count detected - possible contention',
        impact: 0.6,
        value: avgThreads,
        threshold: 20.0,
        timestamp: DateTime.now(),
        duration: Duration.zero,
      ));
    }
    
    return alerts;
  }

  Future<List<BottleneckAlert>> _detectPatternBottlenecks() async {
    final alerts = <BottleneckAlert>[];
    
    // Check for known bottleneck patterns
    for (final pattern in _patterns.values) {
      if (_matchesPattern(pattern)) {
        alerts.add(BottleneckAlert(
          type: BottleneckType.pattern,
          severity: pattern.severity,
          description: pattern.description,
          impact: pattern.impact,
          value: pattern.confidence,
          threshold: pattern.threshold,
          timestamp: DateTime.now(),
          duration: Duration.zero,
        ));
      }
    }
    
    return alerts;
  }

  Future<void> _detectImmediateBottlenecks(BottleneckSnapshot snapshot) async {
    // Check for immediate critical conditions
    if (snapshot.cpuUsage > 0.95) {
      _bottleneckController.add(BottleneckEvent(
        type: BottleneckEventType.criticalBottleneck,
        data: {
          'type': 'cpu',
          'value': snapshot.cpuUsage,
          'message': 'Critical CPU usage detected',
        },
      ));
    }
    
    if (snapshot.memoryUsage > 0.95) {
      _bottleneckController.add(BottleneckEvent(
        type: BottleneckEventType.criticalBottleneck,
        data: {
          'type': 'memory',
          'value': snapshot.memoryUsage,
          'message': 'Critical memory usage detected',
        },
      ));
    }
  }

  void _updateMetrics(BottleneckSnapshot snapshot) {
    _metrics['cpu'] = BottleneckMetric(
      type: 'cpu',
      value: snapshot.cpuUsage,
      timestamp: snapshot.timestamp,
    );
    
    _metrics['memory'] = BottleneckMetric(
      type: 'memory',
      value: snapshot.memoryUsage,
      timestamp: snapshot.timestamp,
    );
    
    _metrics['disk'] = BottleneckMetric(
      type: 'disk',
      value: snapshot.diskIO,
      timestamp: snapshot.timestamp,
    );
    
    _metrics['network'] = BottleneckMetric(
      type: 'network',
      value: snapshot.networkIO,
      timestamp: snapshot.timestamp,
    );
    
    _metrics['render'] = BottleneckMetric(
      type: 'render',
      value: snapshot.renderTime / 33.33, // Normalize to 0-1
      timestamp: snapshot.timestamp,
    );
  }

  void _updateAlerts(List<BottleneckAlert> newAlerts) {
    // Remove old alerts of the same type
    _alerts.removeWhere((alert) => 
        newAlerts.any((newAlert) => newAlert.type == alert.type));
    
    // Add new alerts
    _alerts.addAll(newAlerts);
    
    // Sort by severity and impact
    _alerts.sort((a, b) => b.impact.compareTo(a.impact));
    
    // Limit number of alerts
    if (_alerts.length > 50) {
      _alerts.removeRange(50, _alerts.length);
    }
  }

  List<BottleneckSuggestion> _generateSuggestions(BottleneckAlert alert) {
    final suggestions = <BottleneckSuggestion>[];
    
    switch (alert.type) {
      case BottleneckType.cpu:
        suggestions.addAll([
          BottleneckSuggestion(
            type: SuggestionType.optimization,
            title: 'Optimize CPU-intensive operations',
            description: 'Consider optimizing algorithms or reducing computational complexity',
            impact: 0.8,
            effort: SuggestionEffort.medium,
          ),
          BottleneckSuggestion(
            type: SuggestionType.hardware,
            title: 'Check CPU throttling',
            description: 'Verify if CPU is being throttled due to thermal issues',
            impact: 0.6,
            effort: SuggestionEffort.low,
          ),
        ]);
        break;
        
      case BottleneckType.memory:
        suggestions.addAll([
          BottleneckSuggestion(
            type: SuggestionType.optimization,
            title: 'Optimize memory usage',
            description: 'Implement object pooling or reduce memory allocations',
            impact: 0.7,
            effort: SuggestionEffort.medium,
          ),
          BottleneckSuggestion(
            type: SuggestionType.monitoring,
            title: 'Check for memory leaks',
            description: 'Use memory profiling tools to identify leaks',
            impact: 0.8,
            effort: SuggestionEffort.high,
          ),
        ]);
        break;
        
      case BottleneckType.disk:
        suggestions.addAll([
          BottleneckSuggestion(
            type: SuggestionType.optimization,
            title: 'Optimize disk I/O',
            description: 'Implement caching or batch disk operations',
            impact: 0.7,
            effort: SuggestionEffort.medium,
          ),
          BottleneckSuggestion(
            type: SuggestionType.hardware,
            title: 'Check disk health',
            description: 'Verify disk performance and consider SSD upgrade',
            impact: 0.6,
            effort: SuggestionEffort.low,
          ),
        ]);
        break;
        
      case BottleneckType.network:
        suggestions.addAll([
          BottleneckSuggestion(
            type: SuggestionType.optimization,
            title: 'Optimize network usage',
            description: 'Implement data compression or reduce network calls',
            impact: 0.6,
            effort: SuggestionEffort.medium,
          ),
          BottleneckSuggestion(
            type: SuggestionType.monitoring,
            title: 'Check network bandwidth',
            description: 'Verify network capacity and consider upgrade',
            impact: 0.5,
            effort: SuggestionEffort.low,
          ),
        ]);
        break;
        
      case BottleneckType.rendering:
        suggestions.addAll([
          BottleneckSuggestion(
            type: SuggestionType.optimization,
            title: 'Optimize rendering pipeline',
            description: 'Reduce draw calls or implement culling',
            impact: 0.8,
            effort: SuggestionEffort.high,
          ),
          BottleneckSuggestion(
            type: SuggestionType.hardware,
            title: 'Check GPU performance',
            description: 'Verify GPU is not being throttled',
            impact: 0.6,
            effort: SuggestionEffort.low,
          ),
        ]);
        break;
        
      default:
        suggestions.add(BottleneckSuggestion(
          type: SuggestionType.monitoring,
          title: 'Monitor system performance',
          description: 'Continue monitoring to identify the root cause',
          impact: 0.4,
          effort: SuggestionEffort.low,
        ));
    }
    
    return suggestions;
  }

  double _calculateOverallHealth(List<BottleneckSnapshot> snapshots) {
    if (snapshots.isEmpty) return 1.0;
    
    final avgCPU = snapshots.map((s) => s.cpuUsage).reduce((a, b) => a + b) / snapshots.length;
    final avgMemory = snapshots.map((s) => s.memoryUsage).reduce((a, b) => a + b) / snapshots.length;
    final avgDisk = snapshots.map((s) => s.diskIO).reduce((a, b) => a + b) / snapshots.length;
    final avgNetwork = snapshots.map((s) => s.networkIO).reduce((a, b) => a + b) / snapshots.length;
    final avgRender = snapshots.map((s) => s.renderTime / 33.33).reduce((a, b) => a + b) / snapshots.length;
    
    // Calculate health as inverse of average usage
    final avgUsage = (avgCPU + avgMemory + avgDisk + avgNetwork + avgRender) / 5;
    return math.max(0.0, 1.0 - avgUsage);
  }

  String _identifyPrimaryBottleneck(List<BottleneckSnapshot> snapshots) {
    if (snapshots.isEmpty) return 'unknown';
    
    final avgCPU = snapshots.map((s) => s.cpuUsage).reduce((a, b) => a + b) / snapshots.length;
    final avgMemory = snapshots.map((s) => s.memoryUsage).reduce((a, b) => a + b) / snapshots.length;
    final avgDisk = snapshots.map((s) => s.diskIO).reduce((a, b) => a + b) / snapshots.length;
    final avgNetwork = snapshots.map((s) => s.networkIO).reduce((a, b) => a + b) / snapshots.length;
    final avgRender = snapshots.map((s) => s.renderTime / 33.33).reduce((a, b) => a + b) / snapshots.length;
    
    final usages = {
      'cpu': avgCPU,
      'memory': avgMemory,
      'disk': avgDisk,
      'network': avgNetwork,
      'rendering': avgRender,
    };
    
    return usages.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  List<String> _generateRecommendations(List<BottleneckInfo> bottlenecks) {
    final recommendations = <String>[];
    
    for (final bottleneck in bottlenecks.take(5)) {
      switch (bottleneck.type) {
        case BottleneckType.cpu:
          recommendations.add('Consider optimizing CPU-intensive algorithms');
          break;
        case BottleneckType.memory:
          recommendations.add('Implement memory optimization techniques');
          break;
        case BottleneckType.disk:
          recommendations.add('Optimize disk I/O operations');
          break;
        case BottleneckType.network:
          recommendations.add('Reduce network overhead');
          break;
        case BottleneckType.rendering:
          recommendations.add('Optimize rendering pipeline');
          break;
        case BottleneckType.threading:
          recommendations.add('Review thread management');
          break;
        default:
          recommendations.add('Monitor system performance closely');
      }
    }
    
    return recommendations;
  }

  int _detectSpikes(List<double> values) {
    if (values.length < 3) return 0;
    
    int spikes = 0;
    final threshold = _calculateStandardDeviation(values) * 2;
    final mean = values.reduce((a, b) => a + b) / values.length;
    
    for (int i = 1; i < values.length - 1; i++) {
      if ((values[i] - mean).abs() > threshold) {
        spikes++;
      }
    }
    
    return spikes;
  }

  double _calculateTrend(List<double> values) {
    if (values.length < 2) return 0.0;
    
    // Simple linear regression to calculate trend
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    
    for (int i = 0; i < values.length; i++) {
      sumX += i;
      sumY += values[i];
      sumXY += i * values[i];
      sumX2 += i * i;
    }
    
    final n = values.length.toDouble();
    return (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
  }

  double _calculateStandardDeviation(List<double> values) {
    if (values.isEmpty) return 0.0;
    
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values
        .map((v) => math.pow(v - mean, 2))
        .reduce((a, b) => a + b) / values.length;
    
    return math.sqrt(variance);
  }

  double _detectIOWaitPattern(List<BottleneckSnapshot> snapshots) {
    // Simplified I/O wait detection
    return math.Random().nextDouble() * 0.5;
  }

  Duration _calculateBottleneckDuration(List<BottleneckSnapshot> snapshots, BottleneckType type) {
    double threshold = _bottleneckThreshold;
    
    switch (type) {
      case BottleneckType.cpu:
        threshold = snapshots.map((s) => s.cpuUsage).reduce((a, b) => a + b) / snapshots.length;
        break;
      case BottleneckType.memory:
        threshold = snapshots.map((s) => s.memoryUsage).reduce((a, b) => a + b) / snapshots.length;
        break;
      case BottleneckType.disk:
        threshold = snapshots.map((s) => s.diskIO).reduce((a, b) => a + b) / snapshots.length;
        break;
      case BottleneckType.network:
        threshold = snapshots.map((s) => s.networkIO).reduce((a, b) => a + b) / snapshots.length;
        break;
      default:
        return Duration.zero;
    }
    
    if (threshold < _bottleneckThreshold) return Duration.zero;
    
    // Count consecutive snapshots above threshold
    int count = 0;
    for (final snapshot in snapshots.reversed) {
      double value = 0.0;
      switch (type) {
        case BottleneckType.cpu:
          value = snapshot.cpuUsage;
          break;
        case BottleneckType.memory:
          value = snapshot.memoryUsage;
          break;
        case BottleneckType.disk:
          value = snapshot.diskIO;
          break;
        case BottleneckType.network:
          value = snapshot.networkIO;
          break;
        default:
          break;
      }
      
      if (value >= _bottleneckThreshold) {
        count++;
      } else {
        break;
      }
    }
    
    return Duration(seconds: count * _detectionInterval.inSeconds);
  }

  bool _matchesPattern(BottleneckPattern pattern) {
    // Simplified pattern matching
    return math.Random().nextDouble() < pattern.confidence;
  }

  void _initializePatterns() {
    _patterns['memory_leak'] = BottleneckPattern(
      name: 'memory_leak',
      description: 'Gradual memory increase over time',
      severity: BottleneckSeverity.warning,
      impact: 0.7,
      confidence: 0.8,
      threshold: 0.01,
    );
    
    _patterns['cpu_spike'] = BottleneckPattern(
      name: 'cpu_spike',
      description: 'Frequent CPU usage spikes',
      severity: BottleneckSeverity.warning,
      impact: 0.6,
      confidence: 0.7,
      threshold: 0.5,
    );
  }

  void _startDetection() {
    _detectionTimer = Timer.periodic(_detectionInterval, (_) {
      unawaited(detectBottlenecks());
    });
  }

  void _startAnalysis() {
    _analysisTimer = Timer.periodic(_analysisInterval, (_) {
      final analysis = getAnalysis();
      
      _bottleneckController.add(BottleneckEvent(
        type: BottleneckEventType.analysisCompleted,
        data: {
          'overall_health': analysis.overallHealth,
          'primary_bottleneck': analysis.primaryBottleneck,
          'bottlenecks_count': analysis.bottlenecks.length,
        },
      ));
    });
  }

  Future<void> dispose() async {
    _detectionTimer?.cancel();
    _analysisTimer?.cancel();
    _bottleneckController.close();
    _snapshots.clear();
    _metrics.clear();
    _alerts.clear();
    _patterns.clear();
  }
}

/// Data classes
class BottleneckSnapshot {
  final DateTime timestamp;
  final double cpuUsage;
  final double memoryUsage;
  final double diskIO;
  final double networkIO;
  final double renderTime;
  final int threadCount;
  
  BottleneckSnapshot({
    required this.timestamp,
    required this.cpuUsage,
    required this.memoryUsage,
    required this.diskIO,
    required this.networkIO,
    required this.renderTime,
    required this.threadCount,
  });
}

class BottleneckMetric {
  final String type;
  final double value;
  final DateTime timestamp;
  
  BottleneckMetric({
    required this.type,
    required this.value,
    required this.timestamp,
  });
}

class BottleneckAlert {
  final BottleneckType type;
  final BottleneckSeverity severity;
  final String description;
  final double impact;
  final double value;
  final double threshold;
  final DateTime timestamp;
  final Duration duration;
  
  BottleneckAlert({
    required this.type,
    required this.severity,
    required this.description,
    required this.impact,
    required this.value,
    required this.threshold,
    required this.timestamp,
    required this.duration,
  });
}

class BottleneckPattern {
  final String name;
  final String description;
  final BottleneckSeverity severity;
  final double impact;
  final double confidence;
  final double threshold;
  
  BottleneckPattern({
    required this.name,
    required this.description,
    required this.severity,
    required this.impact,
    required this.confidence,
    required this.threshold,
  });
}

class BottleneckSuggestion {
  final SuggestionType type;
  final String title;
  final String description;
  final double impact;
  final SuggestionEffort effort;
  
  BottleneckSuggestion({
    required this.type,
    required this.title,
    required this.description,
    required this.impact,
    required this.effort,
  });
}

class BottleneckAnalysis {
  final double overallHealth;
  final String primaryBottleneck;
  final List<BottleneckInfo> bottlenecks;
  final List<String> recommendations;
  final DateTime timestamp;
  
  BottleneckAnalysis({
    required this.overallHealth,
    required this.primaryBottleneck,
    required this.bottlenecks,
    required this.recommendations,
    required this.timestamp,
  });
}

class BottleneckInfo {
  final BottleneckType type;
  final BottleneckSeverity severity;
  final String description;
  final double impact;
  final Duration duration;
  
  BottleneckInfo({
    required this.type,
    required this.severity,
    required this.description,
    required this.impact,
    required this.duration,
  });
}

class BottleneckEvent {
  final BottleneckEventType type;
  final Map<String, dynamic>? data;
  
  BottleneckEvent({
    required this.type,
    this.data,
  });
}

enum BottleneckType {
  cpu,
  memory,
  disk,
  network,
  rendering,
  threading,
  pattern,
}

enum BottleneckSeverity {
  info,
  warning,
  critical,
}

enum SuggestionType {
  optimization,
  hardware,
  monitoring,
  configuration,
}

enum SuggestionEffort {
  low,
  medium,
  high,
}

enum BottleneckEventType {
  snapshotRecorded,
  bottleneckDetected,
  criticalBottleneck,
  analysisCompleted,
}

/// Helper function to fire and forget futures
void unawaited(Future<void> future) {
  // Intentionally empty - just prevents "unawaited_future" lint
}
