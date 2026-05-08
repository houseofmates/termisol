import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Real-time Performance Dashboard - /monitor command implementation
class RealtimePerformanceDashboard {
  static final RealtimePerformanceDashboard _instance = RealtimePerformanceDashboard._internal();
  factory RealtimePerformanceDashboard() => _instance;
  RealtimePerformanceDashboard._internal();

  bool _isInitialized = false;
  bool _isMonitoring = false;
  Timer? _monitoringTimer;
  Timer? _updateTimer;
  
  final Queue<PerformanceSnapshot> _snapshots = Queue();
  final Map<String, PerformanceMetric> _currentMetrics = {};
  final List<PerformanceAlert> _activeAlerts = [];
  final Map<String, PerformanceThreshold> _thresholds = {};
  
  static const Duration _monitoringInterval = Duration(milliseconds: 500);
  static const Duration _updateInterval = Duration(seconds: 1);
  static const int _maxSnapshots = 120; // Keep 1 minute of history
  
  final _dashboardController = StreamController<DashboardEvent>.broadcast();
  Stream<DashboardEvent> get events => _dashboardController.stream;
  
  bool get isInitialized => _isInitialized;
  bool get isMonitoring => _isMonitoring;
  PerformanceSnapshot? get latestSnapshot => _snapshots.isNotEmpty ? _snapshots.last : null;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _initializeThresholds();
    _isInitialized = true;
    debugPrint('📊 Real-time Performance Dashboard initialized');
  }

  Future<void> startMonitoring() async {
    if (_isMonitoring) return;
    
    _isMonitoring = true;
    _startMonitoringTimer();
    _startUpdateTimer();
    
    _dashboardController.add(DashboardEvent(
      type: DashboardEventType.monitoringStarted,
      data: {'timestamp': DateTime.now().toIso8601String()},
    ));
    
    debugPrint('📊 Performance monitoring started');
  }

  Future<void> stopMonitoring() async {
    if (!_isMonitoring) return;
    
    _isMonitoring = false;
    _monitoringTimer?.cancel();
    _updateTimer?.cancel();
    
    _dashboardController.add(DashboardEvent(
      type: DashboardEventType.monitoringStopped,
      data: {'timestamp': DateTime.now().toIso8601String()},
    ));
    
    debugPrint('📊 Performance monitoring stopped');
  }

  PerformanceSnapshot getCurrentSnapshot() {
    return PerformanceSnapshot(
      timestamp: DateTime.now(),
      cpu: _collectCPUMetrics(),
      memory: _collectMemoryMetrics(),
      gpu: _collectGPUMetrics(),
      network: _collectNetworkMetrics(),
      disk: _collectDiskMetrics(),
      application: _collectApplicationMetrics(),
    );
  }

  List<PerformanceSnapshot> getHistory({Duration? duration}) {
    if (duration == null) return _snapshots.toList();
    
    final cutoff = DateTime.now().subtract(duration);
    return _snapshots.where((snapshot) => snapshot.timestamp.isAfter(cutoff)).toList();
  }

  PerformanceStatistics getStatistics() {
    if (_snapshots.isEmpty) {
      return PerformanceStatistics(
        averageCPU: 0.0,
        averageMemory: 0.0,
        averageGPU: 0.0,
        peakCPU: 0.0,
        peakMemory: 0.0,
        peakGPU: 0.0,
        alertCount: _activeAlerts.length,
        uptime: Duration.zero,
      );
    }
    
    final cpuValues = _snapshots.map((s) => s.cpu.usage).toList();
    final memoryValues = _snapshots.map((s) => s.memory.usage).toList();
    final gpuValues = _snapshots.map((s) => s.gpu.usage).toList();
    
    return PerformanceStatistics(
      averageCPU: cpuValues.reduce((a, b) => a + b) / cpuValues.length,
      averageMemory: memoryValues.reduce((a, b) => a + b) / memoryValues.length,
      averageGPU: gpuValues.reduce((a, b) => a + b) / gpuValues.length,
      peakCPU: cpuValues.reduce(math.max),
      peakMemory: memoryValues.reduce(math.max),
      peakGPU: gpuValues.reduce(math.max),
      alertCount: _activeAlerts.length,
      uptime: _snapshots.isNotEmpty ? DateTime.now().difference(_snapshots.first.timestamp) : Duration.zero,
    );
  }

  List<PerformanceAlert> getActiveAlerts() {
    return List.unmodifiable(_activeAlerts);
  }

  void setThreshold(String metric, double warning, double critical) {
    _thresholds[metric] = PerformanceThreshold(
      metric: metric,
      warningLevel: warning,
      criticalLevel: critical,
    );
  }

  Widget buildDashboard() {
    return _PerformanceDashboardWidget(
      dashboard: this,
    );
  }

  CPUMetrics _collectCPUMetrics() {
    // Simulate CPU metrics collection
    final usage = 0.3 + (math.Random().nextDouble() * 0.4); // 30-70%
    final cores = 8;
    final frequency = 2400.0 + (math.Random().nextDouble() * 800); // 2.4-3.2 GHz
    final temperature = 45.0 + (math.Random().nextDouble() * 35); // 45-80°C
    
    return CPUMetrics(
      usage: usage,
      cores: cores,
      frequency: frequency,
      temperature: temperature,
      processes: _getProcessCount(),
    );
  }

  MemoryMetrics _collectMemoryMetrics() {
    // Simulate memory metrics collection
    final total = 16384.0; // 16GB
    final used = total * (0.4 + (math.Random().nextDouble() * 0.3)); // 40-70%
    final available = total - used;
    final swapTotal = 8192.0; // 8GB swap
    final swapUsed = swapTotal * (math.Random().nextDouble() * 0.2); // 0-20%
    
    return MemoryMetrics(
      total: total,
      used: used,
      available: available,
      swapTotal: swapTotal,
      swapUsed: swapUsed,
      usage: used / total,
      buffers: used * 0.1,
      cache: used * 0.2,
    );
  }

  GPUMetrics _collectGPUMetrics() {
    // Simulate GPU metrics collection
    final usage = 0.2 + (math.Random().nextDouble() * 0.6); // 20-80%
    final memoryTotal = 8192.0; // 8GB VRAM
    final memoryUsed = memoryTotal * usage;
    final temperature = 35.0 + (math.Random().nextDouble() * 45); // 35-80°C
    final powerUsage = 150.0 + (math.Random().nextDouble() * 200); // 150-350W
    
    return GPUMetrics(
      usage: usage,
      memoryTotal: memoryTotal,
      memoryUsed: memoryUsed,
      temperature: temperature,
      powerUsage: powerUsage,
      clockSpeed: 1500.0 + (math.Random().nextDouble() * 500),
    );
  }

  NetworkMetrics _collectNetworkMetrics() {
    // Simulate network metrics collection
    final uploadSpeed = math.Random().nextDouble() * 100; // 0-100 Mbps
    final downloadSpeed = math.Random().nextDouble() * 1000; // 0-1000 Mbps
    final latency = 5 + (math.Random().nextDouble() * 45); // 5-50ms
    final packetLoss = math.Random().nextDouble() * 0.02; // 0-2%
    
    return NetworkMetrics(
      uploadSpeed: uploadSpeed,
      downloadSpeed: downloadSpeed,
      latency: latency,
      packetLoss: packetLoss,
      connections: _getConnectionCount(),
    );
  }

  DiskMetrics _collectDiskMetrics() {
    // Simulate disk metrics collection
    final readSpeed = 100 + (math.Random().nextDouble() * 400); // 100-500 MB/s
    final writeSpeed = 80 + (math.Random().nextDouble() * 320); // 80-400 MB/s
    final usage = 0.5 + (math.Random().nextDouble() * 0.3); // 50-80%
    final iops = 100 + (math.Random().nextDouble() * 900); // 100-1000 IOPS
    
    return DiskMetrics(
      readSpeed: readSpeed,
      writeSpeed: writeSpeed,
      usage: usage,
      iops: iops,
      queueDepth: math.Random().nextInt(10),
    );
  }

  ApplicationMetrics _collectApplicationMetrics() {
    // Simulate application metrics collection
    final renderTime = 8.0 + (math.Random().nextDouble() * 8); // 8-16ms
    final frameRate = renderTime > 0 ? 1000.0 / renderTime : 60.0;
    final memoryUsage = 100 + (math.Random().nextDouble() * 400); // 100-500MB
    final threadCount = 4 + math.Random().nextInt(8); // 4-12 threads
    
    return ApplicationMetrics(
      renderTime: renderTime,
      frameRate: frameRate,
      memoryUsage: memoryUsage,
      threadCount: threadCount,
      objectCount: 1000 + math.Random().nextInt(9000), // 1000-10000 objects
      gcTime: math.Random().nextDouble() * 5, // 0-5ms
    );
  }

  int _getProcessCount() {
    return 150 + math.Random().nextInt(100); // 150-250 processes
  }

  int _getConnectionCount() {
    return math.Random().nextInt(20); // 0-20 connections
  }

  void _startMonitoringTimer() {
    _monitoringTimer = Timer.periodic(_monitoringInterval, (_) {
      final snapshot = getCurrentSnapshot();
      _addSnapshot(snapshot);
      _checkThresholds(snapshot);
    });
  }

  void _startUpdateTimer() {
    _updateTimer = Timer.periodic(_updateInterval, (_) {
      _dashboardController.add(DashboardEvent(
        type: DashboardEventType.dataUpdated,
        data: {
          'timestamp': DateTime.now().toIso8601String(),
          'snapshot_count': _snapshots.length,
        },
      ));
    });
  }

  void _addSnapshot(PerformanceSnapshot snapshot) {
    _snapshots.add(snapshot);
    if (_snapshots.length > _maxSnapshots) {
      _snapshots.removeFirst();
    }
    
    _dashboardController.add(DashboardEvent(
      type: DashboardEventType.snapshotAdded,
      data: {
        'timestamp': snapshot.timestamp.toIso8601String(),
        'cpu_usage': snapshot.cpu.usage,
        'memory_usage': snapshot.memory.usage,
        'gpu_usage': snapshot.gpu.usage,
      },
    ));
  }

  void _checkThresholds(PerformanceSnapshot snapshot) {
    final newAlerts = <PerformanceAlert>[];
    
    // Check CPU threshold
    final cpuThreshold = _thresholds['cpu'];
    if (cpuThreshold != null) {
      if (snapshot.cpu.usage >= cpuThreshold.criticalLevel) {
        newAlerts.add(PerformanceAlert(
          type: AlertType.critical,
          metric: 'cpu',
          value: snapshot.cpu.usage,
          threshold: cpuThreshold.criticalLevel,
          message: 'CPU usage critically high: ${(snapshot.cpu.usage * 100).toStringAsFixed(1)}%',
          timestamp: DateTime.now(),
        ));
      } else if (snapshot.cpu.usage >= cpuThreshold.warningLevel) {
        newAlerts.add(PerformanceAlert(
          type: AlertType.warning,
          metric: 'cpu',
          value: snapshot.cpu.usage,
          threshold: cpuThreshold.warningLevel,
          message: 'CPU usage high: ${(snapshot.cpu.usage * 100).toStringAsFixed(1)}%',
          timestamp: DateTime.now(),
        ));
      }
    }
    
    // Check Memory threshold
    final memoryThreshold = _thresholds['memory'];
    if (memoryThreshold != null) {
      if (snapshot.memory.usage >= memoryThreshold.criticalLevel) {
        newAlerts.add(PerformanceAlert(
          type: AlertType.critical,
          metric: 'memory',
          value: snapshot.memory.usage,
          threshold: memoryThreshold.criticalLevel,
          message: 'Memory usage critically high: ${(snapshot.memory.usage * 100).toStringAsFixed(1)}%',
          timestamp: DateTime.now(),
        ));
      } else if (snapshot.memory.usage >= memoryThreshold.warningLevel) {
        newAlerts.add(PerformanceAlert(
          type: AlertType.warning,
          metric: 'memory',
          value: snapshot.memory.usage,
          threshold: memoryThreshold.warningLevel,
          message: 'Memory usage high: ${(snapshot.memory.usage * 100).toStringAsFixed(1)}%',
          timestamp: DateTime.now(),
        ));
      }
    }
    
    // Check GPU threshold
    final gpuThreshold = _thresholds['gpu'];
    if (gpuThreshold != null) {
      if (snapshot.gpu.usage >= gpuThreshold.criticalLevel) {
        newAlerts.add(PerformanceAlert(
          type: AlertType.critical,
          metric: 'gpu',
          value: snapshot.gpu.usage,
          threshold: gpuThreshold.criticalLevel,
          message: 'GPU usage critically high: ${(snapshot.gpu.usage * 100).toStringAsFixed(1)}%',
          timestamp: DateTime.now(),
        ));
      } else if (snapshot.gpu.usage >= gpuThreshold.warningLevel) {
        newAlerts.add(PerformanceAlert(
          type: AlertType.warning,
          metric: 'gpu',
          value: snapshot.gpu.usage,
          threshold: gpuThreshold.warningLevel,
          message: 'GPU usage high: ${(snapshot.gpu.usage * 100).toStringAsFixed(1)}%',
          timestamp: DateTime.now(),
        ));
      }
    }
    
    // Update active alerts
    _activeAlerts.clear();
    _activeAlerts.addAll(newAlerts);
    
    // Send alert events
    for (final alert in newAlerts) {
      _dashboardController.add(DashboardEvent(
        type: DashboardEventType.alertTriggered,
        data: {
          'alert_type': alert.type.toString(),
          'metric': alert.metric,
          'value': alert.value,
          'message': alert.message,
        },
      ));
    }
  }

  void _initializeThresholds() {
    _thresholds['cpu'] = PerformanceThreshold(
      metric: 'cpu',
      warningLevel: 0.8, // 80%
      criticalLevel: 0.9, // 90%
    );
    
    _thresholds['memory'] = PerformanceThreshold(
      metric: 'memory',
      warningLevel: 0.85, // 85%
      criticalLevel: 0.95, // 95%
    );
    
    _thresholds['gpu'] = PerformanceThreshold(
      metric: 'gpu',
      warningLevel: 0.85, // 85%
      criticalLevel: 0.95, // 95%
    );
  }

  Future<void> dispose() async {
    await stopMonitoring();
    _dashboardController.close();
    _snapshots.clear();
    _currentMetrics.clear();
    _activeAlerts.clear();
    _thresholds.clear();
  }
}

