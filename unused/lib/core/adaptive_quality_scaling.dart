import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

class AdaptiveQualityScaling {
  static const double _maxQualityScale = 1.0;
  static const double _minQualityScale = 0.2;
  static const double _defaultQualityScale = 0.8;
  static const int _performanceCheckInterval = 1000; // 1 second
  static const int _qualityAdjustmentThreshold = 5; // consecutive frames
  
  final Map<String, QualityProfile> _qualityProfiles = {};
  final List<PerformanceSample> _performanceHistory = [];
  final Map<String, ContentMetrics> _contentMetrics = {};
  
  Timer? _performanceTimer;
  double _currentQualityScale = _defaultQualityScale;
  int _consecutiveHighPerf = 0;
  int _consecutiveLowPerf = 0;
  
  final StreamController<QualityChangeEvent> _qualityChangeController = 
      StreamController<QualityChangeEvent>.broadcast();

  void initialize() {
    _startPerformanceMonitoring();
    _initializeQualityProfiles();
    developer.log('🎨 Adaptive Quality Scaling initialized');
  }

  void _startPerformanceMonitoring() {
    _performanceTimer = Timer.periodic(
      Duration(milliseconds: _performanceCheckInterval),
      (_) => _analyzePerformance(),
    );
  }

  void _initializeQualityProfiles() {
    // Create quality profiles for different content types
    _qualityProfiles['text'] = QualityProfile(
      contentType: 'text',
      minScale: 0.6,
      maxScale: 1.0,
      preferredScale: 0.9,
      importance: 1.0,
    );
    
    _qualityProfiles['graphics'] = QualityProfile(
      contentType: 'graphics',
      minScale: 0.3,
      maxScale: 1.0,
      preferredScale: 0.7,
      importance: 0.8,
    );
    
    _qualityProfiles['video'] = QualityProfile(
      contentType: 'video',
      minScale: 0.4,
      maxScale: 1.0,
      preferredScale: 0.8,
      importance: 0.9,
    );
    
    _qualityProfiles['terminal'] = QualityProfile(
      contentType: 'terminal',
      minScale: 0.8,
      maxScale: 1.0,
      preferredScale: 1.0,
      importance: 1.0,
    );
  }

  void _analyzePerformance() {
    final currentPerformance = _measureCurrentPerformance();
    final performanceSample = PerformanceSample(
      timestamp: DateTime.now(),
      frameTime: currentPerformance.frameTime,
      memoryUsage: currentPerformance.memoryUsage,
      cpuUsage: currentPerformance.cpuUsage,
      qualityScale: _currentQualityScale,
    );

    _performanceHistory.add(performanceSample);
    if (_performanceHistory.length > 60) {
      _performanceHistory.removeAt(0);
    }

    _adjustQuality(performanceSample);
  }

  PerformanceMetrics _measureCurrentPerformance() {
    // In a real implementation, these would be actual measurements
    return PerformanceMetrics(
      frameTime: _measureFrameTime(),
      memoryUsage: _measureMemoryUsage(),
      cpuUsage: _measureCpuUsage(),
    );
  }

  double _measureFrameTime() {
    // Simulate frame time measurement
    return 16.0 + (DateTime.now().millisecond % 20); // 16-36ms
  }

  int _measureMemoryUsage() {
    // Simulate memory usage
    return 50 * 1024 * 1024 + (DateTime.now().millisecond * 1024); // 50-100MB
  }

  double _measureCpuUsage() {
    // Simulate CPU usage
    return 0.3 + (DateTime.now().millisecond % 100) / 200.0; // 30-80%
  }

  void _adjustQuality(PerformanceSample sample) {
    final targetFrameTime = _getTargetFrameTime();
    final performanceRatio = targetFrameTime / sample.frameTime;
    
    if (performanceRatio > 1.2) {
      // Performance is good, can increase quality
      _consecutiveHighPerf++;
      _consecutiveLowPerf = 0;
      
      if (_consecutiveHighPerf >= _qualityAdjustmentThreshold) {
        _increaseQuality();
        _consecutiveHighPerf = 0;
      }
    } else if (performanceRatio < 0.8) {
      // Performance is poor, need to decrease quality
      _consecutiveLowPerf++;
      _consecutiveHighPerf = 0;
      
      if (_consecutiveLowPerf >= _qualityAdjustmentThreshold) {
        _decreaseQuality();
        _consecutiveLowPerf = 0;
      }
    } else {
      // Performance is acceptable
      _consecutiveHighPerf = 0;
      _consecutiveLowPerf = 0;
    }
  }

