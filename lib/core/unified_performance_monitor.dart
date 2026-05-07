import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Unified Performance Monitor - Best-in-class performance tracking
/// 
/// Consolidates all performance monitoring into one unified system:
/// - CPU, memory, GPU, and network monitoring
/// - Application-specific metrics
/// - Real-time performance analysis
/// - Automatic performance optimization suggestions
/// - Historical data tracking and trends
/// - Performance alerts and notifications
class UnifiedPerformanceMonitor {
  static final UnifiedPerformanceMonitor _instance = UnifiedPerformanceMonitor._internal();
  factory UnifiedPerformanceMonitor() => _instance;
  UnifiedPerformanceMonitor._internal();

  final Map<String, PerformanceMetric> _metrics = {};
  final Map<String, PerformanceAlert> _alerts = {};
  final List<PerformanceSnapshot> _history = [];
  final Map<String, PerformanceThreshold> _thresholds = {};
  
  bool _isInitialized = false;
  bool _isMonitoring = false;
  Timer? _monitoringTimer;
  Timer? _analysisTimer;
  
  // Monitoring configuration
  static const Duration _monitoringInterval = Duration(seconds: 2);
  static const Duration _analysisInterval = Duration(seconds: 30);
  static const int _maxHistorySize = 1000;
  static const int _maxAlerts = 100;
  
  // Performance data
  double _currentCpuUsage = 0.0;
  double _currentMemoryUsage = 0.0;
  double _currentGpuUsage = 0.0;
  double _currentNetworkUsage = 0.0;
  int _activeProcesses = 0;
  int _openFileDescriptors = 0;
  
  final _eventController = StreamController<PerformanceEvent>.broadcast();
  Stream<PerformanceEvent> get events => _eventController.stream;
  
  bool get isInitialized => _isInitialized;
  bool get isMonitoring => _isMonitoring;
  Map<String, PerformanceMetric> get metrics => Map.unmodifiable(_metrics);

  /// Initialize the unified performance monitor
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Register default metrics
      await _registerDefaultMetrics();
      
      // Register default thresholds
      await _registerDefaultThresholds();
      