/// Performance metrics classes
class PerformanceSnapshot {
  final DateTime timestamp;
  final CPUMetrics cpu;
  final MemoryMetrics memory;
  final GPUMetrics gpu;
  final NetworkMetrics network;
  final DiskMetrics disk;
  final ApplicationMetrics application;
  
  PerformanceSnapshot({
    required this.timestamp,
    required this.cpu,
    required this.memory,
    required this.gpu,
    required this.network,
    required this.disk,
    required this.application,
  });
}

class CPUMetrics {
  final double usage;
  final int cores;
  final double frequency;
  final double temperature;
  final int processes;
  
  CPUMetrics({
    required this.usage,
    required this.cores,
    required this.frequency,
    required this.temperature,
    required this.processes,
  });
}

class MemoryMetrics {
  final double total;
  final double used;
  final double available;
  final double swapTotal;
  final double swapUsed;
  final double usage;
  final double buffers;
  final double cache;
  
  MemoryMetrics({
    required this.total,
    required this.used,
    required this.available,
    required this.swapTotal,
    required this.swapUsed,
    required this.usage,
    required this.buffers,
    required this.cache,
  });
}

class GPUMetrics {
  final double usage;
  final double memoryTotal;
  final double memoryUsed;
  final double temperature;
  final double powerUsage;
  final double clockSpeed;
  
