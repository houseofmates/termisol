import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Resource Monitoring System for /monitor Command
/// 
/// Comprehensive system resource monitoring with real-time dashboard
/// and integration with AI bottleneck detection.
class ResourceMonitor {
  static final ResourceMonitor _instance = ResourceMonitor._internal();
  factory ResourceMonitor() => _instance;
  ResourceMonitor._internal();

  bool _isInitialized = false;
  
  // Monitoring state
  Timer? _monitoringTimer;
  final List<ResourceSnapshot> _history = [];
  final Map<String, ResourceAlert> _activeAlerts = {};
  
  // Resource metrics
  ResourceMetrics? _currentMetrics;
  ResourceTrends? _trends;
  
  // Configuration
  static const Duration _monitoringInterval = Duration(seconds: 5);
  static const int _maxHistorySize = 2000;
  static const int _alertThresholdSeconds = 30;
  
  // Event system
  final _monitorController = StreamController<ResourceEvent>.broadcast();
  Stream<ResourceEvent> get events => _monitorController.stream;
  
  bool get isInitialized => _isInitialized;
  ResourceMetrics? get currentMetrics => _currentMetrics;
  ResourceTrends? get trends => _trends;
  int get historySize => _history.length;
  int get activeAlerts => _activeAlerts.length;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Load monitoring configuration
      await _loadConfiguration();
      
      // Start monitoring
      _startMonitoring();
      
