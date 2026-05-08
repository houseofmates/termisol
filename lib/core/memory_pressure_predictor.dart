import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Memory Pressure Prediction System - Pre-emptive memory optimization
class MemoryPressurePredictor {
  static final MemoryPressurePredictor _instance = MemoryPressurePredictor._internal();
  factory MemoryPressurePredictor() => _instance;
  MemoryPressurePredictor._internal();

  final Queue<MemorySnapshot> _memoryHistory = Queue();
  final Map<String, MemoryPattern> _patterns = {};
  final List<MemoryPrediction> _predictions = [];
  
  bool _isInitialized = false;
  Timer? _monitoringTimer;
  Timer? _predictionTimer;
  
  static const Duration _monitoringInterval = Duration(seconds: 2);
  static const Duration _predictionInterval = Duration(seconds: 5);
  static const int _maxHistory = 300; // 10 minutes of history
  static const int _predictionWindow = 60; // Predict 60 seconds ahead
  static const double _pressureThreshold = 0.8;
  static const double _criticalThreshold = 0.9;
  
  final _pressureController = StreamController<MemoryPressureEvent>.broadcast();
  Stream<MemoryPressureEvent> get events => _pressureController.stream;
  
  bool get isInitialized => _isInitialized;
  MemoryPressureLevel get currentPressure => _calculateCurrentPressure();

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _startMonitoring();
    _startPrediction();
    _isInitialized = true;
    debugPrint('🧠 Memory Pressure Predictor initialized');
  }

  Future<MemoryPrediction> predictMemoryPressure({int secondsAhead = 60}) async {
    if (_memoryHistory.length < 10) {
      return MemoryPrediction(
        timestamp: DateTime.now().add(Duration(seconds: secondsAhead)),
        predictedUsage: _getCurrentMemoryUsage(),
        confidence: 0.1,
        pressureLevel: MemoryPressureLevel.normal,
        recommendations: ['Insufficient data for accurate prediction'],
      );
    }

    // Use multiple prediction models
    final linearPrediction = _linearRegressionPredict(secondsAhead);
    final trendPrediction = _trendAnalysisPredict(secondsAhead);
    final patternPrediction = _patternBasedPredict(secondsAhead);
    
    // Ensemble predictions
    final ensemblePrediction = _ensemblePredictions([
      linearPrediction,
      trendPrediction,
      patternPrediction,
    ]);
    
    // Generate recommendations
    final recommendations = _generateRecommendations(ensemblePrediction);
    
    final prediction = MemoryPrediction(
      timestamp: DateTime.now().add(Duration(seconds: secondsAhead)),
      predictedUsage: ensemblePrediction.usage,
      confidence: ensemblePrediction.confidence,
      pressureLevel: _determinePressureLevel(ensemblePrediction.usage),
      recommendations: recommendations,
    );
    
    _predictions.add(prediction);
    if (_predictions.length > 100) {
      _predictions.removeAt(0);
    }
    
    _pressureController.add(MemoryPressureEvent(
      type: MemoryPressureEventType.predictionGenerated,
      data: {
        'predicted_usage': ensemblePrediction.usage,
        'confidence': ensemblePrediction.confidence,
        'pressure_level': prediction.pressureLevel.toString(),
      },
    ));
    
    return prediction;
  }

  void recordMemorySnapshot(MemorySnapshot snapshot) {
    _memoryHistory.add(snapshot);
    if (_memoryHistory.length > _maxHistory) {
      _memoryHistory.removeFirst();
    }
    
    // Check for immediate pressure
    final currentLevel = _calculateCurrentPressure();
    if (currentLevel == MemoryPressureLevel.critical) {
      _handleCriticalPressure();
    } else if (currentLevel == MemoryPressureLevel.high) {
      _handleHighPressure();
    }
    
    _pressureController.add(MemoryPressureEvent(
      type: MemoryPressureEventType.snapshotRecorded,
      data: {
        'total_memory': snapshot.totalMemory,
        'used_memory': snapshot.usedMemory,
        'pressure_level': currentLevel.toString(),
      },
    ));
  }

  List<MemoryOptimizationAction> getOptimizationActions() {
    final actions = <MemoryOptimizationAction>[];
    final currentUsage = _getCurrentMemoryUsage();
    
    if (currentUsage > _criticalThreshold) {
      actions.addAll(_getCriticalActions());
    } else if (currentUsage > _pressureThreshold) {
      actions.addAll(_getHighPressureActions());
    } else {
      actions.addAll(_getPreventiveActions());
    }
    
    return actions;
  }

  PredictionEnsemble _linearRegressionPredict(int secondsAhead) {
    if (_memoryHistory.length < 2) {
      return PredictionEnsemble(usage: _getCurrentMemoryUsage(), confidence: 0.1);
    }
    
    final recentSnapshots = _memoryHistory.toList().takeLast(30).toList();
    final n = recentSnapshots.length;
    
    // Calculate linear regression
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    
    for (int i = 0; i < n; i++) {
      final x = i.toDouble();
      final y = recentSnapshots[i].memoryUsage;
      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumX2 += x * x;
    }
    
    final slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    final intercept = (sumY - slope * sumX) / n;
    
    // Predict future value
    final futureX = n + (secondsAhead / _monitoringInterval.inSeconds);
    final predictedUsage = slope * futureX + intercept;
    
    // Calculate confidence based on R²
    final confidence = _calculateRegressionConfidence(recentSnapshots, slope, intercept);
    
    return PredictionEnsemble(
      usage: math.max(0.0, math.min(1.0, predictedUsage)),
      confidence: confidence,
    );
  }

  PredictionEnsemble _trendAnalysisPredict(int secondsAhead) {
    if (_memoryHistory.length < 5) {
      return PredictionEnsemble(usage: _getCurrentMemoryUsage(), confidence: 0.1);
    }
    
    final recentSnapshots = _memoryHistory.toList().takeLast(20).toList();
    
    // Calculate moving averages
    final shortTermMA = _calculateMovingAverage(recentSnapshots.takeLast(5).toList());
    final mediumTermMA = _calculateMovingAverage(recentSnapshots.takeLast(10).toList());
    final longTermMA = _calculateMovingAverage(recentSnapshots);
    
    // Determine trend
    final shortTermTrend = shortTermMA - mediumTermMA;
    final mediumTermTrend = mediumTermMA - longTermMA;
    
    // Extrapolate trend
    double trendMultiplier = 1.0;
    if (shortTermTrend > 0.01) trendMultiplier = 1.1;
    if (shortTermTrend > 0.05) trendMultiplier = 1.2;
    if (mediumTermTrend > 0.02) trendMultiplier = 1.15;
    
    final predictedUsage = _getCurrentMemoryUsage() * trendMultiplier;
    final confidence = math.max(0.2, 1.0 - (shortTermTrend.abs() + mediumTermTrend.abs()));
    
    return PredictionEnsemble(
      usage: math.max(0.0, math.min(1.0, predictedUsage)),
      confidence: confidence,
    );
  }

  PredictionEnsemble _patternBasedPredict(int secondsAhead) {
    final currentHour = DateTime.now().hour;
    final currentDay = DateTime.now().weekday;
    final patternKey = '${currentDay}_$currentHour';
    
    final pattern = _patterns[patternKey];
    if (pattern == null) {
      return PredictionEnsemble(usage: _getCurrentMemoryUsage(), confidence: 0.3);
    }
    
    // Use pattern to predict
    final predictedUsage = pattern.averageUsage + (pattern.trend * secondsAhead / 3600.0);
    final confidence = pattern.confidence;
    
    return PredictionEnsemble(
      usage: math.max(0.0, math.min(1.0, predictedUsage)),
      confidence: confidence,
    );
  }

  PredictionEnsemble _ensemblePredictions(List<PredictionEnsemble> predictions) {
    // Weighted average based on confidence
    double totalWeight = 0;
    double weightedSum = 0;
    
    for (final prediction in predictions) {
      final weight = prediction.confidence;
      weightedSum += prediction.usage * weight;
      totalWeight += weight;
    }
    
    final ensembleUsage = totalWeight > 0 ? weightedSum / totalWeight : _getCurrentMemoryUsage();
    final ensembleConfidence = totalWeight / predictions.length;
    
    return PredictionEnsemble(
      usage: ensembleUsage,
      confidence: ensembleConfidence,
    );
  }

  List<String> _generateRecommendations(PredictionEnsemble prediction) {
    final recommendations = <String>[];
    
    if (prediction.usage > _criticalThreshold) {
      recommendations.addAll([
        'Immediate memory cleanup required',
        'Close unnecessary applications',
        'Clear caches and temporary files',
        'Restart memory-intensive services',
      ]);
    } else if (prediction.usage > _pressureThreshold) {
      recommendations.addAll([
        'Pre-emptive memory optimization recommended',
        'Clear unused object pools',
        'Reduce buffer sizes',
        'Enable aggressive garbage collection',
      ]);
    } else if (prediction.usage > 0.6) {
      recommendations.addAll([
        'Monitor memory usage closely',
        'Consider preventive cleanup',
        'Optimize memory allocations',
      ]);
    }
    
    return recommendations;
  }

  MemoryPressureLevel _determinePressureLevel(double usage) {
    if (usage >= _criticalThreshold) return MemoryPressureLevel.critical;
    if (usage >= _pressureThreshold) return MemoryPressureLevel.high;
    if (usage >= 0.6) return MemoryPressureLevel.medium;
    return MemoryPressureLevel.normal;
  }

  MemoryPressureLevel _calculateCurrentPressure() {
    final usage = _getCurrentMemoryUsage();
    return _determinePressureLevel(usage);
  }

  double _getCurrentMemoryUsage() {
    if (_memoryHistory.isEmpty) return 0.0;
    return _memoryHistory.last.memoryUsage;
  }

  double _calculateMovingAverage(List<MemorySnapshot> snapshots) {
    if (snapshots.isEmpty) return 0.0;
    return snapshots.map((s) => s.memoryUsage).reduce((a, b) => a + b) / snapshots.length;
  }

  double _calculateRegressionConfidence(List<MemorySnapshot> snapshots, double slope, double intercept) {
    double sumSquaredErrors = 0;
    double sumSquaredTotal = 0;
    final mean = snapshots.map((s) => s.memoryUsage).reduce((a, b) => a + b) / snapshots.length;
    
    for (int i = 0; i < snapshots.length; i++) {
      final predicted = slope * i + intercept;
      final actual = snapshots[i].memoryUsage;
      sumSquaredErrors += math.pow(actual - predicted, 2);
      sumSquaredTotal += math.pow(actual - mean, 2);
    }
    
    final rSquared = sumSquaredTotal > 0 ? 1 - (sumSquaredErrors / sumSquaredTotal) : 0;
    return math.max(0.1, rSquared);
  }

  void _handleCriticalPressure() {
    _pressureController.add(MemoryPressureEvent(
      type: MemoryPressureEventType.criticalPressure,
      data: {
        'current_usage': _getCurrentMemoryUsage(),
        'actions_taken': 'critical_memory_cleanup',
      },
    ));
    
    debugPrint('🚨 CRITICAL MEMORY PRESSURE DETECTED!');
  }

  void _handleHighPressure() {
    _pressureController.add(MemoryPressureEvent(
      type: MemoryPressureEventType.highPressure,
      data: {
        'current_usage': _getCurrentMemoryUsage(),
        'actions_taken': 'preventive_optimization',
      },
    ));
    
    debugPrint('⚠️ HIGH MEMORY PRESSURE DETECTED');
  }

  List<MemoryOptimizationAction> _getCriticalActions() {
    return [
      MemoryOptimizationAction(
        type: OptimizationType.emergencyCleanup,
        description: 'Emergency memory cleanup',
        priority: 1,
        estimatedImpact: 0.3,
        executionTime: Duration(seconds: 5),
      ),
      MemoryOptimizationAction(
        type: OptimizationType.clearCaches,
        description: 'Clear all caches',
        priority: 2,
        estimatedImpact: 0.2,
        executionTime: Duration(seconds: 2),
      ),
      MemoryOptimizationAction(
        type: OptimizationType.reduceBuffers,
        description: 'Reduce buffer sizes to minimum',
        priority: 3,
        estimatedImpact: 0.15,
        executionTime: Duration(seconds: 1),
      ),
    ];
  }

  List<MemoryOptimizationAction> _getHighPressureActions() {
    return [
      MemoryOptimizationAction(
        type: OptimizationType.aggressiveGC,
        description: 'Aggressive garbage collection',
        priority: 1,
        estimatedImpact: 0.15,
        executionTime: Duration(seconds: 3),
      ),
      MemoryOptimizationAction(
        type: OptimizationType.clearUnusedPools,
        description: 'Clear unused object pools',
        priority: 2,
        estimatedImpact: 0.1,
        executionTime: Duration(seconds: 2),
      ),
      MemoryOptimizationAction(
        type: OptimizationType.compressMemory,
        description: 'Compress memory structures',
        priority: 3,
        estimatedImpact: 0.08,
        executionTime: Duration(seconds: 1),
      ),
    ];
  }

  List<MemoryOptimizationAction> _getPreventiveActions() {
    return [
      MemoryOptimizationAction(
        type: OptimizationType.optimisticCleanup,
        description: 'Optimistic memory cleanup',
        priority: 1,
        estimatedImpact: 0.05,
        executionTime: Duration(seconds: 2),
      ),
      MemoryOptimizationAction(
        type: OptimizationType.tuneBuffers,
        description: 'Tune buffer sizes',
        priority: 2,
        estimatedImpact: 0.03,
        executionTime: Duration(seconds: 1),
      ),
    ];
  }

  void _startMonitoring() {
    _monitoringTimer = Timer.periodic(_monitoringInterval, (_) {
      _collectMemorySnapshot();
    });
  }

  void _startPrediction() {
    _predictionTimer = Timer.periodic(_predictionInterval, (_) {
      unawaited(predictMemoryPressure());
    });
  }

  Future<void> _collectMemorySnapshot() async {
    // Simulate memory snapshot collection
    final totalMemory = 16384.0; // 16GB
    final usedMemory = totalMemory * (0.3 + math.Random().nextDouble() * 0.4); // 30-70% usage
    
    final snapshot = MemorySnapshot(
      timestamp: DateTime.now(),
      totalMemory: totalMemory,
      usedMemory: usedMemory,
      availableMemory: totalMemory - usedMemory,
      memoryUsage: usedMemory / totalMemory,
      swapUsage: math.Random().nextDouble() * 0.2,
      cacheSize: usedMemory * 0.1,
    );
    
    recordMemorySnapshot(snapshot);
  }

  MemoryStatistics getStatistics() {
    return MemoryStatistics(
      currentUsage: _getCurrentMemoryUsage(),
      currentPressure: _calculateCurrentPressure(),
      predictionsCount: _predictions.length,
      patternsCount: _patterns.length,
      historyLength: _memoryHistory.length,
      averageConfidence: _predictions.isEmpty ? 0.0 : 
          _predictions.map((p) => p.confidence).reduce((a, b) => a + b) / _predictions.length,
    );
  }

  Future<void> dispose() async {
    _monitoringTimer?.cancel();
    _predictionTimer?.cancel();
    _pressureController.close();
    _memoryHistory.clear();
    _patterns.clear();
    _predictions.clear();
  }
}

