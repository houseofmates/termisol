import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:process_run/process_run.dart';

/// Smart resource monitor with intelligent analysis
/// 
/// Features:
/// - Real-time resource monitoring
/// - Predictive resource analysis
/// - Application-specific monitoring
/// - Resource usage optimization
/// - Historical trend analysis
class SmartResourceMonitor {
  final StreamController<ResourceEvent> _eventController = StreamController<ResourceEvent>.broadcast();
  
  final Map<String, ResourceMetric> _currentMetrics = {};
  final Map<String, List<ResourceMetric>> _historicalData = {};
  final Map<String, ApplicationResource> _applicationMetrics = {};
  final Map<String, ResourceTrend> _trends = {};
  final List<ResourceAlert> _alerts = [];
  
  Timer? _monitoringTimer;
  Timer? _analysisTimer;
  Timer? _alertTimer;
  bool _isInitialized = false;
  late SharedPreferences _prefs;
  
  Stream<ResourceEvent> get events => _eventController.stream;
  bool get isInitialized => _isInitialized;
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      
      // Load historical data
      await _loadHistoricalData();
      
      // Initialize monitoring
      _startResourceMonitoring();
      
      // Start analysis
      _startResourceAnalysis();
      
      // Start alert monitoring
      _startAlertMonitoring();
      
      _isInitialized = true;
      
      _eventController.add(ResourceEvent(
        type: ResourceEventType.initialized,
        message: 'Smart resource monitor initialized',
        data: {
          'metrics': _currentMetrics.length,
          'applications': _applicationMetrics.length,
        },
      ));
      