      _isInitialized = true;
      debugPrint('📊 Resource Monitor initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Resource Monitor: $e');
    }
  }

  Future<void> _loadConfiguration() async {
    // Load configuration from file or use defaults
    // Configuration includes alert thresholds, monitoring intervals, etc.
  }

  void _startMonitoring() {
    _monitoringTimer = Timer.periodic(_monitoringInterval, (_) {
      _collectMetrics();
    });
    
    debugPrint('📊 Started resource monitoring');
  }

  Future<void> _collectMetrics() async {
    try {
      final metrics = await _captureResourceMetrics();
      _currentMetrics = metrics;
      
      // Add to history
      _history.add(ResourceSnapshot(
        timestamp: DateTime.now(),
        metrics: metrics,
      ));
      
      // Limit history size
      if (_history.length > _maxHistorySize) {
        _history.removeAt(0);
      }
      
      // Update trends
      _updateTrends();
      
      // Check for alerts
      _checkAlerts(metrics);
      
      // Emit update event
      _monitorController.add(ResourceEvent(
        type: ResourceEventType.metricsUpdated,
        metrics: metrics,
      ));
      
    } catch (e) {
      debugPrint('⚠️ Failed to collect resource metrics: $e');
    }
  }

  Future<ResourceMetrics> _captureResourceMetrics() async {
    final timestamp = DateTime.now();
    final metrics = <String, double>{};
    
    try {
      // CPU Usage
      final cpuResult = await Process.run('top', ['-bn1'], runInShell: true);
      if (cpuResult.exitCode == 0) {
        final cpuOutput = cpuResult.stdout as String;
        final cpuLines = cpuOutput.split('\n');
        
        double totalCpu = 0.0;
        int cpuCount = 0;
        
        for (final line in cpuLines) {
          if (line.contains('%Cpu(s):')) {
            final match = RegExp(r'(\d+\.\d+)\s%us').firstMatch(line);
            if (match != null) {
              totalCpu += double.parse(match.group(1)!);
              cpuCount++;
            }
          }
        }
        
        metrics['cpu_percent'] = cpuCount > 0 ? totalCpu / cpuCount : 0.0;
      }
      
      // Memory Usage
      final memResult = await Process.run('free', ['-m'], runInShell: true);
      if (memResult.exitCode == 0) {
        final memOutput = memResult.stdout as String;
        final memLines = memOutput.split('\n');
        
        for (final line in memLines) {
          if (line.startsWith('Mem:')) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 3) {
              final total = double.parse(parts[1]);
              final used = double.parse(parts[2]);
              final available = double.parse(parts[6]);
              
              metrics['memory_total_mb'] = total;
              metrics['memory_used_mb'] = used;
              metrics['memory_available_mb'] = available;
              metrics['memory_percent'] = (used / total) * 100;
            }
            break;
          }
        }
      }
      
      // Swap Usage
      final swapResult = await Process.run('free', ['-m'], runInShell: true);
      if (swapResult.exitCode == 0) {
        final swapOutput = swapResult.stdout as String;
        final swapLines = swapOutput.split('\n');
        
        for (final line in swapLines) {
          if (line.startsWith('Swap:')) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 3) {
              final total = double.parse(parts[1]);
              final used = double.parse(parts[2]);
              
              metrics['swap_total_mb'] = total;
              metrics['swap_used_mb'] = used;
              metrics['swap_percent'] = total > 0 ? (used / total) * 100 : 0.0;
            }
            break;
          }
        }
      }
      
      // Disk Usage
      final diskResult = await Process.run('df', ['-h', '/'], runInShell: true);
      if (diskResult.exitCode == 0) {
        final diskOutput = diskResult.stdout as String;
        final diskLines = diskOutput.split('\n');
        
        for (final line in diskLines) {
          if (line.startsWith('/') && !line.startsWith('Filesystem')) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 5) {
              final total = parts[1];
              final used = parts[2];
              final available = parts[3];
              final usageStr = parts[4].replaceAll('%', '');
              
              metrics['disk_total'] = _parseDiskSize(total);
              metrics['disk_used'] = _parseDiskSize(used);
              metrics['disk_available'] = _parseDiskSize(available);
              metrics['disk_percent'] = double.tryParse(usageStr) ?? 0.0;
            }
            break;
          }
        }
      }
      
      // Network I/O
      try {
        final netResult = await Process.run('cat', ['/proc/net/dev'], runInShell: true);
        if (netResult.exitCode == 0) {
          final netOutput = netResult.stdout as String;
          final netLines = netOutput.split('\n');
          
          double totalRxBytes = 0.0;
          double totalTxBytes = 0.0;
          
          for (final line in netLines) {
            if (line.contains(':') && !line.startsWith('Inter-') && !line.startsWith('face')) {
              final parts = line.split(RegExp(r'\s+'));
              if (parts.length >= 10) {
                totalRxBytes += double.tryParse(parts[2]) ?? 0.0;
                totalTxBytes += double.tryParse(parts[10]) ?? 0.0;
              }
            }
          }
          
          metrics['network_rx_bytes'] = totalRxBytes;
          metrics['network_tx_bytes'] = totalTxBytes;
        }
      } catch (e) {
        // Network monitoring not available
      }
      
      // Process Information
      final processResult = await Process.run('ps', ['aux'], runInShell: true);
      if (processResult.exitCode == 0) {
        final processOutput = processResult.stdout as String;
        final processLines = processOutput.split('\n');
        
        int totalProcesses = 0;
        int runningProcesses = 0;
        int sleepingProcesses = 0;
        double totalCpu = 0.0;
        double totalMem = 0.0;
        
        for (final line in processLines.skip(1)) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 8) {
            totalProcesses++;
            
            final state = parts[7];
            if (state == 'R') runningProcesses++;
            else if (state == 'S') sleepingProcesses++;
            
            final cpu = double.tryParse(parts[2]) ?? 0.0;
            final mem = double.tryParse(parts[3]) ?? 0.0;
            
            totalCpu += cpu;
            totalMem += mem;
          }
        }
        
        metrics['process_total'] = totalProcesses.toDouble();
        metrics['process_running'] = runningProcesses.toDouble();
        metrics['process_sleeping'] = sleepingProcesses.toDouble();
        metrics['process_avg_cpu'] = totalProcesses > 0 ? totalCpu / totalProcesses : 0.0;
        metrics['process_avg_mem'] = totalProcesses > 0 ? totalMem / totalProcesses : 0.0;
      }
      
      // Temperature (if available)
      try {
        final tempResult = await Process.run('sensors', [], runInShell: true);
        if (tempResult.exitCode == 0) {
          final tempOutput = tempResult.stdout as String;
          final tempLines = tempOutput.split('\n');
          
          double maxCpuTemp = 0.0;
          double maxGpuTemp = 0.0;
          double maxSystemTemp = 0.0;
          
          for (final line in tempLines) {
            if (line.contains('°C')) {
              final match = RegExp(r'(\d+\.\d+)°C').firstMatch(line);
              if (match != null) {
                final temp = double.parse(match.group(1)!);
                
                if (line.toLowerCase().contains('core') || line.toLowerCase().contains('cpu')) {
                  maxCpuTemp = math.max(maxCpuTemp, temp);
                } else if (line.toLowerCase().contains('gpu')) {
                  maxGpuTemp = math.max(maxGpuTemp, temp);
                } else {
                  maxSystemTemp = math.max(maxSystemTemp, temp);
                }
              }
            }
          }
          
          if (maxCpuTemp > 0) metrics['cpu_temp'] = maxCpuTemp;
          if (maxGpuTemp > 0) metrics['gpu_temp'] = maxGpuTemp;
          if (maxSystemTemp > 0) metrics['system_temp'] = maxSystemTemp;
        }
      } catch (e) {
        // Temperature monitoring not available
      }
      
      // System Load
      try {
        final loadResult = await Process.run('cat', ['/proc/loadavg'], runInShell: true);
        if (loadResult.exitCode == 0) {
          final loadOutput = loadResult.stdout as String;
          final parts = loadOutput.split(' ');
          
          if (parts.length >= 3) {
            metrics['load_1min'] = double.tryParse(parts[0]) ?? 0.0;
            metrics['load_5min'] = double.tryParse(parts[1]) ?? 0.0;
            metrics['load_15min'] = double.tryParse(parts[2]) ?? 0.0;
          }
        }
      } catch (e) {
        // Load monitoring not available
      }
      
      // Uptime
      try {
        final uptimeResult = await Process.run('cat', ['/proc/uptime'], runInShell: true);
        if (uptimeResult.exitCode == 0) {
          final uptimeOutput = uptimeResult.stdout as String;
          final parts = uptimeOutput.split(' ');
          
          if (parts.isNotEmpty) {
            metrics['uptime_seconds'] = double.tryParse(parts[0]) ?? 0.0;
          }
        }
      } catch (e) {
        // Uptime monitoring not available
      }
      
    } catch (e) {
      debugPrint('⚠️ Error capturing resource metrics: $e');
    }
    
    return ResourceMetrics(
      timestamp: timestamp,
      metrics: metrics,
    );
  }

  double _parseDiskSize(String sizeStr) {
    // Parse disk size string (e.g., "100G", "500M", "1T") to GB
    if (sizeStr.endsWith('G') || sizeStr.endsWith('g')) {
      return double.parse(sizeStr.substring(0, sizeStr.length - 1));
    } else if (sizeStr.endsWith('M') || sizeStr.endsWith('m')) {
      return double.parse(sizeStr.substring(0, sizeStr.length - 1)) / 1024;
    } else if (sizeStr.endsWith('T') || sizeStr.endsWith('t')) {
      return double.parse(sizeStr.substring(0, sizeStr.length - 1)) * 1024;
    } else if (sizeStr.endsWith('K') || sizeStr.endsWith('k')) {
      return double.parse(sizeStr.substring(0, sizeStr.length - 1)) / (1024 * 1024);
    }
    
    return double.tryParse(sizeStr) ?? 0.0;
  }

  void _updateTrends() {
    if (_history.length < 2) return;
    
    final recent = _history.take(10).toList();
    final older = _history.skip(10).take(10).toList();
    
    if (older.isEmpty) return;
    
    final trends = <String, TrendDirection>{};
    
    for (final metric in _currentMetrics!.metrics.keys) {
      final recentAvg = recent
          .map((s) => s.metrics[metric] ?? 0.0)
          .reduce((a, b) => a + b) / recent.length;
      
      final olderAvg = older
          .map((s) => s.metrics[metric] ?? 0.0)
          .reduce((a, b) => a + b) / older.length;
      
      final diff = recentAvg - olderAvg;
      final threshold = olderAvg * 0.1; // 10% threshold
      
      if (diff > threshold) {
        trends[metric] = TrendDirection.increasing;
      } else if (diff < -threshold) {
        trends[metric] = TrendDirection.decreasing;
      } else {
        trends[metric] = TrendDirection.stable;
      }
    }
    
    _trends = ResourceTrends(
      timestamp: DateTime.now(),
      directions: trends,
    );
  }

  void _checkAlerts(ResourceMetrics metrics) {
    final alerts = <ResourceAlert>[];
    
    // CPU Alert
    final cpuPercent = metrics.metrics['cpu_percent'] ?? 0.0;
    if (cpuPercent > 90) {
      alerts.add(ResourceAlert(
        id: 'high_cpu',
        type: ResourceType.cpu,
        severity: AlertSeverity.critical,
        message: 'CPU usage is critically high: ${cpuPercent.toStringAsFixed(1)}%',
        value: cpuPercent,
        threshold: 90.0,
      ));
    } else if (cpuPercent > 80) {
      alerts.add(ResourceAlert(
        id: 'medium_cpu',
        type: ResourceType.cpu,
        severity: AlertSeverity.warning,
        message: 'CPU usage is high: ${cpuPercent.toStringAsFixed(1)}%',
        value: cpuPercent,
        threshold: 80.0,
      ));
    }
    
    // Memory Alert
    final memPercent = metrics.metrics['memory_percent'] ?? 0.0;
    if (memPercent > 90) {
      alerts.add(ResourceAlert(
        id: 'high_memory',
        type: ResourceType.memory,
        severity: AlertSeverity.critical,
        message: 'Memory usage is critically high: ${memPercent.toStringAsFixed(1)}%',
        value: memPercent,
        threshold: 90.0,
      ));
    } else if (memPercent > 85) {
      alerts.add(ResourceAlert(
        id: 'medium_memory',
        type: ResourceType.memory,
        severity: AlertSeverity.warning,
        message: 'Memory usage is high: ${memPercent.toStringAsFixed(1)}%',
        value: memPercent,
        threshold: 85.0,
      ));
    }
    
    // Disk Alert
    final diskPercent = metrics.metrics['disk_percent'] ?? 0.0;
    if (diskPercent > 95) {
      alerts.add(ResourceAlert(
        id: 'high_disk',
        type: ResourceType.disk,
        severity: AlertSeverity.critical,
        message: 'Disk usage is critically high: ${diskPercent.toStringAsFixed(1)}%',
        value: diskPercent,
        threshold: 95.0,
      ));
    } else if (diskPercent > 90) {
      alerts.add(ResourceAlert(
        id: 'medium_disk',
        type: ResourceType.disk,
        severity: AlertSeverity.warning,
        message: 'Disk usage is high: ${diskPercent.toStringAsFixed(1)}%',
        value: diskPercent,
        threshold: 90.0,
      ));
    }
    
    // Temperature Alert
    final cpuTemp = metrics.metrics['cpu_temp'];
    if (cpuTemp != null && cpuTemp > 85) {
      alerts.add(ResourceAlert(
        id: 'high_temp',
        type: ResourceType.temperature,
        severity: AlertSeverity.critical,
        message: 'CPU temperature is critically high: ${cpuTemp.toStringAsFixed(1)}°C',
        value: cpuTemp,
        threshold: 85.0,
      ));
    } else if (cpuTemp != null && cpuTemp > 75) {
      alerts.add(ResourceAlert(
        id: 'medium_temp',
        type: ResourceType.temperature,
        severity: AlertSeverity.warning,
        message: 'CPU temperature is high: ${cpuTemp.toStringAsFixed(1)}°C',
        value: cpuTemp,
        threshold: 75.0,
      ));
    }
    
    // Update active alerts
    for (final alert in alerts) {
      _activeAlerts[alert.id] = alert;
      
      // Emit alert event
      _monitorController.add(ResourceEvent(
        type: ResourceEventType.alertTriggered,
        alert: alert,
      ));
    }
    
    // Remove resolved alerts
    final resolvedAlerts = <String>[];
    for (final entry in _activeAlerts.entries) {
      final alert = entry.value;
      final currentValue = metrics.metrics[alert.type.name];
      
      if (currentValue != null && currentValue < alert.threshold) {
        resolvedAlerts.add(entry.key);
        
        // Emit resolved event
        _monitorController.add(ResourceEvent(
          type: ResourceEventType.alertResolved,
          alert: alert,
        ));
      }
    }
    
    for (final alertId in resolvedAlerts) {
      _activeAlerts.remove(alertId);
    }
  }

  String generateDashboardHTML() {
    if (_currentMetrics == null) {
      return '<div class="error">No metrics available</div>';
    }
    
    final metrics = _currentMetrics!;
    final buffer = StringBuffer();
    
    buffer.write('<div class="resource-dashboard">');
    buffer.write('<div class="dashboard-header">');
    buffer.write('<h2>System Resource Monitor</h2>');
    buffer.write('<div class="timestamp">Last updated: ${metrics.timestamp.toIso8601String()}</div>');
    buffer.write('</div>');
    
    // CPU Section
    buffer.write('<div class="resource-section">');
    buffer.write('<h3>CPU</h3>');
    buffer.write('<div class="metric">');
    buffer.write('<div class="metric-label">Usage</div>');
    buffer.write('<div class="metric-value">${(metrics.metrics['cpu_percent'] ?? 0.0).toStringAsFixed(1)}%</div>');
    buffer.write('<div class="metric-bar"><div class="metric-fill" style="width: ${metrics.metrics['cpu_percent'] ?? 0.0}%"></div></div>');
    buffer.write('</div>');
    
    if (metrics.metrics.containsKey('cpu_temp')) {
      buffer.write('<div class="metric">');
      buffer.write('<div class="metric-label">Temperature</div>');
      buffer.write('<div class="metric-value">${(metrics.metrics['cpu_temp'] ?? 0.0).toStringAsFixed(1)}°C</div>');
      buffer.write('</div>');
    }
    
    if (metrics.metrics.containsKey('load_1min')) {
      buffer.write('<div class="metric">');
      buffer.write('<div class="metric-label">Load Average (1min)</div>');
      buffer.write('<div class="metric-value">${(metrics.metrics['load_1min'] ?? 0.0).toStringAsFixed(2)}</div>');
      buffer.write('</div>');
    }
    buffer.write('</div>');
    
    // Memory Section
    buffer.write('<div class="resource-section">');
    buffer.write('<h3>Memory</h3>');
    buffer.write('<div class="metric">');
    buffer.write('<div class="metric-label">Usage</div>');
    buffer.write('<div class="metric-value">${(metrics.metrics['memory_percent'] ?? 0.0).toStringAsFixed(1)}%</div>');
    buffer.write('<div class="metric-bar"><div class="metric-fill" style="width: ${metrics.metrics['memory_percent'] ?? 0.0}%"></div></div>');
    buffer.write('</div>');
    
    buffer.write('<div class="metric">');
    buffer.write('<div class="metric-label">Used / Total</div>');
    buffer.write('<div class="metric-value">${(metrics.metrics['memory_used_mb'] ?? 0.0).toStringAsFixed(0)} / ${(metrics.metrics['memory_total_mb'] ?? 0.0).toStringAsFixed(0)} MB</div>');
    buffer.write('</div>');
    
    if (metrics.metrics['swap_percent']! > 0) {
      buffer.write('<div class="metric">');
      buffer.write('<div class="metric-label">Swap Usage</div>');
      buffer.write('<div class="metric-value">${(metrics.metrics['swap_percent'] ?? 0.0).toStringAsFixed(1)}%</div>');
      buffer.write('</div>');
    }
    buffer.write('</div>');
    
    // Disk Section
    buffer.write('<div class="resource-section">');
    buffer.write('<h3>Disk</h3>');
    buffer.write('<div class="metric">');
    buffer.write('<div class="metric-label">Usage</div>');
    buffer.write('<div class="metric-value">${(metrics.metrics['disk_percent'] ?? 0.0).toStringAsFixed(1)}%</div>');
    buffer.write('<div class="metric-bar"><div class="metric-fill" style="width: ${metrics.metrics['disk_percent'] ?? 0.0}%"></div></div>');
    buffer.write('</div>');
    
    buffer.write('<div class="metric">');
    buffer.write('<div class="metric-label">Used / Total</div>');
    buffer.write('<div class="metric-value">${(metrics.metrics['disk_used'] ?? 0.0).toStringAsFixed(1)} / ${(metrics.metrics['disk_total'] ?? 0.0).toStringAsFixed(1)} GB</div>');
    buffer.write('</div>');
    buffer.write('</div>');
    
    // Processes Section
    buffer.write('<div class="resource-section">');
    buffer.write('<h3>Processes</h3>');
    buffer.write('<div class="metric">');
    buffer.write('<div class="metric-label">Total</div>');
    buffer.write('<div class="metric-value">${(metrics.metrics['process_total'] ?? 0.0).toInt()}</div>');
    buffer.write('</div>');
    
    buffer.write('<div class="metric">');
    buffer.write('<div class="metric-label">Running</div>');
    buffer.write('<div class="metric-value">${(metrics.metrics['process_running'] ?? 0.0).toInt()}</div>');
    buffer.write('</div>');
    
    buffer.write('<div class="metric">');
    buffer.write('<div class="metric-label">Avg CPU</div>');
    buffer.write('<div class="metric-value">${(metrics.metrics['process_avg_cpu'] ?? 0.0).toStringAsFixed(1)}%</div>');
    buffer.write('</div>');
    buffer.write('</div>');
    
    // Alerts Section
    if (_activeAlerts.isNotEmpty) {
      buffer.write('<div class="resource-section alerts">');
      buffer.write('<h3>Alerts</h3>');
      
      for (final alert in _activeAlerts.values) {
        buffer.write('<div class="alert ${alert.severity.name}">');
        buffer.write('<div class="alert-message">${alert.message}</div>');
        buffer.write('<div class="alert-time">${alert.timestamp.toIso8601String()}</div>');
        buffer.write('</div>');
      }
      
      buffer.write('</div>');
    }
    
    // Trends Section
    if (_trends != null) {
      buffer.write('<div class="resource-section">');
      buffer.write('<h3>Trends (Last 10 samples)</h3>');
      
      for (final entry in _trends!.directions.entries) {
        final direction = entry.value;
        final icon = direction == TrendDirection.increasing ? '📈' : 
                     direction == TrendDirection.decreasing ? '📉' : '➡️';
        
        buffer.write('<div class="trend">');
        buffer.write('<span class="trend-icon">$icon</span>');
        buffer.write('<span class="trend-metric">${entry.key}</span>');
        buffer.write('<span class="trend-direction">${direction.name}</span>');
        buffer.write('</div>');
      }
      
      buffer.write('</div>');
    }
    
    buffer.write('</div>');
    
    return buffer.toString();
  }

  ResourceStatistics getStatistics() {
    if (_history.isEmpty) {
      return ResourceStatistics(
        historySize: 0,
        activeAlerts: 0,
        averageCpuUsage: 0.0,
        averageMemoryUsage: 0.0,
        peakCpuUsage: 0.0,
        peakMemoryUsage: 0.0,
        uptime: Duration.zero,
      );
    }
    
    final cpuUsages = _history.map((h) => h.metrics['cpu_percent'] ?? 0.0).toList();
    final memUsages = _history.map((h) => h.metrics['memory_percent'] ?? 0.0).toList();
    
    return ResourceStatistics(
      historySize: _history.length,
      activeAlerts: _activeAlerts.length,
      averageCpuUsage: cpuUsages.reduce((a, b) => a + b) / cpuUsages.length,
      averageMemoryUsage: memUsages.reduce((a, b) => a + b) / memUsages.length,
      peakCpuUsage: cpuUsages.reduce(math.max),
      peakMemoryUsage: memUsages.reduce(math.max),
      uptime: Duration(seconds: (_currentMetrics?.metrics['uptime_seconds'] ?? 0.0).toInt()),
    );
  }

  Future<void> dispose() async {
    _monitoringTimer?.cancel();
    _monitorController.close();
    _history.clear();
    _activeAlerts.clear();
    _currentMetrics = null;
    _trends = null;
    _isInitialized = false;
    
    debugPrint('📊 Resource Monitor disposed');
  }
}

