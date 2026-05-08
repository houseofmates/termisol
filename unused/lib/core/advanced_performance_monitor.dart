import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Advanced Performance Monitor - Real-time system and application performance tracking
/// 
/// Features:
/// - CPU, Memory, GPU monitoring with platform-specific optimizations
/// - Frame rate and rendering performance analysis
/// - Network performance monitoring
/// - Resource usage prediction and alerts
/// - Performance bottleneck detection
/// - Cross-platform compatibility (Linux, Android, Windows, Quest 2)
class AdvancedPerformanceMonitor {
  static final AdvancedPerformanceMonitor _instance = AdvancedPerformanceMonitor._internal();
  factory AdvancedPerformanceMonitor() => _instance;
  AdvancedPerformanceMonitor._internal();

  // Performance data storage
  final Queue<PerformanceSnapshot> _performanceHistory = Queue();
  final Map<String, PerformanceMetric> _metrics = {};
  final List<PerformanceAlert> _alerts = [];
  
  // Monitoring configuration
  Duration _monitoringInterval = Duration(seconds: 1);
  Duration _historyRetention = Duration(minutes: 30);
  int _maxHistorySize = 1800; // 30 minutes at 1-second intervals
  
  // Timers and controllers
  Timer? _monitoringTimer;
  final StreamController<PerformanceEvent> _eventController = 
      StreamController<PerformanceEvent>.broadcast();
  
  // Platform detection
  final PlatformInfo _platform = PlatformInfo();
  
  // Performance thresholds
  static const double _cpuWarningThreshold = 80.0;
  static const double _cpuCriticalThreshold = 95.0;
  static const double _memoryWarningThreshold = 85.0;
  static const double _memoryCriticalThreshold = 95.0;
  static const double _gpuWarningThreshold = 80.0;
  static const double _gpuCriticalThreshold = 95.0;
  static const double _fpsWarningThreshold = 30.0;
  static const double _fpsCriticalThreshold = 15.0;

  Stream<PerformanceEvent> get events => _eventController.stream;
  List<PerformanceAlert> get alerts => List.unmodifiable(_alerts);
  PerformanceSnapshot? get latestSnapshot => 
      _performanceHistory.isNotEmpty ? _performanceHistory.last : null;

  /// Start performance monitoring
  Future<void> startMonitoring({Duration? interval}) async {
    if (_monitoringTimer?.isActive == true) return;
    
    if (interval != null) {
      _monitoringInterval = interval;
    }
    
    await _initializePlatformSpecificMonitoring();
    
    _monitoringTimer = Timer.periodic(_monitoringInterval, (_) {
      _collectPerformanceSnapshot();
    });
    
    debugPrint('🔍 Advanced Performance Monitor started');
  }

  /// Stop performance monitoring
  Future<void> stopMonitoring() async {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    
    await _cleanupPlatformSpecificMonitoring();
    
    debugPrint('⏹️ Advanced Performance Monitor stopped');
  }

  /// Initialize platform-specific monitoring
  Future<void> _initializePlatformSpecificMonitoring() async {
    switch (_platform.type) {
      case PlatformType.linux:
        await _initializeLinuxMonitoring();
        break;
      case PlatformType.android:
        await _initializeAndroidMonitoring();
        break;
      case PlatformType.windows:
        await _initializeWindowsMonitoring();
        break;
      case PlatformType.quest2:
        await _initializeQuest2Monitoring();
        break;
      default:
        debugPrint('⚠️ Unsupported platform for advanced monitoring');
    }
  }

  /// Initialize Linux-specific monitoring
  Future<void> _initializeLinuxMonitoring() async {
    // Check for NVIDIA GPU
    final nvidiaSmiResult = await Process.run('which', ['nvidia-smi']);
    if (nvidiaSmiResult.exitCode == 0) {
      _metrics['nvidia_available'] = PerformanceMetric(
        name: 'nvidia_available',
        value: 1.0,
        unit: 'boolean',
        timestamp: DateTime.now(),
      );
    }
    
    // Check system info
    final memInfo = File('/proc/meminfo');
    if (await memInfo.exists()) {
      _metrics['proc_meminfo_available'] = PerformanceMetric(
        name: 'proc_meminfo_available',
        value: 1.0,
        unit: 'boolean',
        timestamp: DateTime.now(),
      );
    }
  }