  GPUMetrics({
    required this.usage,
    required this.memoryTotal,
    required this.memoryUsed,
    required this.temperature,
    required this.powerUsage,
    required this.clockSpeed,
  });
}

class NetworkMetrics {
  final double uploadSpeed;
  final double downloadSpeed;
  final double latency;
  final double packetLoss;
  final int connections;
  
  NetworkMetrics({
    required this.uploadSpeed,
    required this.downloadSpeed,
    required this.latency,
    required this.packetLoss,
    required this.connections,
  });
}

class DiskMetrics {
  final double readSpeed;
  final double writeSpeed;
  final double usage;
  final double iops;
  final int queueDepth;
  
  DiskMetrics({
    required this.readSpeed,
    required this.writeSpeed,
    required this.usage,
    required this.iops,
    required this.queueDepth,
  });
}

class ApplicationMetrics {
  final double renderTime;
  final double frameRate;
  final double memoryUsage;
  final int threadCount;
  final int objectCount;
  final double gcTime;
  
  ApplicationMetrics({
    required this.renderTime,
    required this.frameRate,
    required this.memoryUsage,
    required this.threadCount,
    required this.objectCount,
    required this.gcTime,
  });
}

class PerformanceThreshold {
  final String metric;
  final double warningLevel;
  final double criticalLevel;
  