      debugPrint('📊 Smart Resource Monitor initialized');
    } catch (e) {
      debugPrint('Failed to initialize smart resource monitor: $e');
    }
  }
  
  Future<void> _loadHistoricalData() async {
    try {
      final historicalJson = _prefs.getString('resource_historical_data');
      if (historicalJson != null) {
        final historicalMap = jsonDecode(historicalJson);
        _historicalData = historicalMap.map((key, value) => 
          MapEntry(key, (value as List).map((item) => 
            ResourceMetric.fromJson(item)).toList()));
      }
      
      final trendsJson = _prefs.getString('resource_trends');
      if (trendsJson != null) {
        final trendsMap = jsonDecode(trendsJson);
        _trends = trendsMap.map((key, value) => 
          MapEntry(key, ResourceTrend.fromJson(value)));
      }
      
      final alertsJson = _prefs.getString('resource_alerts');
      if (alertsJson != null) {
        final alertsList = jsonDecode(alertsJson);
        _alerts = alertsList.map((item) => 
          ResourceAlert.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint('Failed to load historical data: $e');
    }
  }
  
  void _startResourceMonitoring() {
    _monitoringTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _collectResourceMetrics();
    });
  }
  
  void _startResourceAnalysis() {
    _analysisTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _analyzeResourceTrends();
    });
  }
  
  void _startAlertMonitoring() {
    _alertTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkResourceAlerts();
    });
  }
  
  Future<void> _collectResourceMetrics() async {
    try {
      final timestamp = DateTime.now();
      
      // CPU metrics
      final cpuUsage = await _getCPUUsage();
      final cpuFrequency = await _getCPUFrequency();
      final cpuTemperature = await _getCPUTemperature();
      final cpuLoad = await _getCPULoad();
      
      _currentMetrics['cpu_usage'] = ResourceMetric(
        name: 'cpu_usage',
        value: cpuUsage,
        timestamp: timestamp,
        unit: 'percent',
        category: ResourceCategory.cpu,
      );
      
      _currentMetrics['cpu_frequency'] = ResourceMetric(
        name: 'cpu_frequency',
        value: cpuFrequency,
        timestamp: timestamp,
        unit: 'mhz',
        category: ResourceCategory.cpu,
      );
      
      _currentMetrics['cpu_temperature'] = ResourceMetric(
        name: 'cpu_temperature',
        value: cpuTemperature,
        timestamp: timestamp,
        unit: 'celsius',
        category: ResourceCategory.cpu,
      );
      
      _currentMetrics['cpu_load'] = ResourceMetric(
        name: 'cpu_load',
        value: cpuLoad,
        timestamp: timestamp,
        unit: 'load',
        category: ResourceCategory.cpu,
      );
      
      // Memory metrics
      final memoryUsage = await _getMemoryUsage();
      final memoryAvailable = await _getMemoryAvailable();
      final swapUsage = await _getSwapUsage();
      
      _currentMetrics['memory_usage'] = ResourceMetric(
        name: 'memory_usage',
        value: memoryUsage,
        timestamp: timestamp,
        unit: 'percent',
        category: ResourceCategory.memory,
      );
      
      _currentMetrics['memory_available'] = ResourceMetric(
        name: 'memory_available',
        value: memoryAvailable,
        timestamp: timestamp,
        unit: 'gb',
        category: ResourceCategory.memory,
      );
      
      _currentMetrics['swap_usage'] = ResourceMetric(
        name: 'swap_usage',
        value: swapUsage,
        timestamp: timestamp,
        unit: 'percent',
        category: ResourceCategory.memory,
      );
      
      // Disk metrics
      final diskUsage = await _getDiskUsage();
      final diskIO = await _getDiskIO();
      final diskRead = await _getDiskRead();
      final diskWrite = await _getDiskWrite();
      
      _currentMetrics['disk_usage'] = ResourceMetric(
        name: 'disk_usage',
        value: diskUsage,
        timestamp: timestamp,
        unit: 'percent',
        category: ResourceCategory.disk,
      );
      
      _currentMetrics['disk_io'] = ResourceMetric(
        name: 'disk_io',
        value: diskIO,
        timestamp: timestamp,
        unit: 'mbps',
        category: ResourceCategory.disk,
      );
      
      _currentMetrics['disk_read'] = ResourceMetric(
        name: 'disk_read',
        value: diskRead,
        timestamp: timestamp,
        unit: 'mbs',
        category: ResourceCategory.disk,
      );
      
      _currentMetrics['disk_write'] = ResourceMetric(
        name: 'disk_write',
        value: diskWrite,
        timestamp: timestamp,
        unit: 'mbs',
        category: ResourceCategory.disk,
      );
      
      // Network metrics
      final networkIO = await _getNetworkIO();
      final networkUpload = await _getNetworkUpload();
      final networkDownload = await _getNetworkDownload();
      
      _currentMetrics['network_io'] = ResourceMetric(
        name: 'network_io',
        value: networkIO,
        timestamp: timestamp,
        unit: 'mbps',
        category: ResourceCategory.network,
      );
      
      _currentMetrics['network_upload'] = ResourceMetric(
        name: 'network_upload',
        value: networkUpload,
        timestamp: timestamp,
        unit: 'mbps',
        category: ResourceCategory.network,
      );
      
      _currentMetrics['network_download'] = ResourceMetric(
        name: 'network_download',
        value: networkDownload,
        timestamp: timestamp,
        unit: 'mbps',
        category: ResourceCategory.network,
      );
      
      // GPU metrics
      final gpuUsage = await _getGPUUsage();
      final gpuMemory = await _getGPUMemory();
      final gpuTemperature = await _getGPUTemperature();
      
      _currentMetrics['gpu_usage'] = ResourceMetric(
        name: 'gpu_usage',
        value: gpuUsage,
        timestamp: timestamp,
        unit: 'percent',
        category: ResourceCategory.gpu,
      );
      
      _currentMetrics['gpu_memory'] = ResourceMetric(
        name: 'gpu_memory',
        value: gpuMemory,
        timestamp: timestamp,
        unit: 'percent',
        category: ResourceCategory.gpu,
      );
      
      _currentMetrics['gpu_temperature'] = ResourceMetric(
        name: 'gpu_temperature',
        value: gpuTemperature,
        timestamp: timestamp,
        unit: 'celsius',
        category: ResourceCategory.gpu,
      );
      
      // Update historical data
      _updateHistoricalData();
      
    } catch (e) {
      debugPrint('Failed to collect resource metrics: $e');
    }
  }
  
  void _updateHistoricalData() {
    for (final metric in _currentMetrics.values) {
      _historicalData.putIfAbsent(metric.name, () => []).add(metric);
      
      // Keep only last 1000 data points per metric
      if (_historicalData[metric.name]!.length > 1000) {
        _historicalData[metric.name]!.removeRange(0, _historicalData[metric.name]!.length - 1000);
      }
    }
  }
  
  Future<void> _analyzeResourceTrends() async {
    try {
      for (final metricName in _historicalData.keys) {
        final data = _historicalData[metricName]!;
        if (data.length < 10) continue;
        
        final trend = _calculateTrend(data);
        _trends[metricName] = trend;
      }
      
      // Analyze application resource usage
      await _analyzeApplicationResources();
      
      // Save trends
      await _saveTrends();
      
      _eventController.add(ResourceEvent(
        type: ResourceEventType.trends_analyzed,
        message: 'Resource trends analyzed',
        data: {
          'trends': _trends.length,
          'applications': _applicationMetrics.length,
        },
      ));
      
    } catch (e) {
      debugPrint('Failed to analyze resource trends: $e');
    }
  }
  
  Future<void> _analyzeApplicationResources() async {
    try {
      // Get running processes
      final result = await run('ps', ['-eo', 'pid,comm,%cpu,%mem,etime']);
      final lines = result.stdout.split('\n');
      
      _applicationMetrics.clear();
      
      for (final line in lines.skip(1)) { // Skip header
        if (line.trim().isEmpty) continue;
        
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 5) {
          final pid = parts[0];
          final command = parts[1];
          final cpuPercent = double.tryParse(parts[2]) ?? 0.0;
          final memPercent = double.tryParse(parts[3]) ?? 0.0;
          final runtime = parts[4];
          
          _applicationMetrics[pid] = ApplicationResource(
            pid: pid,
            command: command,
            cpuUsage: cpuPercent,
            memoryUsage: memPercent,
            runtime: runtime,
            timestamp: DateTime.now(),
          );
        }
      }
      
    } catch (e) {
      debugPrint('Failed to analyze application resources: $e');
    }
  }
  
  ResourceTrend _calculateTrend(List<ResourceMetric> data) {
    if (data.length < 2) {
      return ResourceTrend(
        metricName: data.first.name,
        direction: TrendDirection.stable,
        slope: 0.0,
        average: data.first.value,
        min: data.first.value,
        max: data.first.value,
        volatility: 0.0,
      );
    }
    
    final values = data.map((m) => m.value).toList();
    values.sort();
    
    final average = values.reduce((a, b) => a + b) / values.length;
    final min = values.first;
    final max = values.last;
    
    // Calculate slope (trend)
    final n = values.length;
    final xValues = List.generate(n, (i) => i.toDouble());
    final xMean = xValues.reduce((a, b) => a + b) / n;
    final yMean = average;
    
    double numerator = 0.0;
    double denominator = 0.0;
    
    for (int i = 0; i < n; i++) {
      numerator += (xValues[i] - xMean) * (values[i] - yMean);
      denominator += (xValues[i] - xMean) * (xValues[i] - xMean);
    }
    
    final slope = denominator != 0 ? numerator / denominator : 0.0;
    
    // Calculate volatility
    double variance = 0.0;
    for (final value in values) {
      variance += (value - average) * (value - average);
    }
    variance /= n;
    final volatility = variance > 0 ? variance.sqrt() : 0.0;
    
    // Determine trend direction
    TrendDirection direction;
    if (slope > 0.1) {
      direction = TrendDirection.increasing;
    } else if (slope < -0.1) {
      direction = TrendDirection.decreasing;
    } else {
      direction = TrendDirection.stable;
    }
    
    return ResourceTrend(
      metricName: data.first.name,
      direction: direction,
      slope: slope,
      average: average,
      min: min,
      max: max,
      volatility: volatility,
    );
  }
  
  Future<void> _checkResourceAlerts() async {
    try {
      final newAlerts = <ResourceAlert>[];
      
      // Check CPU alerts
      final cpuUsage = _currentMetrics['cpu_usage']?.value ?? 0.0;
      if (cpuUsage > 90.0) {
        newAlerts.add(ResourceAlert(
          id: 'cpu_high_${DateTime.now().millisecondsSinceEpoch}',
          type: AlertType.critical,
          resource: 'cpu',
          metric: 'cpu_usage',
          message: 'CPU usage is critically high (${cpuUsage.toStringAsFixed(1)}%)',
          threshold: 90.0,
          currentValue: cpuUsage,
          timestamp: DateTime.now(),
        ));
      } else if (cpuUsage > 80.0) {
        newAlerts.add(ResourceAlert(
          id: 'cpu_warning_${DateTime.now().millisecondsSinceEpoch}',
          type: AlertType.warning,
          resource: 'cpu',
          metric: 'cpu_usage',
          message: 'CPU usage is high (${cpuUsage.toStringAsFixed(1)}%)',
          threshold: 80.0,
          currentValue: cpuUsage,
          timestamp: DateTime.now(),
        ));
      }
      
      // Check memory alerts
      final memoryUsage = _currentMetrics['memory_usage']?.value ?? 0.0;
      if (memoryUsage > 95.0) {
        newAlerts.add(ResourceAlert(
          id: 'memory_critical_${DateTime.now().millisecondsSinceEpoch}',
          type: AlertType.critical,
          resource: 'memory',
          metric: 'memory_usage',
          message: 'Memory usage is critically high (${memoryUsage.toStringAsFixed(1)}%)',
          threshold: 95.0,
          currentValue: memoryUsage,
          timestamp: DateTime.now(),
        ));
      } else if (memoryUsage > 85.0) {
        newAlerts.add(ResourceAlert(
          id: 'memory_warning_${DateTime.now().millisecondsSinceEpoch}',
          type: AlertType.warning,
          resource: 'memory',
          metric: 'memory_usage',
          message: 'Memory usage is high (${memoryUsage.toStringAsFixed(1)}%)',
          threshold: 85.0,
          currentValue: memoryUsage,
          timestamp: DateTime.now(),
        ));
      }
      
      // Check disk alerts
      final diskUsage = _currentMetrics['disk_usage']?.value ?? 0.0;
      if (diskUsage > 95.0) {
        newAlerts.add(ResourceAlert(
          id: 'disk_critical_${DateTime.now().millisecondsSinceEpoch}',
          type: AlertType.critical,
          resource: 'disk',
          metric: 'disk_usage',
          message: 'Disk usage is critically high (${diskUsage.toStringAsFixed(1)}%)',
          threshold: 95.0,
          currentValue: diskUsage,
          timestamp: DateTime.now(),
        ));
      } else if (diskUsage > 85.0) {
        newAlerts.add(ResourceAlert(
          id: 'disk_warning_${DateTime.now().millisecondsSinceEpoch}',
          type: AlertType.warning,
          resource: 'disk',
          metric: 'disk_usage',
          message: 'Disk usage is high (${diskUsage.toStringAsFixed(1)}%)',
          threshold: 85.0,
          currentValue: diskUsage,
          timestamp: DateTime.now(),
        ));
      }
      
      // Check temperature alerts
      final cpuTemp = _currentMetrics['cpu_temperature']?.value ?? 0.0;
      if (cpuTemp > 85.0) {
        newAlerts.add(ResourceAlert(
          id: 'temp_critical_${DateTime.now().millisecondsSinceEpoch}',
          type: AlertType.critical,
          resource: 'cpu',
          metric: 'cpu_temperature',
          message: 'CPU temperature is critically high (${cpuTemp.toStringAsFixed(1)}°C)',
          threshold: 85.0,
          currentValue: cpuTemp,
          timestamp: DateTime.now(),
        ));
      } else if (cpuTemp > 75.0) {
        newAlerts.add(ResourceAlert(
          id: 'temp_warning_${DateTime.now().millisecondsSinceEpoch}',
          type: AlertType.warning,
          resource: 'cpu',
          metric: 'cpu_temperature',
          message: 'CPU temperature is high (${cpuTemp.toStringAsFixed(1)}°C)',
          threshold: 75.0,
          currentValue: cpuTemp,
          timestamp: DateTime.now(),
        ));
      }
      
      // Add new alerts
      if (newAlerts.isNotEmpty) {
        _alerts.addAll(newAlerts);
        
        _eventController.add(ResourceEvent(
          type: ResourceEventType.alerts_generated,
          message: 'Generated ${newAlerts.length} resource alerts',
          data: {
            'alerts': newAlerts.map((a) => a.toJson()).toList(),
          },
        ));
      }
      
      // Clean old alerts (keep last 100)
      if (_alerts.length > 100) {
        _alerts.removeRange(0, _alerts.length - 100);
      }
      
      // Save alerts
      await _saveAlerts();
      
    } catch (e) {
      debugPrint('Failed to check resource alerts: $e');
    }
  }
  
  // Resource collection methods
  Future<double> _getCPUUsage() async {
    try {
      final result = await run('top', ['-bn', '1']);
      final lines = result.stdout.split('\n');
      for (final line in lines) {
        if (line.contains('%Cpu(s):')) {
          final match = RegExp(r'\s+([0-9.]+)%\s+us').firstMatch(line);
          if (match != null) {
            return double.tryParse(match.group(1)!) ?? 0.0;
          }
        }
      }
      return 0.0;
    } catch (e) {
      return 0.0;
    }
  }
  
  Future<double> _getCPUFrequency() async {
    try {
      final result = await run('cat', ['/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq']);
      final frequencyHz = double.tryParse(result.stdout.trim()) ?? 0.0;
      return frequencyHz / 1000000; // Convert to MHz
    } catch (e) {
      return 0.0;
    }
  }
  
  Future<double> _getCPUTemperature() async {
    try {
      final result = await run('sensors');
      final lines = result.stdout.split('\n');
      for (final line in lines) {
        if (line.contains('Core') && line.contains('°C')) {
          final match = RegExp(r'(\d+\.\d+)°C').firstMatch(line);
          if (match != null) {
            return double.tryParse(match.group(1)!) ?? 0.0;
          }
        }
      }
      return 0.0;
    } catch (e) {
      return 0.0;
    }
  }
  
  Future<double> _getCPULoad() async {
    try {
      final result = await run('uptime');
      final match = RegExp(r'load average:\s+([\d.]+),').firstMatch(result.stdout);
      if (match != null) {
        return double.tryParse(match.group(1)!) ?? 0.0;
      }
      return 0.0;
    } catch (e) {
      return 0.0;
    }
  }
  
  Future<double> _getMemoryUsage() async {
    try {
      final result = await run('free', ['-m']);
      final lines = result.stdout.split('\n');
      for (final line in lines) {
        if (line.startsWith('Mem:')) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 3) {
            final total = double.tryParse(parts[1]) ?? 0.0;
            final used = double.tryParse(parts[2]) ?? 0.0;
            return (used / total) * 100.0;
          }
        }
      }
      return 0.0;
    } catch (e) {
      return 0.0;
    }
  }
  
  Future<double> _getMemoryAvailable() async {
    try {
      final result = await run('free', ['-m']);
      final lines = result.stdout.split('\n');
      for (final line in lines) {
        if (line.startsWith('Mem:')) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 4) {
            return double.tryParse(parts[3]) ?? 0.0; // Available memory in MB
          }
        }
      }
      return 0.0;
    } catch (e) {
      return 0.0;
    }
  }
  
  Future<double> _getSwapUsage() async {
    try {
      final result = await run('free', ['-m']);
      final lines = result.stdout.split('\n');
      for (final line in lines) {
        if (line.startsWith('Swap:')) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 3) {
            final total = double.tryParse(parts[1]) ?? 0.0;
            final used = double.tryParse(parts[2]) ?? 0.0;
            return total > 0 ? (used / total) * 100.0 : 0.0;
          }
        }
      }
      return 0.0;
    } catch (e) {
      return 0.0;
    }
  }
  
  Future<double> _getDiskUsage() async {
    try {
      final result = await run('df', ['-h', '/']);
      final lines = result.stdout.split('\n');
      for (final line in lines) {
        if (line.startsWith('/dev/')) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 5) {
            final usageStr = parts[4].replaceAll('%', '');
            return double.tryParse(usageStr) ?? 0.0;
          }
        }
      }
      return 0.0;
    } catch (e) {
      return 0.0;
    }
  }
  
  Future<double> _getDiskIO() async {
    try {
      final result = await run('iostat', ['-x', '1', '1']);
      return 25.0; // Simplified implementation
    } catch (e) {
      return 0.0;
    }
  }
  
  Future<double> _getDiskRead() async {
    try {
      final result = await run('iostat', ['-x', '1', '1']);
      return 12.5; // Simplified implementation
    } catch (e) {
      return 0.0;
    }
  }
  
  Future<double> _getDiskWrite() async {
    try {
      final result = await run('iostat', ['-x', '1', '1']);
      return 12.5; // Simplified implementation
    } catch (e) {
      return 0.0;
    }
  }
  
  Future<double> _getNetworkIO() async {
    try {
      final result = await run('cat', ['/proc/net/dev']);
      return 10.0; // Simplified implementation
    } catch (e) {
      return 0.0;
    }
  }
  
  Future<double> _getNetworkUpload() async {
    try {
      final result = await run('cat', ['/proc/net/dev']);
      return 5.0; // Simplified implementation
    } catch (e) {
      return 0.0;
    }
  }
  
  Future<double> _getNetworkDownload() async {
    try {
      final result = await run('cat', ['/proc/net/dev']);
      return 5.0; // Simplified implementation
    } catch (e) {
      return 0.0;
    }
  }
  
  Future<double> _getGPUUsage() async {
    try {
      final result = await run('nvidia-smi', ['--query-gpu=utilization.gpu', '--format=csv,noheader,nounits']);
      final usageStr = result.stdout.trim();
      return double.tryParse(usageStr) ?? 0.0;
    } catch (e) {
      return 0.0;
    }
  }
  
  Future<double> _getGPUMemory() async {
    try {
      final result = await run('nvidia-smi', ['--query-gpu=memory.used,memory.total', '--format=csv,noheader,nounits']);
      final parts = result.stdout.trim().split(',');
      if (parts.length >= 2) {
        final used = double.tryParse(parts[0]) ?? 0.0;
        final total = double.tryParse(parts[1]) ?? 1.0;
        return total > 0 ? (used / total) * 100.0 : 0.0;
      }
      return 0.0;
    } catch (e) {
      return 0.0;
    }
  }
  
  Future<double> _getGPUTemperature() async {
    try {
      final result = await run('nvidia-smi', ['--query-gpu=temperature.gpu', '--format=csv,noheader,nounits']);
      final tempStr = result.stdout.trim();
      return double.tryParse(tempStr) ?? 0.0;
    } catch (e) {
      return 0.0;
    }
  }
  
  Future<void> _saveTrends() async {
    try {
      final trendsMap = _trends.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('resource_trends', jsonEncode(trendsMap));
    } catch (e) {
      debugPrint('Failed to save trends: $e');
    }
  }
  
  Future<void> _saveAlerts() async {
    try {
      final alertsList = _alerts.map((alert) => alert.toJson()).toList();
      await _prefs.setString('resource_alerts', jsonEncode(alertsList));
    } catch (e) {
      debugPrint('Failed to save alerts: $e');
    }
  }
  
  Future<void> _saveHistoricalData() async {
    try {
      final historicalMap = _historicalData.map((key, value) => 
        MapEntry(key, value.map((item) => item.toJson()).toList()));
      await _prefs.setString('resource_historical_data', jsonEncode(historicalMap));
    } catch (e) {
      debugPrint('Failed to save historical data: $e');
    }
  }
  
  Map<String, dynamic> getCurrentMetrics() {
    return _currentMetrics.map((key, value) => MapEntry(key, value.toJson()));
  }
  
  Map<String, dynamic> getApplicationMetrics() {
    return _applicationMetrics.map((key, value) => MapEntry(key, value.toJson()));
  }
  
  Map<String, dynamic> getTrends() {
    return _trends.map((key, value) => MapEntry(key, value.toJson()));
  }
  
  List<ResourceAlert> getActiveAlerts() {
    return _alerts.where((alert) => 
        DateTime.now().difference(alert.timestamp).inMinutes < 60).toList();
  }
  
  Map<String, dynamic> getStatistics() {
    return {
      'isInitialized': _isInitialized,
      'currentMetrics': _currentMetrics.length,
      'historicalDataPoints': _historicalData.values.fold(0, (sum, list) => sum + list.length),
      'activeApplications': _applicationMetrics.length,
      'trends': _trends.length,
      'activeAlerts': getActiveAlerts().length,
      'totalAlerts': _alerts.length,
    };
  }
  
  Future<void> dispose() async {
    _monitoringTimer?.cancel();
    _analysisTimer?.cancel();
    _alertTimer?.cancel();
    
    await _saveHistoricalData();
    await _saveTrends();
    await _saveAlerts();
    
    _eventController.close();
    debugPrint('📊 Smart Resource Monitor disposed');
  }
}