class MemorySnapshot {
  final DateTime timestamp;
  final double totalMemory;
  final double usedMemory;
  final double availableMemory;
  final double memoryUsage;
  final double swapUsage;
  final double cacheSize;
  
  MemorySnapshot({
    required this.timestamp,
    required this.totalMemory,
    required this.usedMemory,
    required this.availableMemory,
    required this.memoryUsage,
    required this.swapUsage,
    required this.cacheSize,
  });
}

class MemoryPrediction {
  final DateTime timestamp;
  final double predictedUsage;
  final double confidence;
  final MemoryPressureLevel pressureLevel;
  final List<String> recommendations;
  
  MemoryPrediction({
    required this.timestamp,
    required this.predictedUsage,
    required this.confidence,
    required this.pressureLevel,
    required this.recommendations,
  });
}

class MemoryPattern {
  final String key;
  final double averageUsage;
  final double trend;
  final double confidence;
  final int sampleCount;
  
  MemoryPattern({
    required this.key,
    required this.averageUsage,
    required this.trend,
    required this.confidence,
    required this.sampleCount,
  });
}

class PredictionEnsemble {
  final double usage;
  final double confidence;
  
  PredictionEnsemble({
    required this.usage,
    required this.confidence,
  });
}

class MemoryOptimizationAction {
  final OptimizationType type;
  final String description;
  final int priority;
  final double estimatedImpact;
  final Duration executionTime;
  