      _isInitialized = true;
      debugPrint('📊 Unified Performance Monitor initialized');
      
    } catch (e) {
      debugPrint('❌ Failed to initialize Unified Performance Monitor: $e');
      rethrow;
    }
  }

  /// Start performance monitoring
  void startMonitoring() {
    if (_isMonitoring) return;
    
    _isMonitoring = true;
    
    // Start monitoring timer
    _monitoringTimer = Timer.periodic(_monitoringInterval, (_) {
      _collectMetrics();
    });
    
    // Start analysis timer
    _analysisTimer = Timer.periodic(_analysisInterval, (_) {
      _analyzePerformance();
    });
    
    debugPrint('📊 Started performance monitoring');
    
    _eventController.add(PerformanceEvent(
      type: PerformanceEventType.monitoringStarted,
      message: 'Performance monitoring started',
      timestamp: DateTime.now(),
    ));
  }

  /// Stop performance monitoring
  void stopMonitoring() {
    if (!_isMonitoring) return;
    
    _isMonitoring = false;
    _monitoringTimer?.cancel();
    _analysisTimer?.cancel();
    
    debugPrint('📊 Stopped performance monitoring');
    
    _eventController.add(PerformanceEvent(
      type: PerformanceEventType.monitoringStopped,
      message: 'Performance monitoring stopped',
      timestamp: DateTime.now(),
    ));
  }

  /// Collect all performance metrics
  Future<void> _collectMetrics() async {
    try {
      // Collect system metrics
      await _collectSystemMetrics();
      
      // Collect application metrics
      await _collectApplicationMetrics();
      
      // Collect GPU metrics
      await _collectGPUMetrics();
      
      // Collect network metrics
      await _collectNetworkMetrics();
      
      // Create performance snapshot
      final snapshot = PerformanceSnapshot(
        timestamp: DateTime.now(),
        cpuUsage: _currentCpuUsage,
        memoryUsage: _currentMemoryUsage,
        gpuUsage: _currentGpuUsage,
        networkUsage: _currentNetworkUsage,
        activeProcesses: _activeProcesses,
        openFileDescriptors: _openFileDescriptors,
        metrics: Map.unmodifiable(_metrics),
      );
      
      _addToHistory(snapshot);
      
    } catch (e) {
      debugPrint('❌ Failed to collect metrics: $e');
    }
  }

  /// Collect system metrics
  Future<void> _collectSystemMetrics() async {
    // CPU usage
    _currentCpuUsage = await _getCpuUsage();
    _updateMetric('cpu_usage', _currentCpuUsage, '%');
    
    // Memory usage
    _currentMemoryUsage = await _getMemoryUsage();
    _updateMetric('memory_usage', _currentMemoryUsage, '%');
    
    // Active processes
    _activeProcesses = await _getActiveProcesses();
    _updateMetric('active_processes', _activeProcesses.toDouble(), 'count');
    
    // Open file descriptors
    _openFileDescriptors = await _getOpenFileDescriptors();
    _updateMetric('open_file_descriptors', _openFileDescriptors.toDouble(), 'count');
  }

  /// Collect application-specific metrics
  Future<void> _collectApplicationMetrics() async {
    // Terminal buffer usage
    final bufferUsage = await _getTerminalBufferUsage();
    _updateMetric('terminal_buffer_usage', bufferUsage, '%');
    
    // Render performance
    final renderTime = await _getRenderTime();
    _updateMetric('render_time', renderTime, 'ms');
    
    // AI response time
    final aiResponseTime = await _getAIResponseTime();
    _updateMetric('ai_response_time', aiResponseTime, 'ms');
    
    // Frame rate
    final frameRate = await _getFrameRate();
    _updateMetric('frame_rate', frameRate, 'fps');
  }

  /// Collect GPU metrics
  Future<void> _collectGPUMetrics() async {
    _currentGpuUsage = await _getGpuUsage();
    _updateMetric('gpu_usage', _currentGpuUsage, '%');
    
    // GPU memory
    final gpuMemory = await _getGpuMemoryUsage();
    _updateMetric('gpu_memory_usage', gpuMemory, '%');
    
    // GPU temperature
    final gpuTemp = await _getGpuTemperature();
    _updateMetric('gpu_temperature', gpuTemp, '°C');
  }

  /// Collect network metrics
  Future<void> _collectNetworkMetrics() async {
    _currentNetworkUsage = await _getNetworkUsage();
    _updateMetric('network_usage', _currentNetworkUsage, 'Mbps');
    
    // Network latency
    final latency = await _getNetworkLatency();
    _updateMetric('network_latency', latency, 'ms');
  }

  /// Analyze performance and generate alerts
  void _analyzePerformance() {
    if (_history.length < 10) return;
    
    final recent = _history.reversed.take(10).toList();
    
    // Check thresholds and generate alerts
    _checkThresholds();
    
    // Analyze trends
    _analyzeTrends(recent);
    
    // Generate optimization suggestions
    _generateOptimizationSuggestions();
  }

  /// Check performance thresholds
  void _checkThresholds() {
    for (final entry in _thresholds.entries) {
      final metricId = entry.key;
      final threshold = entry.value;
      final metric = _metrics[metricId];
      
      if (metric != null) {
        _checkMetricThreshold(metricId, metric, threshold);
      }
    }
  }

  /// Check individual metric threshold
  void _checkMetricThreshold(String metricId, PerformanceMetric metric, PerformanceThreshold threshold) {
    final value = metric.currentValue;
    bool alertTriggered = false;
    String alertMessage = '';
    
    switch (threshold.type) {
      case ThresholdType.above:
        if (value > threshold.value) {
          alertTriggered = true;
          alertMessage = 'Metric $metricId exceeded threshold: ${value.toStringAsFixed(2)} > ${threshold.value}';
        }
        break;
      case ThresholdType.below:
        if (value < threshold.value) {
          alertTriggered = true;
          alertMessage = 'Metric $metricId below threshold: ${value.toStringAsFixed(2)} < ${threshold.value}';
        }
        break;
      case ThresholdType.rapidChange:
        if (_isRapidChange(metricId, value)) {
          alertTriggered = true;
          alertMessage = 'Rapid change detected in $metricId: ${value.toStringAsFixed(2)}';
        }
        break;
    }
    
    if (alertTriggered) {
      _createAlert(metricId, alertMessage, threshold.severity);
    }
  }

  /// Check for rapid changes in metric
  bool _isRapidChange(String metricId, double currentValue) {
    if (_history.length < 5) return false;
    
    final recent = _history.reversed.take(5).map((s) => s.metrics[metricId]?.currentValue).where((v) => v != null).cast<double>().toList();
    
    if (recent.length < 3) return false;
    
    // Calculate standard deviation
    final mean = recent.reduce((a, b) => a + b) / recent.length;
    final variance = recent.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b) / recent.length;
    final stdDev = math.sqrt(variance);
    
    // Check if current value is more than 2 standard deviations from mean
    return (currentValue - mean).abs() > 2 * stdDev;
  }

  /// Analyze performance trends
  void _analyzeTrends(List<PerformanceSnapshot> recent) {
    // CPU trend
    final cpuTrend = _calculateTrend(recent.map((s) => s.cpuUsage).toList());
    if (cpuTrend > 0.1) {
      _eventController.add(PerformanceEvent(
        type: PerformanceEventType.trendUpward,
        message: 'CPU usage trending upward',
        timestamp: DateTime.now(),
        data: {'metric': 'cpu_usage', 'trend': cpuTrend},
      ));
    }
    
    // Memory trend
    final memoryTrend = _calculateTrend(recent.map((s) => s.memoryUsage).toList());
    if (memoryTrend > 0.1) {
      _eventController.add(PerformanceEvent(
        type: PerformanceEventType.trendUpward,
        message: 'Memory usage trending upward',
        timestamp: DateTime.now(),
        data: {'metric': 'memory_usage', 'trend': memoryTrend},
      ));
    }
  }

  /// Calculate trend coefficient
  double _calculateTrend(List<double> values) {
    if (values.length < 2) return 0.0;
    
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    final n = values.length.toDouble();
    
    for (int i = 0; i < values.length; i++) {
      sumX += i;
      sumY += values[i];
      sumXY += i * values[i];
      sumX2 += i * i;
    }
    
    return (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
  }

  /// Generate optimization suggestions
  void _generateOptimizationSuggestions() {
    final suggestions = <String>[];
    
    if (_currentCpuUsage > 80) {
      suggestions.add('High CPU usage detected. Consider reducing background processes.');
    }
    
    if (_currentMemoryUsage > 85) {
      suggestions.add('High memory usage detected. Consider clearing unused buffers or restarting.');
    }
    
    if (_currentGpuUsage > 90) {
      suggestions.add('High GPU usage detected. Consider reducing rendering quality or closing graphics-intensive applications.');
    }
    
    if (_currentNetworkUsage > 50) {
      suggestions.add('High network usage detected. Check for background downloads or uploads.');
    }
    
    if (suggestions.isNotEmpty) {
      _eventController.add(PerformanceEvent(
        type: PerformanceEventType.optimizationSuggestions,
        message: 'Performance optimization suggestions available',
        timestamp: DateTime.now(),
        data: {'suggestions': suggestions},
      ));
    }
  }

  /// Create performance alert
  void _createAlert(String metricId, String message, AlertSeverity severity) {
    final alert = PerformanceAlert(
      id: '${metricId}_${DateTime.now().millisecondsSinceEpoch}',
      metricId: metricId,
      message: message,
      severity: severity,
      timestamp: DateTime.now(),
    );
    
    _alerts[alert.id] = alert;
    
    // Limit alerts
    if (_alerts.length > _maxAlerts) {
      final oldest = _alerts.keys.first;
      _alerts.remove(oldest);
    }
    
    _eventController.add(PerformanceEvent(
      type: PerformanceEventType.alert,
      message: message,
      timestamp: DateTime.now(),
      data: {'alert': alert.toJson()},
    ));
    
    debugPrint('🚨 Performance alert: $message');
  }

  /// Update metric value
  void _updateMetric(String id, double value, String unit) {
    final metric = _metrics.putIfAbsent(
      id,
      () => PerformanceMetric(id: id, unit: unit),
    );
    
    metric.updateValue(value);
  }

  /// Add snapshot to history
  void _addToHistory(PerformanceSnapshot snapshot) {
    _history.add(snapshot);
    
    // Limit history size
    if (_history.length > _maxHistorySize) {
      _history.removeAt(0);
    }
  }

  /// Get current performance summary
  PerformanceSummary getSummary() {
    return PerformanceSummary(
      timestamp: DateTime.now(),
      cpuUsage: _currentCpuUsage,
      memoryUsage: _currentMemoryUsage,
      gpuUsage: _currentGpuUsage,
      networkUsage: _currentNetworkUsage,
      activeProcesses: _activeProcesses,
      openFileDescriptors: _openFileDescriptors,
      metrics: Map.unmodifiable(_metrics),
      alerts: _alerts.values.toList(),
      trend: _calculateOverallTrend(),
    );
  }

  /// Calculate overall performance trend
  PerformanceTrend _calculateOverallTrend() {
    if (_history.length < 10) return PerformanceTrend.stable;
    
    final recent = _history.reversed.take(10).toList();
    final cpuTrend = _calculateTrend(recent.map((s) => s.cpuUsage).toList());
    final memoryTrend = _calculateTrend(recent.map((s) => s.memoryUsage).toList());
    
    if (cpuTrend > 0.1 || memoryTrend > 0.1) {
      return PerformanceTrend.degrading;
    } else if (cpuTrend < -0.1 || memoryTrend < -0.1) {
      return PerformanceTrend.improving;
    }
    
    return PerformanceTrend.stable;
  }

  /// Register default metrics
  Future<void> _registerDefaultMetrics() async {
    // System metrics
    _metrics['cpu_usage'] = PerformanceMetric(id: 'cpu_usage', unit: '%');
    _metrics['memory_usage'] = PerformanceMetric(id: 'memory_usage', unit: '%');
    _metrics['gpu_usage'] = PerformanceMetric(id: 'gpu_usage', unit: '%');
    _metrics['network_usage'] = PerformanceMetric(id: 'network_usage', unit: 'Mbps');
    
    // Application metrics
    _metrics['terminal_buffer_usage'] = PerformanceMetric(id: 'terminal_buffer_usage', unit: '%');
    _metrics['render_time'] = PerformanceMetric(id: 'render_time', unit: 'ms');
    _metrics['ai_response_time'] = PerformanceMetric(id: 'ai_response_time', unit: 'ms');
    _metrics['frame_rate'] = PerformanceMetric(id: 'frame_rate', unit: 'fps');
  }

  /// Register default thresholds
  Future<void> _registerDefaultThresholds() async {
    _thresholds['cpu_usage'] = PerformanceThreshold(
      metricId: 'cpu_usage',
      type: ThresholdType.above,
      value: 80.0,
      severity: AlertSeverity.warning,
    );
    
    _thresholds['memory_usage'] = PerformanceThreshold(
      metricId: 'memory_usage',
      type: ThresholdType.above,
      value: 85.0,
      severity: AlertSeverity.warning,
    );
    
    _thresholds['gpu_usage'] = PerformanceThreshold(
      metricId: 'gpu_usage',
      type: ThresholdType.above,
      value: 90.0,
      severity: AlertSeverity.critical,
    );
  }

  // System metric collection methods (would use platform channels in real implementation)
  Future<double> _getCpuUsage() async {
    // Simulate CPU usage
    return 20.0 + math.Random().nextDouble() * 30.0;
  }

  Future<double> _getMemoryUsage() async {
    // Simulate memory usage
    return 40.0 + math.Random().nextDouble() * 20.0;
  }

  Future<int> _getActiveProcesses() async {
    // Simulate active processes
    return 50 + math.Random().nextInt(50);
  }

  Future<int> _getOpenFileDescriptors() async {
    // Simulate open file descriptors
    return 200 + math.Random().nextInt(100);
  }

  Future<double> _getTerminalBufferUsage() async {
    // Simulate terminal buffer usage
    return 30.0 + math.Random().nextDouble() * 40.0;
  }

  Future<double> _getRenderTime() async {
    // Simulate render time
    return 5.0 + math.Random().nextDouble() * 10.0;
  }

  Future<double> _getAIResponseTime() async {
    // Simulate AI response time
    return 100.0 + math.Random().nextDouble() * 200.0;
  }

  Future<double> _getFrameRate() async {
    // Simulate frame rate
    return 55.0 + math.Random().nextDouble() * 10.0;
  }

  Future<double> _getGpuUsage() async {
    // Simulate GPU usage
    return 10.0 + math.Random().nextDouble() * 20.0;
  }

  Future<double> _getGpuMemoryUsage() async {
    // Simulate GPU memory usage
    return 25.0 + math.Random().nextDouble() * 15.0;
  }

  Future<double> _getGpuTemperature() async {
    // Simulate GPU temperature
    return 60.0 + math.Random().nextDouble() * 20.0;
  }

  Future<double> _getNetworkUsage() async {
    // Simulate network usage
    return math.Random().nextDouble() * 10.0;
  }

  Future<double> _getNetworkLatency() async {
    // Simulate network latency
    return 10.0 + math.Random().nextDouble() * 20.0;
  }

  /// Dispose the performance monitor
  Future<void> dispose() async {
    stopMonitoring();
    _eventController.close();
    
    _metrics.clear();
    _alerts.clear();
    _history.clear();
    _thresholds.clear();
    
    debugPrint('📊 Unified Performance Monitor disposed');
  }
}

