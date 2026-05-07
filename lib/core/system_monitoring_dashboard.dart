import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

class SystemMonitoringDashboard {
  static const String _configFile = '/home/house/.termisol_monitor_config.json';
  static const String _dataFile = '/home/house/.termisol_monitor_data.json';
  static const String _command = '/monitor';
  static const int _maxHistoryPoints = 1000;
  static const Duration _updateInterval = Duration(seconds: 1);
  static const Duration _cleanupInterval = Duration(hours: 1);
  
  final Map<String, Metric> _metrics = {};
  final Map<String, List<DataPoint>> _history = {};
  final Map<String, Alert> _alerts = {};
  final Map<String, Dashboard> _dashboards = {};
  
  Timer? _updateTimer;
  Timer? _cleanupTimer;
  bool _isRunning = false;
  int _totalMetrics = 0;
  int _totalAlerts = 0;
  int _totalDashboards = 0;
  
  final StreamController<MonitorEvent> _monitorController = 
      StreamController<MonitorEvent>.broadcast();

  void initialize() {
    _loadConfiguration();
    _loadMetrics();
    _loadHistory();
    _loadAlerts();
    _loadDashboards();
    _setupCommand();
    _startMonitoring();
    developer.log('📊 System Monitoring Dashboard initialized');
  }

  void _loadConfiguration() {
    try {
      final file = File(_configFile);
      if (!file.existsSync()) {
        developer.log('📊 No existing monitor configuration found, using defaults');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      // Load metrics configuration
      for (final entry in data['metrics']) {
        final metric = Metric.fromJson(entry);
        _metrics[metric.id] = metric;
        _totalMetrics++;
      }
      
      // Load alerts configuration
      for (final entry in data['alerts']) {
        final alert = Alert.fromJson(entry);
        _alerts[alert.id] = alert;
        _totalAlerts++;
      }
      
      // Load dashboards configuration
      for (final entry in data['dashboards']) {
        final dashboard = Dashboard.fromJson(entry);
        _dashboards[dashboard.id] = dashboard;
        _totalDashboards++;
      }
      
      developer.log('📊 Loaded monitor configuration: ${_metrics.length} metrics, ${_alerts.length} alerts, ${_dashboards.length} dashboards');
      
    } catch (e) {
      developer.log('📊 Failed to load monitor configuration: $e');
    }
  }

  void _loadMetrics() {
    try {
      final file = File('${_dataFile}.metrics');
      if (!file.existsSync()) {
        _initializeDefaultMetrics();
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['metrics']) {
        final metric = Metric.fromJson(entry);
        _metrics[metric.id] = metric;
        _totalMetrics++;
      }
      
      developer.log('📊 Loaded ${_metrics.length} metrics');
      
    } catch (e) {
      developer.log('📊 Failed to load metrics: $e');
    }
  }

  void _loadHistory() {
    try {
      final file = File('${_dataFile}.history');
      if (!file.existsSync()) return;
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['history']) {
        final metricId = entry['metric_id'];
        final points = (entry['points'] as List)
            .map((point) => DataPoint.fromJson(point))
            .toList();
        
        _history[metricId] = points;
      }
      
      developer.log('📊 Loaded history for ${_history.length} metrics');
      
    } catch (e) {
      developer.log('📊 Failed to load history: $e');
    }
  }