  PerformanceThreshold({
    required this.metric,
    required this.warningLevel,
    required this.criticalLevel,
  });
}

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

class PerformanceStatistics {
  final double averageCPU;
  final double averageMemory;
  final double averageGPU;
  final double peakCPU;
  final double peakMemory;
  final double peakGPU;
  final int alertCount;
  final Duration uptime;
  
  PerformanceStatistics({
    required this.averageCPU,
    required this.averageMemory,
    required this.averageGPU,
    required this.peakCPU,
    required this.peakMemory,
    required this.peakGPU,
    required this.alertCount,
    required this.uptime,
  });
}

class DashboardEvent {
  final DashboardEventType type;
  final Map<String, dynamic>? data;
  
  DashboardEvent({
    required this.type,
    this.data,
  });
}

enum AlertType {
  info,
  warning,
  critical,
}

enum DashboardEventType {
  monitoringStarted,
  monitoringStopped,
  snapshotAdded,
  dataUpdated,
  alertTriggered,
}

/// Flutter Widget for the Dashboard
class _PerformanceDashboardWidget extends StatefulWidget {
  final RealtimePerformanceDashboard dashboard;
  
  const _PerformanceDashboardWidget({
    required this.dashboard,
  });
  
  @override
  _PerformanceDashboardWidgetState createState() => _PerformanceDashboardWidgetState();
}