/// Performance metric
class PerformanceMetric {
  final String id;
  final String unit;
  final List<double> _values = [];
  final List<DateTime> _timestamps = [];
  
  double _currentValue = 0.0;
  DateTime _lastUpdate = DateTime.now();
  
  PerformanceMetric({required this.id, required this.unit});
  
  void updateValue(double value) {
    _currentValue = value;
    _lastUpdate = DateTime.now();
    
    _values.add(value);
    _timestamps.add(_lastUpdate);
    
    // Keep only last 100 values
    if (_values.length > 100) {
      _values.removeAt(0);
      _timestamps.removeAt(0);
    }
  }
  
  double get currentValue => _currentValue;
  DateTime get lastUpdate => _lastUpdate;
  List<double> get values => List.unmodifiable(_values);
  
  double getAverage() {
    if (_values.isEmpty) return 0.0;
    return _values.reduce((a, b) => a + b) / _values.length;
  }
  
  double getMin() {
    if (_values.isEmpty) return 0.0;
    return _values.reduce(math.min);
  }
  
  double getMax() {
    if (_values.isEmpty) return 0.0;
    return _values.reduce(math.max);
  }
}

/// Performance snapshot
class PerformanceSnapshot {
  final DateTime timestamp;
  final double cpuUsage;
  final double memoryUsage;
  final double gpuUsage;
  final double networkUsage;
  final int activeProcesses;
  final int openFileDescriptors;
  final Map<String, PerformanceMetric> metrics;
  