  MemoryOptimizationAction({
    required this.type,
    required this.description,
    required this.priority,
    required this.estimatedImpact,
    required this.executionTime,
  });
}

class MemoryStatistics {
  final double currentUsage;
  final MemoryPressureLevel currentPressure;
  final int predictionsCount;
  final int patternsCount;
  final int historyLength;
  final double averageConfidence;
  
  MemoryStatistics({
    required this.currentUsage,
    required this.currentPressure,
    required this.predictionsCount,
    required this.patternsCount,
    required this.historyLength,
    required this.averageConfidence,
  });
}

class MemoryPressureEvent {
  final MemoryPressureEventType type;
  final Map<String, dynamic>? data;
  
  MemoryPressureEvent({
    required this.type,
    this.data,
  });
}

enum MemoryPressureLevel {
  normal,
  medium,
  high,
  critical,
}

enum OptimizationType {
  emergencyCleanup,
  aggressiveGC,
  clearCaches,
  clearUnusedPools,
  reduceBuffers,
  compressMemory,
  optimisticCleanup,
  tuneBuffers,
}

enum MemoryPressureEventType {
  snapshotRecorded,
  predictionGenerated,
  criticalPressure,
  highPressure,
}

/// Extension on List for takeLast
extension ListExtension<T> on List<T> {
  List<T> takeLast(int n) {
    if (n >= length) return this;
    return sublist(length - n);
  }
}