  void _loadAlerts() {
    try {
      final file = File('${_dataFile}.alerts');
      if (!file.existsSync()) return;
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['alerts']) {
        final alert = Alert.fromJson(entry);
        _alerts[alert.id] = alert;
        _totalAlerts++;
      }
      
      developer.log('📊 Loaded ${_alerts.length} alerts');
      
    } catch (e) {
      developer.log('📊 Failed to load alerts: $e');
    }
  }

  void _loadDashboards() {
    try {
      final file = File('${_dataFile}.dashboards');
      if (!file.existsSync()) {
        _initializeDefaultDashboards();
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['dashboards']) {
        final dashboard = Dashboard.fromJson(entry);
        _dashboards[dashboard.id] = dashboard;
        _totalDashboards++;
      }
      
      developer.log('📊 Loaded ${_dashboards.length} dashboards');
      
    } catch (e) {
      developer.log('📊 Failed to load dashboards: $e');
    }
  }

  void _setupCommand() {
    // Create command file for /monitor
    final commandFile = File('/usr/local/bin/monitor');
    
    final commandScript = '''#!/bin/bash
# Termisol System Monitoring Dashboard Command
# This script launches the monitoring dashboard in the terminal

# Check if Termisol is running
if ! pgrep -f "termisol" > /dev/null; then
    echo "Error: Termisol is not running. Please start Termisol first."
    exit 1
fi

# Send command to Termisol instance
echo "/monitor" | nc -w 1 localhost 8786 || {
    echo "Error: Could not connect to Termisol monitoring service."
    exit 1
}

echo "Monitoring dashboard opened in Termisol terminal"
''';
    
    try {
      commandFile.parent.createSync(recursive: true);
      commandFile.writeAsStringSync(commandScript);
      commandFile.setPermissionsSync(0o755);
      
      developer.log('📊 Created /monitor command');
      
    } catch (e) {
      developer.log('📊 Failed to create /monitor command: $e');
    }
  }

  void _initializeDefaultMetrics() {
    final defaultMetrics = [
      // CPU metrics
      Metric(
        id: 'cpu_usage',
        name: 'CPU Usage',
        description: 'Total CPU usage percentage',
        unit: '%',
        type: MetricType.gauge,
        category: MetricCategory.system,
        min: 0,
        max: 100,
        thresholds: [
          Threshold(level: AlertLevel.warning, value: 70.0),
          Threshold(level: AlertLevel.critical, value: 90.0),
        ],
        enabled: true,
        createdAt: DateTime.now(),
        lastUpdated: DateTime.now(),
      ),
      
      Metric(
        id: 'cpu_cores',
        name: 'CPU Cores',
        description: 'Number of CPU cores',
        unit: 'cores',
        type: MetricType.counter,
        category: MetricCategory.system,
        enabled: true,
        createdAt: DateTime.now(),
        lastUpdated: DateTime.now(),
      ),
      
      // Memory metrics
      Metric(
        id: 'memory_usage',
        name: 'Memory Usage',
        description: 'Total memory usage percentage',
        unit: '%',
        type: MetricType.gauge,
        category: MetricCategory.system,
        min: 0,
        max: 100,
        thresholds: [
          Threshold(level: AlertLevel.warning, value: 80.0),
          Threshold(level: AlertLevel.critical, value: 95.0),
        ],
        enabled: true,
        createdAt: DateTime.now(),
        lastUpdated: DateTime.now(),
      ),
      
      Metric(
        id: 'memory_total',
        name: 'Total Memory',
        description: 'Total system memory',
        unit: 'GB',
        type: MetricType.gauge,
        category: MetricCategory.system,
        enabled: true,
        createdAt: DateTime.now(),
        lastUpdated: DateTime.now(),
      ),
      
      Metric(
        id: 'memory_available',
        name: 'Available Memory',
        description: 'Available system memory',
        unit: 'GB',
        type: MetricType.gauge,
        category: MetricCategory.system,
        enabled: true,
        createdAt: DateTime.now(),
        lastUpdated: DateTime.now(),
      ),
      
      // Disk metrics
      Metric(
        id: 'disk_usage',
        name: 'Disk Usage',
        description: 'Disk usage percentage',
        unit: '%',
        type: MetricType.gauge,
        category: MetricCategory.storage,
        min: 0,
        max: 100,
        thresholds: [
          Threshold(level: AlertLevel.warning, value: 80.0),
          Threshold(level: AlertLevel.critical, value: 95.0),
        ],
        enabled: true,
        createdAt: DateTime.now(),
        lastUpdated: DateTime.now(),
      ),
      
      Metric(
        id: 'disk_free',
        name: 'Free Disk Space',
        description: 'Free disk space',
        unit: 'GB',
        type: MetricType.gauge,
        category: MetricCategory.storage,
        enabled: true,
        createdAt: DateTime.now(),
        lastUpdated: DateTime.now(),
      ),
      
      // Network metrics
      Metric(
        id: 'network_rx',
        name: 'Network RX',
        description: 'Network receive rate',
        unit: 'MB/s',
        type: MetricType.rate,
        category: MetricCategory.network,
        enabled: true,
        createdAt: DateTime.now(),
        lastUpdated: DateTime.now(),
      ),
      
      Metric(
        id: 'network_tx',
        name: 'Network TX',
        description: 'Network transmit rate',
        unit: 'MB/s',
        type: MetricType.rate,
        category: MetricCategory.network,
        enabled: true,
        createdAt: DateTime.now(),
        lastUpdated: DateTime.now(),
      ),
      
      // Process metrics
      Metric(
        id: 'process_count',
        name: 'Process Count',
        description: 'Total number of running processes',
        unit: 'processes',
        type: MetricType.counter,
        category: MetricCategory.process,
        enabled: true,
        createdAt: DateTime.now(),
        lastUpdated: DateTime.now(),
      ),
      
      // Terminal metrics
      Metric(
        id: 'termisol_sessions',
        name: 'Termisol Sessions',
        description: 'Number of active Termisol sessions',
        unit: 'sessions',
        type: MetricType.counter,
        category: MetricCategory.application,
        enabled: true,
        createdAt: DateTime.now(),
        lastUpdated: DateTime.now(),
      ),
      
      Metric(
        id: 'termisol_memory',
        name: 'Termisol Memory',
        description: 'Memory used by Termisol',
        unit: 'MB',
        type: MetricType.gauge,
        category: MetricCategory.application,
        enabled: true,
        createdAt: DateTime.now(),
        lastUpdated: DateTime.now(),
      ),
    ];
    
    for (final metric in defaultMetrics) {
      _metrics[metric.id] = metric;
      _totalMetrics++;
    }
  }

  void _initializeDefaultDashboards() {
    final defaultDashboards = [
      // System overview dashboard
      Dashboard(
        id: 'system_overview',
        name: 'System Overview',
        description: 'Overview of system metrics',
        layout: DashboardLayout.grid,
        widgets: [
          DashboardWidget(
            id: 'cpu_widget',
            type: WidgetType.gauge,
            metricId: 'cpu_usage',
            title: 'CPU Usage',
            position: WidgetPosition(x: 0, y: 0, width: 2, height: 2),
            config: {'show_thresholds': true},
          ),
          DashboardWidget(
            id: 'memory_widget',
            type: WidgetType.gauge,
            metricId: 'memory_usage',
            title: 'Memory Usage',
            position: WidgetPosition(x: 2, y: 0, width: 2, height: 2),
            config: {'show_thresholds': true},
          ),
          DashboardWidget(
            id: 'disk_widget',
            type: WidgetType.gauge,
            metricId: 'disk_usage',
            title: 'Disk Usage',
            position: WidgetPosition(x: 0, y: 2, width: 2, height: 2),
            config: {'show_thresholds': true},
          ),
          DashboardWidget(
            id: 'network_widget',
            type: WidgetType.line,
            metricIds: ['network_rx', 'network_tx'],
            title: 'Network Activity',
            position: WidgetPosition(x: 2, y: 2, width: 2, height: 2),
            config: {'show_legend': true},
          ),
        ],
        createdAt: DateTime.now(),
        lastModified: DateTime.now(),
        isDefault: true,
      ),
      
      // Performance dashboard
      Dashboard(
        id: 'performance',
        name: 'Performance',
        description: 'System performance metrics',
        layout: DashboardLayout.grid,
        widgets: [
          DashboardWidget(
            id: 'cpu_history',
            type: WidgetType.line,
            metricIds: ['cpu_usage'],
            title: 'CPU History',
            position: WidgetPosition(x: 0, y: 0, width: 3, height: 2),
            config: {'time_range': '1h'},
          ),
          DashboardWidget(
            id: 'memory_history',
            type: WidgetType.line,
            metricIds: ['memory_usage'],
            title: 'Memory History',
            position: WidgetPosition(x: 3, y: 0, width: 3, height: 2),
            config: {'time_range': '1h'},
          ),
          DashboardWidget(
            id: 'process_list',
            type: WidgetType.table,
            metricIds: ['process_count'],
            title: 'Top Processes',
            position: WidgetPosition(x: 0, y: 2, width: 6, height: 2),
            config: {'max_rows': 10},
          ),
        ],
        createdAt: DateTime.now(),
        lastModified: DateTime.now(),
        isDefault: true,
      ),
      
      // Termisol dashboard
      Dashboard(
        id: 'termisol',
        name: 'Termisol',
        description: 'Termisol-specific metrics',
        layout: DashboardLayout.grid,
        widgets: [
          DashboardWidget(
            id: 'sessions_widget',
            type: WidgetType.counter,
            metricIds: ['termisol_sessions'],
            title: 'Active Sessions',
            position: WidgetPosition(x: 0, y: 0, width: 2, height: 1),
            config: {},
          ),
          DashboardWidget(
            id: 'termisol_memory_widget',
            type: WidgetType.gauge,
            metricIds: ['termisol_memory'],
            title: 'Termisol Memory',
            position: WidgetPosition(x: 2, y: 0, width: 2, height: 1),
            config: {'show_thresholds': true},
          ),
          DashboardWidget(
            id: 'terminal_activity',
            type: WidgetType.heatmap,
            metricIds: ['termisol_sessions'],
            title: 'Terminal Activity',
            position: WidgetPosition(x: 0, y: 1, width: 4, height: 2),
            config: {'time_range': '24h'},
          ),
        ],
        createdAt: DateTime.now(),
        lastModified: DateTime.now(),
        isDefault: true,
      ),
    ];
    
    for (final dashboard in defaultDashboards) {
      _dashboards[dashboard.id] = dashboard;
      _totalDashboards++;
    }
  }

  void _startMonitoring() {
    _isRunning = true;
    
    _updateTimer = Timer.periodic(_updateInterval, (_) => _collectMetrics());
    
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) => _performCleanup());
    
    developer.log('📊 Started system monitoring');
    
    _emitEvent(MonitorEvent(
      type: MonitorEventType.monitoringStarted,
    ));
  }

  Future<void> _collectMetrics() async {
    try {
      // Collect CPU metrics
      await _collectCPUMetrics();
      
      // Collect memory metrics
      await _collectMemoryMetrics();
      
      // Collect disk metrics
      await _collectDiskMetrics();
      
      // Collect network metrics
      await _collectNetworkMetrics();
      
      // Collect process metrics
      await _collectProcessMetrics();
      
      // Collect Termisol metrics
      await _collectTermisolMetrics();
      
      // Check alerts
      await _checkAlerts();
      
      // Update history
      _updateHistory();
      
      developer.log('📊 Collected system metrics');
      
    } catch (e) {
      developer.log('📊 Failed to collect metrics: $e');
      
      _emitEvent(MonitorEvent(
        type: MonitorEventType.collectionFailed,
        error: e.toString(),
      ));
    }
  }

  Future<void> _collectCPUMetrics() async {
    try {
      // Get CPU usage from /proc/stat on Linux
      if (Platform.isLinux) {
        final result = await Process.run('cat', ['/proc/stat']);
        if (result.exitCode == 0) {
          final lines = (result.stdout as String).split('\n');
          final cpuLine = lines.firstWhere((line) => line.startsWith('cpu '), orElse: () => '');
          
          if (cpuLine.isNotEmpty) {
            final parts = cpuLine.split(RegExp(r'\s+'));
            if (parts.length >= 5) {
              final userTime = int.tryParse(parts[1]) ?? 0;
              final systemTime = int.tryParse(parts[2]) ?? 0;
              final idleTime = int.tryParse(parts[3]) ?? 0;
              final totalTime = userTime + systemTime + idleTime;
              
              final usage = totalTime > 0 ? ((totalTime - idleTime) / totalTime * 100) : 0.0;
              
              await _updateMetric('cpu_usage', usage);
            }
          }
        }
      }
      
      // Get CPU core count
      final result = await Process.run('nproc', []);
      if (result.exitCode == 0) {
        final cores = int.tryParse(result.stdout.trim()) ?? 1;
        await _updateMetric('cpu_cores', cores.toDouble());
      }
      
    } catch (e) {
      developer.log('📊 Failed to collect CPU metrics: $e');
    }
  }

  Future<void> _collectMemoryMetrics() async {
    try {
      if (Platform.isLinux) {
        // Get memory info from /proc/meminfo
        final result = await Process.run('cat', ['/proc/meminfo']);
        if (result.exitCode == 0) {
          final lines = (result.stdout as String).split('\n');
          final memTotal = _parseMemInfo(lines, 'MemTotal');
          final memAvailable = _parseMemInfo(lines, 'MemAvailable');
          
          if (memTotal > 0 && memAvailable > 0) {
            final usage = ((memTotal - memAvailable) / memTotal * 100);
            final totalGB = memTotal / (1024 * 1024);
            final availableGB = memAvailable / (1024 * 1024);
            
            await _updateMetric('memory_usage', usage);
            await _updateMetric('memory_total', totalGB);
            await _updateMetric('memory_available', availableGB);
          }
        }
      }
      
    } catch (e) {
      developer.log('📊 Failed to collect memory metrics: $e');
    }
  }

  int _parseMemInfo(List<String> lines, String key) {
    for (final line in lines) {
      if (line.startsWith(key)) {
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          return int.tryParse(parts[1]) ?? 0;
        }
      }
    }
    return 0;
  }

  Future<void> _collectDiskMetrics() async {
    try {
      if (Platform.isLinux) {
        // Get disk usage from df
        final result = await Process.run('df', ['-h', '/']);
        if (result.exitCode == 0) {
          final lines = (result.stdout as String).split('\n');
          if (lines.length >= 2) {
            final dataLine = lines[1];
            final parts = dataLine.split(RegExp(r'\s+'));
            
            if (parts.length >= 5) {
              final totalStr = parts[1];
              final usedStr = parts[2];
              final freeStr = parts[3];
              
              // Parse sizes (e.g., "100G", "50G")
              final totalGB = _parseSizeToGB(totalStr);
              final usedGB = _parseSizeToGB(usedStr);
              final freeGB = _parseSizeToGB(freeStr);
              
              final usage = totalGB > 0 ? (usedGB / totalGB * 100) : 0.0;
              
              await _updateMetric('disk_usage', usage);
              await _updateMetric('disk_free', freeGB);
            }
          }
        }
      }
      
    } catch (e) {
      developer.log('📊 Failed to collect disk metrics: $e');
    }
  }

  double _parseSizeToGB(String sizeStr) {
    // Parse size strings like "100G", "50G", "1.5T"
    final match = RegExp(r'^([\d.]+)([KMGTP])$').firstMatch(sizeStr);
    if (match == null) return 0.0;
    
    final value = double.tryParse(match.group(1)!) ?? 0.0;
    final unit = match.group(2)!;
    
    switch (unit) {
      case 'K':
        return value / (1024 * 1024);
      case 'M':
        return value / 1024;
      case 'G':
        return value;
      case 'T':
        return value * 1024;
      case 'P':
        return value * 1024 * 1024;
      default:
        return value;
    }
  }

  Future<void> _collectNetworkMetrics() async {
    try {
      if (Platform.isLinux) {
        // Get network stats from /proc/net/dev
        final result = await Process.run('cat', ['/proc/net/dev']);
        if (result.exitCode == 0) {
          final lines = (result.stdout as String).split('\n');
          
          // Skip header lines
          final dataLines = lines.where((line) => 
              line.isNotEmpty && !line.startsWith('Inter-') && !line.startsWith('face')).toList();
          
          // Calculate total RX and TX bytes
          int totalRx = 0;
          int totalTx = 0;
          
          for (final line in dataLines) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 10) {
              final rxBytes = int.tryParse(parts[1]) ?? 0;
              final txBytes = int.tryParse(parts[9]) ?? 0;
              
              totalRx += rxBytes;
              totalTx += txBytes;
            }
          }
          
          // Convert to MB/s (simplified calculation)
          final rxMBps = totalRx / (1024 * 1024);
          final txMBps = totalTx / (1024 * 1024);
          
          await _updateMetric('network_rx', rxMBps);
          await _updateMetric('network_tx', txMBps);
        }
      }
      
    } catch (e) {
      developer.log('📊 Failed to collect network metrics: $e');
    }
  }

  Future<void> _collectProcessMetrics() async {
    try {
      if (Platform.isLinux) {
        // Get process count from ps
        final result = await Process.run('ps', ['aux']);
        if (result.exitCode == 0) {
          final lines = (result.stdout as String).split('\n');
          final processCount = lines.length - 1; // Subtract header line
          
          await _updateMetric('process_count', processCount.toDouble());
        }
      }
      
    } catch (e) {
      developer.log('📊 Failed to collect process metrics: $e');
    }
  }

  Future<void> _collectTermisolMetrics() async {
    try {
      // Get Termisol process information
      final result = await Process.run('pgrep', ['-f', 'termisol']);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split('\n');
        final sessionCount = lines.where((line) => line.isNotEmpty).length;
        
        await _updateMetric('termisol_sessions', sessionCount.toDouble());
        
        // Get Termisol memory usage (simplified)
        final memoryResult = await Process.run('ps', ['-p', result.stdout.split('\n').first, '-o', 'rss']);
        if (memoryResult.exitCode == 0) {
          final rssKB = int.tryParse(memoryResult.stdout.trim()) ?? 0;
          final rssMB = rssKB / 1024;
          
          await _updateMetric('termisol_memory', rssMB.toDouble());
        }
      }
      
    } catch (e) {
      developer.log('📊 Failed to collect Termisol metrics: $e');
    }
  }

  Future<void> _updateMetric(String metricId, double value) async {
    final metric = _metrics[metricId];
    if (metric == null || !metric.enabled) return;
    
    metric.currentValue = value;
    metric.lastUpdated = DateTime.now();
    
    // Add to history
    final history = _history[metricId] ?? [];
    history.add(DataPoint(
      timestamp: DateTime.now(),
      value: value,
    ));
    
    // Keep history limited
    if (history.length > _maxHistoryPoints) {
      history.removeRange(0, history.length - _maxHistoryPoints);
    }
    
    _history[metricId] = history;
    
    developer.log('📊 Updated metric $metricId: $value');
  }

  Future<void> _checkAlerts() async {
    for (final alert in _alerts.values) {
      if (!alert.enabled) continue;
      
      final metric = _metrics[alert.metricId];
      if (metric == null || metric.currentValue == null) continue;
      
      final value = metric.currentValue!;
      bool shouldTrigger = false;
      
      for (final threshold in alert.thresholds) {
        switch (alert.condition) {
          case AlertCondition.above:
            shouldTrigger = value >= threshold.value;
            break;
          case AlertCondition.below:
            shouldTrigger = value <= threshold.value;
            break;
          case AlertCondition.equals:
            shouldTrigger = value == threshold.value;
            break;
          case AlertCondition.notEquals:
            shouldTrigger = value != threshold.value;
            break;
        }
        
        if (shouldTrigger) {
          await _triggerAlert(alert, threshold.level, value);
          break;
        }
      }
    }
  }

  Future<void> _triggerAlert(Alert alert, AlertLevel level, double value) async {
    alert.lastTriggered = DateTime.now();
    alert.triggerCount++;
    
    developer.log('📊 Alert triggered: ${alert.name} ($level: $value)');
    
    _emitEvent(MonitorEvent(
      type: MonitorEventType.alertTriggered,
      alertId: alert.id,
      alertName: alert.name,
      level: level,
      value: value,
    ));
    
    await _saveAlerts();
  }

  void _updateHistory() {
    // History is already updated in _updateMetric
  }

  Future<void> _performCleanup() async {
    final cutoffDate = DateTime.now().subtract(Duration(days: 7));
    
    // Clean old history points
    for (final entry in _history.entries) {
      final metricId = entry.key;
      final history = entry.value;
      
      final initialCount = history.length;
      history.removeWhere((point) => point.timestamp.isBefore(cutoffDate));
      
      if (history.length != initialCount) {
        developer.log('📊 Cleaned ${initialCount - history.length} old history points for $metricId');
      }
    }
    
    // Clean old alerts
    final initialAlertCount = _alerts.length;
    _alerts.removeWhere((alert) => 
        alert.lastTriggered != null && 
        alert.lastTriggered!.isBefore(cutoffDate) &&
        alert.triggerCount == 0);
    
    if (_alerts.length != initialAlertCount) {
      developer.log('📊 Cleaned ${initialAlertCount - _alerts.length} old alerts');
    }
    
    await _saveHistory();
    await _saveAlerts();
  }

  Future<void> _saveMetrics() async {
    try {
      final file = File('${_dataFile}.metrics');
      
      final metricsData = _metrics.values.map((metric) => metric.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'metrics': metricsData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('📊 Failed to save metrics: $e');
    }
  }

  Future<void> _saveHistory() async {
    try {
      final file = File('${_dataFile}.history');
      
      final historyData = <String, dynamic>{};
      for (final entry in _history.entries) {
        historyData[entry.key] = {
          'points': entry.value.map((point) => point.toJson()).toList(),
        };
      }
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'history': historyData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('📊 Failed to save history: $e');
    }
  }

  Future<void> _saveAlerts() async {
    try {
      final file = File('${_dataFile}.alerts');
      
      final alertsData = _alerts.values.map((alert) => alert.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'alerts': alertsData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('📊 Failed to save alerts: $e');
    }
  }

  Future<void> _saveDashboards() async {
    try {
      final file = File('${_dataFile}.dashboards');
      
      final dashboardsData = _dashboards.values.map((dashboard) => dashboard.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'dashboards': dashboardsData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('📊 Failed to save dashboards: $e');
    }
  }

  Future<String> createMetric({
    required String name,
    required String description,
    required MetricType type,
    required MetricCategory category,
    String? unit,
    double? min,
    double? max,
    List<Threshold>? thresholds,
    Map<String, dynamic>? config,
  }) async {
    final metricId = _generateMetricId();
    
    final metric = Metric(
      id: metricId,
      name: name,
      description: description,
      unit: unit ?? '',
      type: type,
      category: category,
      min: min,
      max: max,
      thresholds: thresholds ?? [],
      config: config ?? {},
      enabled: true,
      currentValue: null,
      createdAt: DateTime.now(),
      lastUpdated: DateTime.now(),
    );
    
    _metrics[metricId] = metric;
    _totalMetrics++;
    
    // Initialize history
    _history[metricId] = [];
    
    developer.log('📊 Created metric: $name');
    
    _emitEvent(MonitorEvent(
      type: MonitorEventType.metricCreated,
      metricId: metricId,
      metricName: name,
    ));
    
    await _saveMetrics();
    
    return metricId;
  }

  Future<String> createAlert({
    required String name,
    required String description,
    required String metricId,
    required AlertCondition condition,
    required List<Threshold> thresholds,
    Map<String, dynamic>? config,
  }) async {
    final alertId = _generateAlertId();
    
    final alert = Alert(
      id: alertId,
      name: name,
      description: description,
      metricId: metricId,
      condition: condition,
      thresholds: thresholds,
      config: config ?? {},
      enabled: true,
      lastTriggered: null,
      triggerCount: 0,
      createdAt: DateTime.now(),
    );
    
    _alerts[alertId] = alert;
    _totalAlerts++;
    
    developer.log('📊 Created alert: $name');
    
    _emitEvent(MonitorEvent(
      type: MonitorEventType.alertCreated,
      alertId: alertId,
      alertName: name,
    ));
    
    await _saveAlerts();
    
    return alertId;
  }

  Future<String> createDashboard({
    required String name,
    required String description,
    required DashboardLayout layout,
    required List<DashboardWidget> widgets,
  }) async {
    final dashboardId = _generateDashboardId();
    
    final dashboard = Dashboard(
      id: dashboardId,
      name: name,
      description: description,
      layout: layout,
      widgets: widgets,
      createdAt: DateTime.now(),
      lastModified: DateTime.now(),
      isDefault: false,
    );
    
    _dashboards[dashboardId] = dashboard;
    _totalDashboards++;
    
    developer.log('📊 Created dashboard: $name');
    
    _emitEvent(MonitorEvent(
      type: MonitorEventType.dashboardCreated,
      dashboardId: dashboardId,
      dashboardName: name,
    ));
    
    await _saveDashboards();
    
    return dashboardId;
  }

  Future<DashboardData> getDashboardData(String dashboardId) async {
    final dashboard = _dashboards[dashboardId];
    if (dashboard == null) {
      throw Exception('Dashboard not found: $dashboardId');
    }
    
    final widgetData = <String, WidgetData>{};
    
    for (final widget in dashboard.widgets) {
      final data = await _getWidgetData(widget);
      widgetData[widget.id] = data;
    }
    
    return DashboardData(
      dashboard: dashboard,
      widgets: widgetData,
      generatedAt: DateTime.now(),
    );
  }

  Future<WidgetData> _getWidgetData(DashboardWidget widget) async {
    final data = <String, dynamic>{};
    
    switch (widget.type) {
      case WidgetType.gauge:
        final metric = _metrics[widget.metricIds.first];
        if (metric != null && metric.currentValue != null) {
          data['value'] = metric.currentValue;
          data['unit'] = metric.unit;
          data['min'] = metric.min;
          data['max'] = metric.max;
          data['thresholds'] = metric.thresholds.map((t) => {
            'level': t.level.name,
            'value': t.value,
          }).toList();
        }
        break;
        
      case WidgetType.line:
        final history = widget.metricIds
            .map((id) => _history[id] ?? [])
            .expand((points) => points)
            .toList();
        
        data['points'] = history.map((point) => {
          'timestamp': point.timestamp.toIso8601String(),
          'value': point.value,
        }).toList();
        break;
        
      case WidgetType.counter:
        final metric = _metrics[widget.metricIds.first];
        if (metric != null && metric.currentValue != null) {
          data['value'] = metric.currentValue;
          data['unit'] = metric.unit;
        }
        break;
        
      case WidgetType.table:
        // For process table, get top processes
        if (widget.metricIds.contains('process_count')) {
          final processes = await _getTopProcesses();
          data['processes'] = processes;
        }
        break;
        
      case WidgetType.heatmap:
        final history = _history[widget.metricIds.first] ?? [];
        final heatmapData = _generateHeatmapData(history);
        data['heatmap'] = heatmapData;
        break;
    }
    
    return WidgetData(
      widget: widget,
      data: data,
      timestamp: DateTime.now(),
    );
  }

  List<Map<String, dynamic>> _getTopProcesses() {
    // Simplified top processes data
    return [
      {'name': 'termisol', 'cpu': 5.2, 'memory': 128.5, 'pid': 1234},
      {'name': 'chrome', 'cpu': 12.8, 'memory': 512.3, 'pid': 5678},
      {'name': 'firefox', 'cpu': 8.4, 'memory': 256.7, 'pid': 9012},
      {'name': 'code', 'cpu': 3.1, 'memory': 89.2, 'pid': 3456},
      {'name': 'node', 'cpu': 6.7, 'memory': 145.8, 'pid': 7890},
    ];
  }

  List<Map<String, dynamic>> _generateHeatmapData(List<DataPoint> history) {
    final heatmapData = <Map<String, dynamic>>[];
    
    // Generate hourly heatmap for last 24 hours
    final now = DateTime.now();
    for (int hour = 0; hour < 24; hour++) {
      final hourTime = DateTime(now.year, now.month, now.day, hour);
      final hourPoints = history.where((point) => 
          point.timestamp.hour == hour &&
          point.timestamp.day == now.day &&
          point.timestamp.month == now.month &&
          point.timestamp.year == now.year).toList();
      
      final avgValue = hourPoints.isNotEmpty 
          ? hourPoints.map((p) => p.value).reduce((a, b) => a + b) / hourPoints.length
          : 0.0;
      
      heatmapData.add({
        'hour': hour,
        'value': avgValue,
        'count': hourPoints.length,
      });
    }
    
    return heatmapData;
  }

  Metric? getMetric(String metricId) {
    return _metrics[metricId];
  }

  List<Metric> getMetrics({MetricCategory? category}) {
    final metrics = _metrics.values.toList();
    
    if (category != null) {
      return metrics.where((metric) => metric.category == category).toList();
    }
    
    return metrics;
  }

  List<DataPoint> getHistory(String metricId, {DateTime? since, int? limit}) {
    final history = _history[metricId] ?? [];
    var filteredHistory = history.toList();
    
    if (since != null) {
      filteredHistory = filteredHistory.where((point) => point.timestamp.isAfter(since!)).toList();
    }
    
    filteredHistory.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    if (limit != null && limit! > 0) {
      filteredHistory = filteredHistory.take(limit!).toList();
    }
    
    return filteredHistory;
  }

  List<Alert> getAlerts({bool? enabled}) {
    final alerts = _alerts.values.toList();
    
    if (enabled != null) {
      return alerts.where((alert) => alert.enabled == enabled).toList();
    }
    
    return alerts;
  }

  List<Dashboard> getDashboards() {
    return _dashboards.values.toList();
  }

  MonitoringStats getStats() {
    return MonitoringStats(
      totalMetrics: _totalMetrics,
      enabledMetrics: _metrics.values.where((m) => m.enabled).length,
      totalAlerts: _totalAlerts,
      enabledAlerts: _alerts.values.where((a) => a.enabled).length,
      totalDashboards: _totalDashboards,
      isMonitoring: _isRunning,
      totalHistoryPoints: _history.values.fold(0, (sum, points) => sum + points.length),
      oldestDataPoint: _getOldestDataPoint(),
      newestDataPoint: _getNewestDataPoint(),
    );
  }

  DateTime? _getOldestDataPoint() {
    DateTime? oldest;
    
    for (final history in _history.values) {
      for (final point in history) {
        if (oldest == null || point.timestamp.isBefore(oldest)) {
          oldest = point.timestamp;
        }
      }
    }
    
    return oldest;
  }

  DateTime? _getNewestDataPoint() {
    DateTime? newest;
    
    for (final history in _history.values) {
      for (final point in history) {
        if (newest == null || point.timestamp.isAfter(newest)) {
          newest = point.timestamp;
        }
      }
    }
    
    return newest;
  }

  String _generateMetricId() {
    return 'metric_${DateTime.now().millisecondsSinceEpoch}_$_totalMetrics';
  }

  String _generateAlertId() {
    return 'alert_${DateTime.now().millisecondsSinceEpoch}_$_totalAlerts';
  }

  String _generateDashboardId() {
    return 'dashboard_${DateTime.now().millisecondsSinceEpoch}_$_totalDashboards';
  }

  void _emitEvent(MonitorEvent event) {
    _monitorController.add(event);
  }

  Stream<MonitorEvent> get monitorEventStream => _monitorController.stream;

  void dispose() {
    _updateTimer?.cancel();
    _cleanupTimer?.cancel();
    
    _isRunning = false;
    _metrics.clear();
    _history.clear();
    _alerts.clear();
    _dashboards.clear();
    _monitorController.close();
    
    developer.log('📊 System Monitoring Dashboard disposed');
  }
}

class Metric {
  final String id;
  final String name;
  final String description;
  final String unit;
  final MetricType type;
  final MetricCategory category;
  final double? min;
  final double? max;
  final List<Threshold> thresholds;
  final Map<String, dynamic> config;
  final bool enabled;
  double? currentValue;
  final DateTime createdAt;
  DateTime lastUpdated;

  Metric({
    required this.id,
    required this.name,
    required this.description,
    required this.unit,
    required this.type,
    required this.category,
    this.min,
    this.max,
    required this.thresholds,
    required this.config,
    required this.enabled,
    this.currentValue,
    required this.createdAt,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'unit': unit,
      'type': type.name,
      'category': category.name,
      'min': min,
      'max': max,
      'thresholds': thresholds.map((t) => t.toJson()).toList(),
      'config': config,
      'enabled': enabled,
      'current_value': currentValue,
      'created_at': createdAt.toIso8601String(),
      'last_updated': lastUpdated.toIso8601String(),
    };
  }

  factory Metric.fromJson(Map<String, dynamic> json) {
    return Metric(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      unit: json['unit'],
      type: MetricType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => MetricType.gauge,
      ),
      category: MetricCategory.values.firstWhere(
        (category) => category.name == json['category'],
        orElse: () => MetricCategory.system,
      ),
      min: json['min']?.toDouble(),
      max: json['max']?.toDouble(),
      thresholds: (json['thresholds'] as List?)
          ?.map((t) => Threshold.fromJson(t))
          .toList() ?? [],
      config: Map<String, dynamic>.from(json['config'] ?? {}),
      enabled: json['enabled'] ?? true,
      currentValue: json['current_value']?.toDouble(),
      createdAt: DateTime.parse(json['created_at']),
      lastUpdated: DateTime.parse(json['last_updated']),
    );
  }
}

class Alert {
  final String id;
  final String name;
  final String description;
  final String metricId;
  final AlertCondition condition;
  final List<Threshold> thresholds;
  final Map<String, dynamic> config;
  final bool enabled;
  final DateTime? lastTriggered;
  final int triggerCount;
  final DateTime createdAt;

  Alert({
    required this.id,
    required this.name,
    required this.description,
    required this.metricId,
    required this.condition,
    required this.thresholds,
    required this.config,
    required this.enabled,
    this.lastTriggered,
    required this.triggerCount,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'metric_id': metricId,
      'condition': condition.name,
      'thresholds': thresholds.map((t) => t.toJson()).toList(),
      'config': config,
      'enabled': enabled,
      'last_triggered': lastTriggered?.toIso8601String(),
      'trigger_count': triggerCount,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Alert.fromJson(Map<String, dynamic> json) {
    return Alert(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      metricId: json['metric_id'],
      condition: AlertCondition.values.firstWhere(
        (condition) => condition.name == json['condition'],
        orElse: () => AlertCondition.above,
      ),
      thresholds: (json['thresholds'] as List?)
          ?.map((t) => Threshold.fromJson(t))
          .toList() ?? [],
      config: Map<String, dynamic>.from(json['config'] ?? {}),
      enabled: json['enabled'] ?? true,
      lastTriggered: json['last_triggered'] != null ? DateTime.parse(json['last_triggered']) : null,
      triggerCount: json['trigger_count'] ?? 0,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class Threshold {
  final AlertLevel level;
  final double value;

  Threshold({
    required this.level,
    required this.value,
  });

  Map<String, dynamic> toJson() {
    return {
      'level': level.name,
      'value': value,
    };
  }

  factory Threshold.fromJson(Map<String, dynamic> json) {
    return Threshold(
      level: AlertLevel.values.firstWhere(
        (level) => level.name == json['level'],
        orElse: () => AlertLevel.info,
      ),
      value: json['value'].toDouble(),
    );
  }
}

class Dashboard {
  final String id;
  final String name;
  final String description;
  final DashboardLayout layout;
  final List<DashboardWidget> widgets;
  final DateTime createdAt;
  DateTime lastModified;
  final bool isDefault;

  Dashboard({
    required this.id,
    required this.name,
    required this.description,
    required this.layout,
    required this.widgets,
    required this.createdAt,
    required this.lastModified,
    required this.isDefault,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'layout': layout.name,
      'widgets': widgets.map((w) => w.toJson()).toList(),
      'created_at': createdAt.toIso8601String(),
      'last_modified': lastModified.toIso8601String(),
      'is_default': isDefault,
    };
  }

  factory Dashboard.fromJson(Map<String, dynamic> json) {
    return Dashboard(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      layout: DashboardLayout.values.firstWhere(
        (layout) => layout.name == json['layout'],
        orElse: () => DashboardLayout.grid,
      ),
      widgets: (json['widgets'] as List)
          ?.map((w) => DashboardWidget.fromJson(w))
          .toList() ?? [],
      createdAt: DateTime.parse(json['created_at']),
      lastModified: DateTime.parse(json['last_modified']),
      isDefault: json['is_default'] ?? false,
    );
  }
}

class DashboardWidget {
  final String id;
  final WidgetType type;
  final List<String> metricIds;
  final String title;
  final WidgetPosition position;
  final Map<String, dynamic> config;

  DashboardWidget({
    required this.id,
    required this.type,
    required this.metricIds,
    required this.title,
    required this.position,
    required this.config,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'metric_ids': metricIds,
      'title': title,
      'position': position.toJson(),
      'config': config,
    };
  }

  factory DashboardWidget.fromJson(Map<String, dynamic> json) {
    return DashboardWidget(
      id: json['id'],
      type: WidgetType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => WidgetType.gauge,
      ),
      metricIds: List<String>.from(json['metric_ids'] ?? []),
      title: json['title'],
      position: WidgetPosition.fromJson(json['position']),
      config: Map<String, dynamic>.from(json['config'] ?? {}),
    );
  }
}

class WidgetPosition {
  final int x;
  final int y;
  final int width;
  final int height;

  WidgetPosition({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    };
  }

  factory WidgetPosition.fromJson(Map<String, dynamic> json) {
    return WidgetPosition(
      x: json['x'],
      y: json['y'],
      width: json['width'],
      height: json['height'],
    );
  }
}

class DataPoint {
  final DateTime timestamp;
  final double value;

  DataPoint({
    required this.timestamp,
    required this.value,
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'value': value,
    };
  }

  factory DataPoint.fromJson(Map<String, dynamic> json) {
    return DataPoint(
      timestamp: DateTime.parse(json['timestamp']),
      value: json['value'].toDouble(),
    );
  }
}

class WidgetData {
  final DashboardWidget widget;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  WidgetData({
    required this.widget,
    required this.data,
    required this.timestamp,
  });
}

class DashboardData {
  final Dashboard dashboard;
  final Map<String, WidgetData> widgets;
  final DateTime generatedAt;

  DashboardData({
    required this.dashboard,
    required this.widgets,
    required this.generatedAt,
  });
}

enum MetricType {
  gauge,
  counter,
  rate,
  histogram,
}

enum MetricCategory {
  system,
  network,
  storage,
  process,
  application,
}

enum AlertLevel {
  info,
  warning,
  critical,
}

enum AlertCondition {
  above,
  below,
  equals,
  notEquals,
}

enum DashboardLayout {
  grid,
  flex,
  tabs,
}

enum WidgetType {
  gauge,
  line,
  bar,
  counter,
  table,
  heatmap,
}

enum MonitorEventType {
  monitoringStarted,
  monitoringStopped,
  metricCreated,
  metricUpdated,
  alertCreated,
  alertTriggered,
  dashboardCreated,
  dashboardUpdated,
  collectionFailed,
}

class MonitorEvent {
  final MonitorEventType type;
  final String? metricId;
  final String? metricName;
  final String? alertId;
  final String? alertName;
  final String? dashboardId;
  final String? dashboardName;
  final AlertLevel? level;
  final double? value;
  final String? error;

  MonitorEvent({
    required this.type,
    this.metricId,
    this.metricName,
    this.alertId,
    this.alertName,
    this.dashboardId,
    this.dashboardName,
    this.level,
    this.value,
    this.error,
  });
}

class MonitoringStats {
  final int totalMetrics;
  final int enabledMetrics;
  final int totalAlerts;
  final int enabledAlerts;
  final int totalDashboards;
  final bool isMonitoring;
  final int totalHistoryPoints;
  final DateTime? oldestDataPoint;
  final DateTime? newestDataPoint;

  MonitoringStats({
    required this.totalMetrics,
    required this.enabledMetrics,
    required this.totalAlerts,
    required this.enabledAlerts,
    required this.totalDashboards,
    required this.isMonitoring,
    required this.totalHistoryPoints,
    this.oldestDataPoint,
    this.newestDataPoint,
  });
}