  PerformanceSnapshot({
    required this.timestamp,
    required this.cpuUsage,
    required this.memoryUsage,
    required this.gpuUsage,
    required this.networkUsage,
    required this.activeProcesses,
    required this.openFileDescriptors,
    required this.metrics,
  });
}

/// Performance alert
class PerformanceAlert {
  final String id;
  final String metricId;
  final String message;
  final AlertSeverity severity;
  final DateTime timestamp;
  
  PerformanceAlert({
    required this.id,
    required this.metricId,
    required this.message,
    required this.severity,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'metricId': metricId,
    'message': message,
    'severity': severity.toString(),
    'timestamp': timestamp.toIso8601String(),
  };
}

/// Performance threshold
class PerformanceThreshold {
  final String metricId;
  final ThresholdType type;
  final double value;
  final AlertSeverity severity;
  
  PerformanceThreshold({
    required this.metricId,
    required this.type,
    required this.value,
    required this.severity,
  });
}

/// Performance event
class PerformanceEvent {
  final PerformanceEventType type;
  final String message;
  final DateTime timestamp;
  final Map<String, dynamic>? data;
  
  PerformanceEvent({
    required this.type,
    required this.message,
    required this.timestamp,
    this.data,
  });
}

/// Performance summary
class PerformanceSummary {
  final DateTime timestamp;
  final double cpuUsage;
  final double memoryUsage;
  final double gpuUsage;
  final double networkUsage;
  final int activeProcesses;
  final int openFileDescriptors;
  final Map<String, PerformanceMetric> metrics;
  final List<PerformanceAlert> alerts;
  final PerformanceTrend trend;
  
  PerformanceSummary({
    required this.timestamp,
    required this.cpuUsage,
    required this.memoryUsage,
    required this.gpuUsage,
    required this.networkUsage,
    required this.activeProcesses,
    required this.openFileDescriptors,
    required this.metrics,
    required this.alerts,
    required this.trend,
  });
}

/// Enums
enum ThresholdType { above, below, rapidChange }
enum AlertSeverity { info, warning, critical }
enum PerformanceEventType { 
  monitoringStarted, 
  monitoringStopped, 
  alert, 
  trendUpward, 
  trendDownward, 
  optimizationSuggestions 
}
enum PerformanceTrend { improving, stable, degrading }