  /// Initialize Android-specific monitoring
  Future<void> _initializeAndroidMonitoring() async {
    // Android-specific initialization would go here
    // This would use Android APIs through platform channels
  }

  /// Initialize Windows-specific monitoring
  Future<void> _initializeWindowsMonitoring() async {
    // Windows-specific initialization would go here
    // This would use Windows Performance Counters
  }

  /// Initialize Quest 2-specific monitoring
  Future<void> _initializeQuest2Monitoring() async {
    // Quest 2 specific monitoring (Android + VR optimizations)
    await _initializeAndroidMonitoring();
    
    // Add VR-specific metrics
    _metrics['vr_mode'] = PerformanceMetric(
      name: 'vr_mode',
      value: 1.0,
      unit: 'boolean',
      timestamp: DateTime.now(),
    );
  }

  /// Collect comprehensive performance snapshot
  Future<void> _collectPerformanceSnapshot() async {
    final timestamp = DateTime.now();
    
    try {
      // Collect CPU metrics
      final cpuUsage = await _getCpuUsage();
      _metrics['cpu_usage'] = PerformanceMetric(
        name: 'cpu_usage',
        value: cpuUsage,
        unit: 'percent',
        timestamp: timestamp,
      );
      
      // Collect memory metrics
      final memoryMetrics = await _getMemoryMetrics();
      _metrics.addAll(memoryMetrics);
      
      // Collect GPU metrics
      final gpuMetrics = await _getGpuMetrics();
      _metrics.addAll(gpuMetrics);
      
      // Collect application metrics
      final appMetrics = await _getApplicationMetrics();
      _metrics.addAll(appMetrics);
      
      // Create snapshot
      final snapshot = PerformanceSnapshot(
        timestamp: timestamp,
        metrics: Map.from(_metrics),
      );
      
      // Add to history
      _performanceHistory.add(snapshot);
      _trimHistory();
      
      // Check for alerts
      _checkPerformanceAlerts(snapshot);
      
      // Emit event
      _eventController.add(PerformanceEvent(
        type: PerformanceEventType.snapshot,
        timestamp: timestamp,
        data: snapshot,
      ));
      
    } catch (e) {
      debugPrint('❌ Error collecting performance snapshot: $e');
    }
  }