  double _getTargetFrameTime() {
    // Get target frame time based on current content
    final activeContent = _getActiveContentType();
    final profile = _qualityProfiles[activeContent];
    
    if (profile != null) {
      // Terminal needs higher performance
      if (activeContent == 'terminal') return 8.0;
      // Video can tolerate lower performance
      if (activeContent == 'video') return 33.0;
      // Graphics and text are in between
      return 16.0;
    }
    
    return 16.0; // Default 60 FPS target
  }

  String _getActiveContentType() {
    // Determine the most active content type
    // In a real implementation, this would analyze actual content
    return 'terminal'; // Default for terminal emulator
  }

  void _increaseQuality() {
    final activeContent = _getActiveContentType();
    final profile = _qualityProfiles[activeContent];
    
    if (profile == null) return;
    
    final oldScale = _currentQualityScale;
    final maxScale = profile.maxScale;
    final step = (maxScale - _currentQualityScale) * 0.3;
    
    _currentQualityScale = (_currentQualityScale + step).clamp(_minQualityScale, maxScale);
    
    if (_currentQualityScale != oldScale) {
      developer.log('🎨 Increased quality to: ${(_currentQualityScale * 100).toStringAsFixed(0)}%');
      _emitQualityChange(oldScale, _currentQualityScale, 'performance_increase');
    }
  }

  void _decreaseQuality() {
    final activeContent = _getActiveContentType();
    final profile = _qualityProfiles[activeContent];
    
    if (profile == null) return;
    
    final oldScale = _currentQualityScale;
    final minScale = profile.minScale;
    final step = (_currentQualityScale - minScale) * 0.4;
    
    _currentQualityScale = (_currentQualityScale - step).clamp(minScale, _maxQualityScale);
    
    if (_currentQualityScale != oldScale) {
      developer.log('🎨 Decreased quality to: ${(_currentQualityScale * 100).toStringAsFixed(0)}%');
      _emitQualityChange(oldScale, _currentQualityScale, 'performance_decrease');
    }
  }

  void _emitQualityChange(double oldScale, double newScale, String reason) {
    final event = QualityChangeEvent(
      oldScale: oldScale,
      newScale: newScale,
      reason: reason,
      timestamp: DateTime.now(),
      contentType: _getActiveContentType(),
    );
    
    _qualityChangeController.add(event);
  }

  void registerContent(String contentId, String contentType, ContentComplexity complexity) {
    _contentMetrics[contentId] = ContentMetrics(
      id: contentId,
      type: contentType,
      complexity: complexity,
      registeredAt: DateTime.now(),
    );
    
    developer.log('🎨 Registered content $contentId as $contentType (${complexity.name})');
  }

  void updateContentComplexity(String contentId, ContentComplexity complexity) {
    final metrics = _contentMetrics[contentId];
    if (metrics != null) {
      metrics.complexity = complexity;
      metrics.lastUpdated = DateTime.now();
      
      // Adjust quality based on content complexity
      _adjustQualityForContent(contentId, complexity);
    }
  }

  void _adjustQualityForContent(String contentId, ContentComplexity complexity) {
    final metrics = _contentMetrics[contentId];
    if (metrics == null) return;
    
    final profile = _qualityProfiles[metrics.type];
    if (profile == null) return;
    
    // Adjust quality scale based on complexity
    double complexityMultiplier;
    switch (complexity) {
      case ContentComplexity.low:
        complexityMultiplier = 1.2;
        break;
      case ContentComplexity.medium:
        complexityMultiplier = 1.0;
        break;
      case ContentComplexity.high:
        complexityMultiplier = 0.8;
        break;
      case ContentComplexity.very_high:
        complexityMultiplier = 0.6;
        break;
    }
    
    final targetScale = profile.preferredScale * complexityMultiplier;
    final clampedScale = targetScale.clamp(profile.minScale, profile.maxScale);
    
    if (clampedScale != _currentQualityScale) {
      final oldScale = _currentQualityScale;
      _currentQualityScale = clampedScale;
      
      developer.log('🎨 Adjusted quality for content complexity to: ${(_currentQualityScale * 100).toStringAsFixed(0)}%');
      _emitQualityChange(oldScale, _currentQualityScale, 'content_complexity');
    }
  }