/// Data classes
class ResourceMetrics {
  final DateTime timestamp;
  final Map<String, double> metrics;
  
  ResourceMetrics({
    required this.timestamp,
    required this.metrics,
  });
}

class ResourceSnapshot {
  final DateTime timestamp;
  final ResourceMetrics metrics;
  
  ResourceSnapshot({
    required this.timestamp,
    required this.metrics,
  });
}

class ResourceTrends {
  final DateTime timestamp;
  final Map<String, TrendDirection> directions;
  
  ResourceTrends({
    required this.timestamp,
    required this.directions,
  });
}

class ResourceAlert {
  final String id;
  final ResourceType type;
  final AlertSeverity severity;
  final String message;
  final double value;
  final double threshold;
  final DateTime timestamp = DateTime.now();
  
  ResourceAlert({
    required this.id,
    required this.type,
    required this.severity,
    required this.message,
    required this.value,
    required this.threshold,
  });
}

class ResourceEvent {
  final ResourceEventType type;
  final ResourceMetrics? metrics;
  final ResourceAlert? alert;
  final Map<String, dynamic>? data;
  
  ResourceEvent({
    required this.type,
    this.metrics,
    this.alert,
    this.data,
  });
}

class ResourceStatistics {
  final int historySize;
  final int activeAlerts;
  final double averageCpuUsage;
  final double averageMemoryUsage;
  final double peakCpuUsage;
  final double peakMemoryUsage;
  final Duration uptime;
  
  ResourceStatistics({
    required this.historySize,
    required this.activeAlerts,
    required this.averageCpuUsage,
    required this.averageMemoryUsage,
    required this.peakCpuUsage,
    required this.peakMemoryUsage,
    required this.uptime,
  });
}

enum ResourceType {
  cpu,
  memory,
  disk,
  network,
  temperature,
  process,
}

enum AlertSeverity {
  info,
  warning,
  critical,
}

enum TrendDirection {
  increasing,
  decreasing,
  stable,
}

enum ResourceEventType {
  metricsUpdated,
  alertTriggered,
  alertResolved,
  thresholdExceeded,
}