class _PerformanceDashboardWidgetState extends State<_PerformanceDashboardWidget> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          _buildHeader(),
          SizedBox(height: 16),
          _buildMetricsGrid(),
          SizedBox(height: 16),
          _buildCharts(),
          SizedBox(height: 16),
          _buildAlerts(),
        ],
      ),
    );
  }
  
  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.dashboard, size: 24),
        SizedBox(width: 8),
        Text(
          'Performance Monitor',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Spacer(),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: widget.dashboard.isMonitoring ? Colors.green : Colors.red,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            widget.dashboard.isMonitoring ? 'Monitoring' : 'Stopped',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ],
    );
  }
  
  Widget _buildMetricsGrid() {
    final snapshot = widget.dashboard.latestSnapshot;
    if (snapshot == null) return Container();
    
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 3,
      childAspectRatio: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: [
        _buildMetricCard('CPU', '${(snapshot.cpu.usage * 100).toStringAsFixed(1)}%', Icons.memory),
        _buildMetricCard('Memory', '${(snapshot.memory.usage * 100).toStringAsFixed(1)}%', Icons.storage),
        _buildMetricCard('GPU', '${(snapshot.gpu.usage * 100).toStringAsFixed(1)}%', Icons.gpu),
        _buildMetricCard('Network', '${snapshot.network.downloadSpeed.toStringAsFixed(0)} Mbps', Icons.network_check),
        _buildMetricCard('Disk', '${snapshot.disk.readSpeed.toStringAsFixed(0)} MB/s', Icons.storage),
        _buildMetricCard('FPS', '${snapshot.application.frameRate.toStringAsFixed(0)}', Icons.speed),
      ],
    );
  }
  
  Widget _buildMetricCard(String title, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16),
                SizedBox(width: 4),
                Text(
                  title,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            Spacer(),
            Text(
              value,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCharts() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Performance History',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Container(
              height: 200,
              child: Center(
                child: Text('Chart implementation would go here'),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAlerts() {
    final alerts = widget.dashboard.getActiveAlerts();
    
    if (alerts.isEmpty) {
      return Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No active alerts',
            style: TextStyle(color: Colors.green),
          ),
        ),
      );
    }
    
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Active Alerts',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            ...alerts.map((alert) => Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    alert.type == AlertType.critical ? Icons.warning : Icons.info,
                    color: alert.type == AlertType.critical ? Colors.red : Colors.orange,
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      alert.message,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            )).toList(),
          ],
        ),
      ),
    );
  }
}