  void setQualityScale(double scale, {String? reason}) {
    final oldScale = _currentQualityScale;
    _currentQualityScale = scale.clamp(_minQualityScale, _maxQualityScale);
    
    if (_currentQualityScale != oldScale) {
      developer.log('🎨 Manual quality set to: ${(_currentQualityScale * 100).toStringAsFixed(0)}%');
      _emitQualityChange(oldScale, _currentQualityScale, reason ?? 'manual');
    }
  }

  void resetToOptimal() {
    final activeContent = _getActiveContentType();
    final profile = _qualityProfiles[activeContent];
    
    if (profile != null) {
      setQualityScale(profile.preferredScale, reason: 'reset_to_optimal');
    } else {
      setQualityScale(_defaultQualityScale, reason: 'reset_to_default');
    }
  }

  Stream<QualityChangeEvent> get qualityChangeStream => _qualityChangeController.stream;

  double get currentQualityScale => _currentQualityScale;

  QualityScalingStats getStats() {
    return QualityScalingStats(
      currentScale: _currentQualityScale,
      performanceHistory: _performanceHistory.toList(),
      qualityProfiles: _qualityProfiles.values.toList(),
      contentMetrics: _contentMetrics.values.toList(),
      consecutiveHighPerf: _consecutiveHighPerf,
      consecutiveLowPerf: _consecutiveLowPerf,
    );
  }

  void dispose() {
    _performanceTimer?.cancel();
    _qualityChangeController.close();
    _performanceHistory.clear();
    _contentMetrics.clear();
    developer.log('🎨 Adaptive Quality Scaling disposed');
  }
}

class QualityProfile {
  final String contentType;
  final double minScale;
  final double maxScale;
  final double preferredScale;
  final double importance;

  QualityProfile({
    required this.contentType,
    required this.minScale,
    required this.maxScale,
    required this.preferredScale,
    required this.importance,
  });
}

class ContentMetrics {
  final String id;
  final String type;
  ContentComplexity complexity;
  final DateTime registeredAt;
  DateTime lastUpdated;

  ContentMetrics({
    required this.id,
    required this.type,
    required this.complexity,
    required this.registeredAt,
  }) : lastUpdated = DateTime.now();
}

enum ContentComplexity {
  low,
  medium,
  high,
  very_high,
}

class PerformanceSample {
  final DateTime timestamp;
  final double frameTime;
  final int memoryUsage;
  final double cpuUsage;
  final double qualityScale;

  PerformanceSample({
    required this.timestamp,
    required this.frameTime,
    required this.memoryUsage,
    required this.cpuUsage,
    required this.qualityScale,
  });
}

class PerformanceMetrics {
  final double frameTime;
  final int memoryUsage;
  final double cpuUsage;

  PerformanceMetrics({
    required this.frameTime,
    required this.memoryUsage,
    required this.cpuUsage,
  });
}

class QualityChangeEvent {
  final double oldScale;
  final double newScale;
  final String reason;
  final DateTime timestamp;
  final String contentType;

  QualityChangeEvent({
    required this.oldScale,
    required this.newScale,
    required this.reason,
    required this.timestamp,
    required this.contentType,
  });
}

class QualityScalingStats {
  final double currentScale;
  final List<PerformanceSample> performanceHistory;
  final List<QualityProfile> qualityProfiles;
  final List<ContentMetrics> contentMetrics;
  final int consecutiveHighPerf;
  final int consecutiveLowPerf;

  QualityScalingStats({
    required this.currentScale,
    required this.performanceHistory,
    required this.qualityProfiles,
    required this.contentMetrics,
    required this.consecutiveHighPerf,
    required this.consecutiveLowPerf,
  });
}