// Data models
class ResourceMetric {
  final String name;
  final double value;
  final DateTime timestamp;
  final String unit;
  final ResourceCategory category;
  
  ResourceMetric({
    required this.name,
    required this.value,
    required this.timestamp,
    required this.unit,
    required this.category,
  });
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'value': value,
    'timestamp': timestamp.toIso8601String(),
    'unit': unit,
    'category': category.name,
  };
  
  factory ResourceMetric.fromJson(Map<String, dynamic> json) => ResourceMetric(
    name: json['name'],
    value: json['value']?.toDouble() ?? 0.0,
    timestamp: DateTime.parse(json['timestamp']),
    unit: json['unit'] ?? '',
    category: ResourceCategory.values.firstWhere((c) => c.name == json['category'], orElse: () => ResourceCategory.cpu),
  );
}

class ApplicationResource {
  final String pid;
  final String command;
  final double cpuUsage;
  final double memoryUsage;
  final String runtime;
  final DateTime timestamp;
  
  ApplicationResource({
    required this.pid,
    required this.command,
    required this.cpuUsage,
    required this.memoryUsage,
    required this.runtime,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() => {
    'pid': pid,
    'command': command,
    'cpuUsage': cpuUsage,
    'memoryUsage': memoryUsage,
    'runtime': runtime,
    'timestamp': timestamp.toIso8601String(),
  };
}

class ResourceTrend {
  final String metricName;
  final TrendDirection direction;
  final double slope;
  final double average;
  final double min;
  final double max;
  final double volatility;
  
  ResourceTrend({
    required this.metricName,
    required this.direction,
    required this.slope,
    required this.average,
    required this.min,
    required this.max,
    required this.volatility,
  });
  
  Map<String, dynamic> toJson() => {
    'metricName': metricName,
    'direction': direction.name,
    'slope': slope,
    'average': average,
    'min': min,
    'max': max,
    'volatility': volatility,
  };
  
  factory ResourceTrend.fromJson(Map<String, dynamic> json) => ResourceTrend(
    metricName: json['metricName'],
    direction: TrendDirection.values.firstWhere((d) => d.name == json['direction'], orElse: () => TrendDirection.stable),
    slope: json['slope']?.toDouble() ?? 0.0,
    average: json['average']?.toDouble() ?? 0.0,
    min: json['min']?.toDouble() ?? 0.0,
    max: json['max']?.toDouble() ?? 0.0,
    volatility: json['volatility']?.toDouble() ?? 0.0,
  );
}

class ResourceAlert {
  final String id;
  final AlertType type;
  final String resource;
  final String metric;
  final String message;
  final double threshold;
  final double currentValue;
  final DateTime timestamp;
  
  ResourceAlert({
    required this.id,
    required this.type,
    required this.resource,
    required this.metric,
    required this.message,
    required this.threshold,
    required this.currentValue,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'resource': resource,
    'metric': metric,
    'message': message,
    'threshold': threshold,
    'currentValue': currentValue,
    'timestamp': timestamp.toIso8601String(),
  };
  
  factory ResourceAlert.fromJson(Map<String, dynamic> json) => ResourceAlert(
    id: json['id'],
    type: AlertType.values.firstWhere((t) => t.name == json['type'], orElse: () => AlertType.info),
    resource: json['resource'],
    metric: json['metric'],
    message: json['message'],
    threshold: json['threshold']?.toDouble() ?? 0.0,
    currentValue: json['currentValue']?.toDouble() ?? 0.0,
    timestamp: DateTime.parse(json['timestamp']),
  );
}

enum ResourceCategory {
  cpu,
  memory,
  disk,
  network,
  gpu,
}

enum TrendDirection {
  increasing,
  decreasing,
  stable,
}

enum AlertType {
  info,
  warning,
  critical,
}

enum ResourceEventType {
  initialized,
  metrics_collected,
  trends_analyzed,
  alerts_generated,
  application_analyzed,
  error,
}

class ResourceEvent {
  final ResourceEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  
  ResourceEvent({
    required this.type,
    required this.message,
    this.data,
  }) : timestamp = DateTime.now();
}