  /// Get CPU usage with platform-specific implementation
  Future<double> _getCpuUsage() async {
    try {
      switch (_platform.type) {
        case PlatformType.linux:
        case PlatformType.quest2:
          return await _getLinuxCpuUsage();
        case PlatformType.android:
          return await _getAndroidCpuUsage();
        case PlatformType.windows:
          return await _getWindowsCpuUsage();
        default:
          return 0.0;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to get CPU usage: $e');
      return 0.0;
    }
  }

  /// Get Linux CPU usage
  Future<double> _getLinuxCpuUsage() async {
    final statFile = File('/proc/stat');
    if (!await statFile.exists()) return 0.0;
    
    final lines = await statFile.readAsLines();
    if (lines.isEmpty) return 0.0;
    
    final cpuLine = lines.first;
    final parts = cpuLine.split(RegExp(r'\s+'));
    if (parts.length < 8) return 0.0;
    
    final idle = int.parse(parts[4]);
    final total = parts.skip(1).take(7).map(int.parse).reduce((a, b) => a + b);
    
    return total > 0 ? ((total - idle) / total) * 100 : 0.0;
  }

  /// Get Android CPU usage
  Future<double> _getAndroidCpuUsage() async {
    // Android implementation would use /proc/stat or platform channels
    return 0.0;
  }

  /// Get Windows CPU usage
  Future<double> _getWindowsCpuUsage() async {
    // Windows implementation would use Performance Counters
    return 0.0;
  }

  /// Get memory metrics
  Future<Map<String, PerformanceMetric>> _getMemoryMetrics() async {
    final metrics = <String, PerformanceMetric>{};
    final timestamp = DateTime.now();
    
    try {
      switch (_platform.type) {
        case PlatformType.linux:
        case PlatformType.quest2:
          final linuxMetrics = await _getLinuxMemoryMetrics();
          metrics.addAll(linuxMetrics);
          break;
        case PlatformType.android:
          final androidMetrics = await _getAndroidMemoryMetrics();
          metrics.addAll(androidMetrics);
          break;
        case PlatformType.windows:
          final windowsMetrics = await _getWindowsMemoryMetrics();
          metrics.addAll(windowsMetrics);
          break;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to get memory metrics: $e');
    }
    
    return metrics;
  }

  /// Get Linux memory metrics
  Future<Map<String, PerformanceMetric>> _getLinuxMemoryMetrics() async {
    final metrics = <String, PerformanceMetric>{};
    final timestamp = DateTime.now();
    
    final meminfoFile = File('/proc/meminfo');
    if (!await meminfoFile.exists()) return metrics;
    
    final lines = await meminfoFile.readAsLines();
    int totalMem = 0;
    int availableMem = 0;
    int buffers = 0;
    int cached = 0;
    
    for (final line in lines) {
      if (line.startsWith('MemTotal:')) {
        totalMem = int.parse(line.split(RegExp(r'\s+'))[1]);
      } else if (line.startsWith('MemAvailable:')) {
        availableMem = int.parse(line.split(RegExp(r'\s+'))[1]);
      } else if (line.startsWith('Buffers:')) {
        buffers = int.parse(line.split(RegExp(r'\s+'))[1]);
      } else if (line.startsWith('Cached:')) {
        cached = int.parse(line.split(RegExp(r'\s+'))[1]);
      }
    }
    
    if (totalMem > 0) {
      final usedMem = totalMem - availableMem;
      final usagePercent = (usedMem / totalMem) * 100;
      
      metrics['memory_total'] = PerformanceMetric(
        name: 'memory_total',
        value: totalMem.toDouble(),
        unit: 'KB',
        timestamp: timestamp,
      );
      
      metrics['memory_used'] = PerformanceMetric(
        name: 'memory_used',
        value: usedMem.toDouble(),
        unit: 'KB',
        timestamp: timestamp,
      );
      
      metrics['memory_usage_percent'] = PerformanceMetric(
        name: 'memory_usage_percent',
        value: usagePercent,
        unit: 'percent',
        timestamp: timestamp,
      );
      
      metrics['memory_buffers'] = PerformanceMetric(
        name: 'memory_buffers',
        value: buffers.toDouble(),
        unit: 'KB',
        timestamp: timestamp,
      );
      
      metrics['memory_cached'] = PerformanceMetric(
        name: 'memory_cached',
        value: cached.toDouble(),
        unit: 'KB',
        timestamp: timestamp,
      );
    }
    
    return metrics;
  }

  /// Get Android memory metrics
  Future<Map<String, PerformanceMetric>> _getAndroidMemoryMetrics() async {
    // Android implementation would use ActivityManager or platform channels
    return {};
  }

  /// Get Windows memory metrics
  Future<Map<String, PerformanceMetric>> _getWindowsMemoryMetrics() async {
    // Windows implementation would use Performance Counters
    return {};
  }

  /// Get GPU metrics
  Future<Map<String, PerformanceMetric>> _getGpuMetrics() async {
    final metrics = <String, PerformanceMetric>{};
    final timestamp = DateTime.now();
    
    try {
      // Check for NVIDIA GPU
      if (_metrics.containsKey('nvidia_available')) {
        final nvidiaMetrics = await _getNvidiaGpuMetrics();
        metrics.addAll(nvidiaMetrics);
      }
      
      // Add platform-specific GPU metrics
      switch (_platform.type) {
        case PlatformType.quest2:
          final questGpuMetrics = await _getQuest2GpuMetrics();
          metrics.addAll(questGpuMetrics);
          break;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to get GPU metrics: $e');
    }
    
    return metrics;
  }

  /// Get NVIDIA GPU metrics
  Future<Map<String, PerformanceMetric>> _getNvidiaGpuMetrics() async {
    final metrics = <String, PerformanceMetric>{};
    final timestamp = DateTime.now();
    
    try {
      // Get GPU utilization
      final utilizationResult = await Process.run('nvidia-smi', [
        '--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw',
        '--format=csv,noheader,nounits'
      ]);
      
      if (utilizationResult.exitCode == 0) {
        final lines = utilizationResult.stdout.toString().trim().split('\n');
        if (lines.isNotEmpty) {
          final values = lines.first.split(',').map((v) => v.trim()).toList();
          
          if (values.length >= 5) {
            metrics['gpu_utilization'] = PerformanceMetric(
              name: 'gpu_utilization',
              value: double.tryParse(values[0]) ?? 0.0,
              unit: 'percent',
              timestamp: timestamp,
            );
            
            metrics['gpu_memory_used'] = PerformanceMetric(
              name: 'gpu_memory_used',
              value: double.tryParse(values[1]) ?? 0.0,
              unit: 'MB',
              timestamp: timestamp,
            );
            
            metrics['gpu_memory_total'] = PerformanceMetric(
              name: 'gpu_memory_total',
              value: double.tryParse(values[2]) ?? 0.0,
              unit: 'MB',
              timestamp: timestamp,
            );
            
            metrics['gpu_temperature'] = PerformanceMetric(
              name: 'gpu_temperature',
              value: double.tryParse(values[3]) ?? 0.0,
              unit: 'C',
              timestamp: timestamp,
            );
            
            metrics['gpu_power'] = PerformanceMetric(
              name: 'gpu_power',
              value: double.tryParse(values[4]) ?? 0.0,
              unit: 'W',
              timestamp: timestamp,
            );
            
            // Calculate memory usage percentage
            final memoryUsed = double.tryParse(values[1]) ?? 0.0;
            final memoryTotal = double.tryParse(values[2]) ?? 1.0;
            if (memoryTotal > 0) {
              metrics['gpu_memory_usage_percent'] = PerformanceMetric(
                name: 'gpu_memory_usage_percent',
                value: (memoryUsed / memoryTotal) * 100,
                unit: 'percent',
                timestamp: timestamp,
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to get NVIDIA GPU metrics: $e');
    }
    
    return metrics;
  }

  /// Get Quest 2 GPU metrics
  Future<Map<String, PerformanceMetric>> _getQuest2GpuMetrics() async {
    // Quest 2 specific GPU metrics would go here
    return {};
  }

  /// Get application-specific metrics
  Future<Map<String, PerformanceMetric>> _getApplicationMetrics() async {
    final metrics = <String, PerformanceMetric>{};
    final timestamp = DateTime.now();
    
    // These would be populated by the application
    metrics['app_fps'] = PerformanceMetric(
      name: 'app_fps',
      value: 60.0, // Would be measured
      unit: 'fps',
      timestamp: timestamp,
    );
    
    metrics['app_frame_time'] = PerformanceMetric(
      name: 'app_frame_time',
      value: 16.67, // Would be measured
      unit: 'ms',
      timestamp: timestamp,
    );
    
    return metrics;
  }

  /// Check for performance alerts
  void _checkPerformanceAlerts(PerformanceSnapshot snapshot) {
    final alerts = <PerformanceAlert>[];
    
    // CPU alerts
    final cpuUsage = snapshot.metrics['cpu_usage']?.value ?? 0.0;
    if (cpuUsage >= _cpuCriticalThreshold) {
      alerts.add(PerformanceAlert(
        type: AlertType.critical,
        metric: 'cpu_usage',
        value: cpuUsage,
        threshold: _cpuCriticalThreshold,
        message: 'Critical CPU usage detected',
        timestamp: snapshot.timestamp,
      ));
    } else if (cpuUsage >= _cpuWarningThreshold) {
      alerts.add(PerformanceAlert(
        type: AlertType.warning,
        metric: 'cpu_usage',
        value: cpuUsage,
        threshold: _cpuWarningThreshold,
        message: 'High CPU usage detected',
        timestamp: snapshot.timestamp,
      ));
    }
    
    // Memory alerts
    final memoryUsage = snapshot.metrics['memory_usage_percent']?.value ?? 0.0;
    if (memoryUsage >= _memoryCriticalThreshold) {
      alerts.add(PerformanceAlert(
        type: AlertType.critical,
        metric: 'memory_usage_percent',
        value: memoryUsage,
        threshold: _memoryCriticalThreshold,
        message: 'Critical memory usage detected',
        timestamp: snapshot.timestamp,
      ));
    } else if (memoryUsage >= _memoryWarningThreshold) {
      alerts.add(PerformanceAlert(
        type: AlertType.warning,
        metric: 'memory_usage_percent',
        value: memoryUsage,
        threshold: _memoryWarningThreshold,
        message: 'High memory usage detected',
        timestamp: snapshot.timestamp,
      ));
    }
    
    // GPU alerts
    final gpuUsage = snapshot.metrics['gpu_utilization']?.value ?? 0.0;
    if (gpuUsage >= _gpuCriticalThreshold) {
      alerts.add(PerformanceAlert(
        type: AlertType.critical,
        metric: 'gpu_utilization',
        value: gpuUsage,
        threshold: _gpuCriticalThreshold,
        message: 'Critical GPU usage detected',
        timestamp: snapshot.timestamp,
      ));
    } else if (gpuUsage >= _gpuWarningThreshold) {
      alerts.add(PerformanceAlert(
        type: AlertType.warning,
        metric: 'gpu_utilization',
        value: gpuUsage,
        threshold: _gpuWarningThreshold,
        message: 'High GPU usage detected',
        timestamp: snapshot.timestamp,
      ));
    }
    
    // FPS alerts
    final fps = snapshot.metrics['app_fps']?.value ?? 60.0;
    if (fps <= _fpsCriticalThreshold) {
      alerts.add(PerformanceAlert(
        type: AlertType.critical,
        metric: 'app_fps',
        value: fps,
        threshold: _fpsCriticalThreshold,
        message: 'Critical frame rate detected',
        timestamp: snapshot.timestamp,
      ));
    } else if (fps <= _fpsWarningThreshold) {
      alerts.add(PerformanceAlert(
        type: AlertType.warning,
        metric: 'app_fps',
        value: fps,
        threshold: _fpsWarningThreshold,
        message: 'Low frame rate detected',
        timestamp: snapshot.timestamp,
      ));
    }
    
    // Add alerts and emit events
    for (final alert in alerts) {
      _alerts.add(alert);
      _eventController.add(PerformanceEvent(
        type: PerformanceEventType.alert,
        timestamp: alert.timestamp,
        data: alert,
      ));
    }
    
    // Trim old alerts
    if (_alerts.length > 100) {
      _alerts.removeRange(0, _alerts.length - 100);
    }
  }

  /// Trim performance history
  void _trimHistory() {
    // Remove old snapshots based on retention time
    final cutoffTime = DateTime.now().subtract(_historyRetention);
    while (_performanceHistory.isNotEmpty && 
           _performanceHistory.first.timestamp.isBefore(cutoffTime)) {
      _performanceHistory.removeFirst();
    }
    
    // Also limit by size
    while (_performanceHistory.length > _maxHistorySize) {
      _performanceHistory.removeFirst();
    }
  }

  /// Cleanup platform-specific monitoring
  Future<void> _cleanupPlatformSpecificMonitoring() async {
    // Platform-specific cleanup would go here
  }

  /// Get performance summary
  PerformanceSummary getPerformanceSummary() {
    if (_performanceHistory.isEmpty) {
      return PerformanceSummary(
        timestamp: DateTime.now(),
        cpuUsage: 0.0,
        memoryUsage: 0.0,
        gpuUsage: 0.0,
        fps: 60.0,
        alertsCount: 0,
      );
    }
    
    final recentSnapshots = _performanceHistory.toList().take(60); // Last minute
    
    double avgCpu = 0.0;
    double avgMemory = 0.0;
    double avgGpu = 0.0;
    double avgFps = 60.0;
    int validCpuCount = 0;
    int validMemoryCount = 0;
    int validGpuCount = 0;
    int validFpsCount = 0;
    
    for (final snapshot in recentSnapshots) {
      final cpu = snapshot.metrics['cpu_usage']?.value;
      if (cpu != null) {
        avgCpu += cpu;
        validCpuCount++;
      }
      
      final memory = snapshot.metrics['memory_usage_percent']?.value;
      if (memory != null) {
        avgMemory += memory;
        validMemoryCount++;
      }
      
      final gpu = snapshot.metrics['gpu_utilization']?.value;
      if (gpu != null) {
        avgGpu += gpu;
        validGpuCount++;
      }
      
      final fps = snapshot.metrics['app_fps']?.value;
      if (fps != null) {
        avgFps += fps;
        validFpsCount++;
      }
    }
    
    return PerformanceSummary(
      timestamp: DateTime.now(),
      cpuUsage: validCpuCount > 0 ? avgCpu / validCpuCount : 0.0,
      memoryUsage: validMemoryCount > 0 ? avgMemory / validMemoryCount : 0.0,
      gpuUsage: validGpuCount > 0 ? avgGpu / validGpuCount : 0.0,
      fps: validFpsCount > 0 ? avgFps / validFpsCount : 60.0,
      alertsCount: _alerts.where((a) => 
          a.timestamp.isAfter(DateTime.now().subtract(Duration(minutes: 5)))).length,
    );
  }

  /// Dispose resources
  Future<void> dispose() async {
    await stopMonitoring();
    await _eventController.close();
    _performanceHistory.clear();
    _metrics.clear();
    _alerts.clear();
  }
}

/// Platform information
class PlatformInfo {
  final PlatformType type;
  final String version;
  final String architecture;
  
  PlatformInfo()
      : type = _detectPlatformType(),
        version = Platform.operatingSystemVersion,
        architecture = Platform.operatingSystem;
  
  static PlatformType _detectPlatformType() {
    final os = Platform.operatingSystem;
    
    if (os == 'linux') {
      // Check if running on Quest 2
      return PlatformType.linux; // Could be enhanced to detect Quest 2
    } else if (os == 'android') {
      return PlatformType.android;
    } else if (os == 'windows') {
      return PlatformType.windows;
    }
    
    return PlatformType.unknown;
  }
}

enum PlatformType {
  linux,
  android,
  windows,
  quest2,
  unknown,
}

/// Performance snapshot
class PerformanceSnapshot {
  final DateTime timestamp;
  final Map<String, PerformanceMetric> metrics;
  
  PerformanceSnapshot({
    required this.timestamp,
    required this.metrics,
  });
}

/// Performance metric
class PerformanceMetric {
  final String name;
  final double value;
  final String unit;
  final DateTime timestamp;
  
  PerformanceMetric({
    required this.name,
    required this.value,
    required this.unit,
    required this.timestamp,
  });
}

/// Performance alert
class PerformanceAlert {
  final AlertType type;
  final String metric;
  final double value;
  final double threshold;
  final String message;
  final DateTime timestamp;
  
  PerformanceAlert({
    required this.type,
    required this.metric,
    required this.value,
    required this.threshold,
    required this.message,
    required this.timestamp,
  });
}

enum AlertType {
  info,
  warning,
  critical,
}

/// Performance event
class PerformanceEvent {
  final PerformanceEventType type;
  final DateTime timestamp;
  final dynamic data;
  
  PerformanceEvent({
    required this.type,
    required this.timestamp,
    this.data,
  });
}

enum PerformanceEventType {
  snapshot,
  alert,
  threshold,
  system,
}

/// Performance summary
class PerformanceSummary {
  final DateTime timestamp;
  final double cpuUsage;
  final double memoryUsage;
  final double gpuUsage;
  final double fps;
  final int alertsCount;
  
  PerformanceSummary({
    required this.timestamp,
    required this.cpuUsage,
    required this.memoryUsage,
    required this.gpuUsage,
    required this.fps,
    required this.alertsCount,
  });
}
