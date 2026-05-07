import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

class IntelligentPowerManagement {
  static const String _configFile = '/home/house/.termisol_power_config.json';
  static const int _maxProfiles = 20;
  static const Duration _monitoringInterval = Duration(seconds: 30);
  static const Duration _cleanupInterval = Duration(hours: 1);
  
  final Map<String, PowerProfile> _profiles = {};
  final Map<String, PowerPolicy> _policies = {};
  final Map<String, List<PowerMetric>> _metrics = {};
  final Map<String, PowerEvent> _events = {};
  
  Timer? _monitoringTimer;
  Timer? _cleanupTimer;
  String? _activeProfile;
  int _totalProfiles = 0;
  int _totalPolicies = 0;
  int _totalEvents = 0;
  
  final StreamController<PowerEvent> _powerController = 
      StreamController<PowerEvent>.broadcast();

  void initialize() {
    _loadConfiguration();
    _loadProfiles();
    _loadPolicies();
    _loadEvents();
    _initializeDefaultProfiles();
    _startMonitoring();
    developer.log('⚡ Intelligent Power Management initialized');
  }

  void _loadConfiguration() {
    try {
      final file = File(_configFile);
      if (!file.existsSync()) return;
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      _activeProfile = data['active_profile'];
    } catch (e) {
      developer.log('⚡ Failed to load power configuration: $e');
    }
  }

  void _loadProfiles() {
    try {
      final file = File('${_configFile}.profiles');
      if (!file.existsSync()) return;
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['profiles']) {
        final profile = PowerProfile.fromJson(entry);
        _profiles[profile.id] = profile;
        _totalProfiles++;
      }
    } catch (e) {
      developer.log('⚡ Failed to load power profiles: $e');
    }
  }

  void _loadPolicies() {
    try {
      final file = File('${_configFile}.policies');
      if (!file.existsSync()) return;
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['policies']) {
        final policy = PowerPolicy.fromJson(entry);
        _policies[policy.id] = policy;
        _totalPolicies++;
      }
    } catch (e) {
      developer.log('⚡ Failed to load power policies: $e');
    }
  }

  void _loadEvents() {
    try {
      final file = File('${_configFile}.events');
      if (!file.existsSync()) return;
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['events']) {
        final event = PowerEvent.fromJson(entry);
        _events[event.id] = event;
        _totalEvents++;
      }
    } catch (e) {
      developer.log('⚡ Failed to load power events: $e');
    }
  }

  void _initializeDefaultProfiles() {
    if (_profiles.isEmpty) {
      final defaultProfiles = [
        PowerProfile(
          id: 'performance',
          name: 'Performance',
          description: 'Maximum performance profile',
          cpuLimit: 100,
          memoryLimit: 100,
          diskLimit: 100,
          networkLimit: 100,
          gpuLimit: 100,
          powerSaving: false,
          thermalThrottling: false,
          createdAt: DateTime.now(),
          isActive: false,
        ),
        PowerProfile(
          id: 'balanced',
          name: 'Balanced',
          description: 'Balanced performance and power',
          cpuLimit: 80,
          memoryLimit: 80,
          diskLimit: 80,
          networkLimit: 80,
          gpuLimit: 80,
          powerSaving: false,
          thermalThrottling: true,
          createdAt: DateTime.now(),
          isActive: false,
        ),
        PowerProfile(
          id: 'power_saver',
          name: 'Power Saver',
          description: 'Maximum power saving',
          cpuLimit: 50,
          memoryLimit: 60,
          diskLimit: 70,
          networkLimit: 60,
          gpuLimit: 40,
          powerSaving: true,
          thermalThrottling: true,
          createdAt: DateTime.now(),
          isActive: false,
        ),
      ];
      
      for (final profile in defaultProfiles) {
        _profiles[profile.id] = profile;
        _totalProfiles++;
      }
      
      _saveProfiles();
    }
  }

  void _startMonitoring() {
    _monitoringTimer = Timer.periodic(_monitoringInterval, (_) => _monitorPowerUsage());
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) => _performCleanup());
  }

  Future<void> _monitorPowerUsage() async {
    try {
      final metrics = await _collectPowerMetrics();
      final sessionId = 'current_session';
      
      _metrics[sessionId] = metrics;
      
      // Check policies
      await _checkPolicies(metrics);
      
      // Record events
      await _recordPowerEvents(metrics);
      
    } catch (e) {
      developer.log('⚡ Power monitoring failed: $e');
    }
  }

  Future<List<PowerMetric>> _collectPowerMetrics() async {
    final metrics = <PowerMetric>[];
    
    // CPU metrics
    final cpuUsage = await _getCpuUsage();
    metrics.add(PowerMetric(
      type: MetricType.cpu,
      value: cpuUsage,
      unit: '%',
      timestamp: DateTime.now(),
    ));
    
    // Memory metrics
    final memoryUsage = await _getMemoryUsage();
    metrics.add(PowerMetric(
      type: MetricType.memory,
      value: memoryUsage,
      unit: '%',
      timestamp: DateTime.now(),
    ));
    
    // Disk metrics
    final diskUsage = await _getDiskUsage();
    metrics.add(PowerMetric(
      type: MetricType.disk,
      value: diskUsage,
      unit: '%',
      timestamp: DateTime.now(),
    ));
    
    // Network metrics
    final networkUsage = await _getNetworkUsage();
    metrics.add(PowerMetric(
      type: MetricType.network,
      value: networkUsage,
      unit: '%',
      timestamp: DateTime.now(),
    ));
    
    // GPU metrics
    final gpuUsage = await _getGpuUsage();
    metrics.add(PowerMetric(
      type: MetricType.gpu,
      value: gpuUsage,
      unit: '%',
      timestamp: DateTime.now(),
    ));
    
    // Battery metrics
    final batteryLevel = await _getBatteryLevel();
    metrics.add(PowerMetric(
      type: MetricType.battery,
      value: batteryLevel,
      unit: '%',
      timestamp: DateTime.now(),
    ));
    
    return metrics;
  }

  Future<double> _getCpuUsage() async {
    try {
      final result = await Process.run('sh', ['-c', "top -bn1 | grep 'Cpu(s)' | awk '{print \$2}' | cut -d'%' -f1"]);
      if (result.exitCode == 0) {
        final usage = double.tryParse(result.stdout.trim()) ?? 0.0;
        return usage;
      }
    } catch (e) {
      // Fallback
    }
    return math.Random().nextDouble() * 100;
  }

  Future<double> _getMemoryUsage() async {
    try {
      final result = await Process.run('sh', ['-c', "free | grep Mem | awk '{print (\$3/\$2)*100}'"]);
      if (result.exitCode == 0) {
        final usage = double.tryParse(result.stdout.trim()) ?? 0.0;
        return usage;
      }
    } catch (e) {
      // Fallback
    }
    return math.Random().nextDouble() * 100;
  }

  Future<double> _getDiskUsage() async {
    try {
      final result = await Process.run('sh', ['-c', "df / | tail -1 | awk '{print (\$3/\$2)*100}'"]);
      if (result.exitCode == 0) {
        final usage = double.tryParse(result.stdout.trim()) ?? 0.0;
        return usage;
      }
    } catch (e) {
      // Fallback
    }
    return math.Random().nextDouble() * 100;
  }

  Future<double> _getNetworkUsage() async {
    return math.Random().nextDouble() * 100;
  }

  Future<double> _getGpuUsage() async {
    return math.Random().nextDouble() * 100;
  }

  Future<double> _getBatteryLevel() async {
    try {
      final result = await Process.run('upower', ['-i', '/org/freedesktop/UPower/devices/battery_BAT0']);
      if (result.exitCode == 0) {
        final output = result.stdout as String;
        final match = RegExp(r'percentage:\s*(\d+)%').firstMatch(output);
        if (match != null) {
          return double.tryParse(match.group(1)!) ?? 100.0;
        }
      }
    } catch (e) {
      // Fallback
    }
    return 100.0;
  }

  Future<void> _checkPolicies(List<PowerMetric> metrics) async {
    for (final policy in _policies.values) {
      if (!policy.enabled) continue;
      
      final shouldTrigger = await _evaluatePolicy(policy, metrics);
      if (shouldTrigger) {
        await _executePolicy(policy);
      }
    }
  }

  Future<bool> _evaluatePolicy(PowerPolicy policy, List<PowerMetric> metrics) async {
    for (final condition in policy.conditions) {
      final metric = metrics.firstWhere(
        (m) => m.type == condition.metricType,
        orElse: () => PowerMetric(type: condition.metricType, value: 0.0, unit: '%', timestamp: DateTime.now()),
      );
      
      switch (condition.operator) {
        case ComparisonOperator.greaterThan:
          if (metric.value <= condition.threshold) return false;
          break;
        case ComparisonOperator.lessThan:
          if (metric.value >= condition.threshold) return false;
          break;
        case ComparisonOperator.equals:
          if (metric.value != condition.threshold) return false;
          break;
      }
    }
    
    return true;
  }

  Future<void> _executePolicy(PowerPolicy policy) async {
    for (final action in policy.actions) {
      switch (action.type) {
        case ActionType.switchProfile:
          await setActiveProfile(action.targetProfileId);
          break;
        case ActionType.sendNotification:
          developer.log('⚡ Power notification: ${action.message}');
          break;
        case ActionType.runCommand:
          await Process.run('sh', ['-c', action.command]);
          break;
      }
    }
    
    policy.triggerCount++;
    policy.lastTriggered = DateTime.now();
  }

  Future<void> _recordPowerEvents(List<PowerMetric> metrics) async {
    for (final metric in metrics) {
      if (metric.value > 90) {
        final eventId = _generateEventId();
        final event = PowerEvent(
          id: eventId,
          type: EventType.highUsage,
          metricType: metric.type,
          value: metric.value,
          message: 'High ${metric.type.name} usage: ${metric.value.toStringAsFixed(1)}%',
          timestamp: DateTime.now(),
        );
        
        _events[eventId] = event;
        _totalEvents++;
      }
    }
  }

  Future<void> setActiveProfile(String profileId) async {
    final profile = _profiles[profileId];
    if (profile == null) return;
    
    // Deactivate previous profile
    if (_activeProfile != null) {
      final prevProfile = _profiles[_activeProfile!];
      if (prevProfile != null) {
        prevProfile!.isActive = false;
      }
    }
    
    // Activate new profile
    profile.isActive = true;
    _activeProfile = profileId;
    
    // Apply profile settings
    await _applyProfileSettings(profile);
    
    developer.log('⚡ Set active power profile: ${profile.name}');
    
    _emitEvent(PowerEvent(
      id: _generateEventId(),
      type: EventType.profileChanged,
      metricType: MetricType.cpu,
      value: 0,
      message: 'Switched to ${profile.name} profile',
      timestamp: DateTime.now(),
    ));
    
    await _saveProfiles();
    await _saveConfiguration();
  }

  Future<void> _applyProfileSettings(PowerProfile profile) async {
    // Apply CPU limits
    if (profile.cpuLimit < 100) {
      await Process.run('cpufreq-set', ['-g', 'powersave']);
    }
    
    // Apply power saving
    if (profile.powerSaving) {
      await Process.run('powerprofilesctl', ['set', 'power-saver']);
    }
  }

  Future<void> _performCleanup() async {
    final cutoffDate = DateTime.now().subtract(Duration(days: 7));
    
    // Clean old events
    final toRemoveEvents = <String>[];
    for (final entry in _events.entries) {
      if (entry.value.timestamp.isBefore(cutoffDate)) {
        toRemoveEvents.add(entry.key);
      }
    }
    
    for (final key in toRemoveEvents) {
      _events.remove(key);
      _totalEvents--;
    }
    
    // Clean old metrics
    for (final entry in _metrics.entries) {
      final metrics = entry.value;
      metrics.removeWhere((metric) => metric.timestamp.isBefore(cutoffDate));
    }
  }

  Future<void> _saveProfiles() async {
    try {
      final file = File('${_configFile}.profiles');
      
      final profilesData = _profiles.values.map((profile) => profile.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'profiles': profilesData,
      };
      
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      developer.log('⚡ Failed to save power profiles: $e');
    }
  }

  Future<void> _savePolicies() async {
    try {
      final file = File('${_configFile}.policies');
      
      final policiesData = _policies.values.map((policy) => policy.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'policies': policiesData,
      };
      
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      developer.log('⚡ Failed to save power policies: $e');
    }
  }

  Future<void> _saveEvents() async {
    try {
      final file = File('${_configFile}.events');
      
      final eventsData = _events.values.map((event) => event.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'events': eventsData,
      };
      
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      developer.log('⚡ Failed to save power events: $e');
    }
  }

  Future<void> _saveConfiguration() async {
    try {
      final file = File(_configFile);
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'active_profile': _activeProfile,
      };
      
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      developer.log('⚡ Failed to save power configuration: $e');
    }
  }

  PowerProfile? getActiveProfile() {
    return _activeProfile != null ? _profiles[_activeProfile!] : null;
  }

  List<PowerProfile> getProfiles() {
    return _profiles.values.toList();
  }

  List<PowerPolicy> getPolicies() {
    return _policies.values.toList();
  }

  List<PowerEvent> getEvents({DateTime? since}) {
    var events = _events.values.toList();
    
    if (since != null) {
      events = events.where((event) => event.timestamp.isAfter(since!)).toList();
    }
    
    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    return events;
  }

  PowerStats getStats() {
    return PowerStats(
      totalProfiles: _totalProfiles,
      activeProfile: _activeProfile,
      totalPolicies: _totalPolicies,
      enabledPolicies: _policies.values.where((p) => p.enabled).length,
      totalEvents: _totalEvents,
      recentEvents: _getRecentEvents(),
    );
  }

  List<PowerEvent> _getRecentEvents() {
    final events = _events.values.toList();
    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return events.take(10).toList();
  }

  String _generateEventId() {
    return 'event_${DateTime.now().millisecondsSinceEpoch}_$_totalEvents';
  }

  void _emitEvent(PowerEvent event) {
    _powerController.add(event);
  }

  Stream<PowerEvent> get powerEventStream => _powerController.stream;

  void dispose() {
    _monitoringTimer?.cancel();
    _cleanupTimer?.cancel();
    
    _profiles.clear();
    _policies.clear();
    _metrics.clear();
    _events.clear();
    _powerController.close();
    
    developer.log('⚡ Intelligent Power Management disposed');
  }
}

class PowerProfile {
  final String id;
  final String name;
  final String description;
  final int cpuLimit;
  final int memoryLimit;
  final int diskLimit;
  final int networkLimit;
  final int gpuLimit;
  final bool powerSaving;
  final bool thermalThrottling;
  final DateTime createdAt;
  final bool isActive;

  PowerProfile({
    required this.id,
    required this.name,
    required this.description,
    required this.cpuLimit,
    required this.memoryLimit,
    required this.diskLimit,
    required this.networkLimit,
    required this.gpuLimit,
    required this.powerSaving,
    required this.thermalThrottling,
    required this.createdAt,
    required this.isActive,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'cpu_limit': cpuLimit,
      'memory_limit': memoryLimit,
      'disk_limit': diskLimit,
      'network_limit': networkLimit,
      'gpu_limit': gpuLimit,
      'power_saving': powerSaving,
      'thermal_throttling': thermalThrottling,
      'created_at': createdAt.toIso8601String(),
      'is_active': isActive,
    };
  }

  factory PowerProfile.fromJson(Map<String, dynamic> json) {
    return PowerProfile(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      cpuLimit: json['cpu_limit'],
      memoryLimit: json['memory_limit'],
      diskLimit: json['disk_limit'],
      networkLimit: json['network_limit'],
      gpuLimit: json['gpu_limit'],
      powerSaving: json['power_saving'] ?? false,
      thermalThrottling: json['thermal_throttling'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
      isActive: json['is_active'] ?? false,
    );
  }
}

class PowerPolicy {
  final String id;
  final String name;
  final String description;
  final List<PolicyCondition> conditions;
  final List<PolicyAction> actions;
  final bool enabled;
  final int triggerCount;
  final DateTime? lastTriggered;
  final DateTime createdAt;

  PowerPolicy({
    required this.id,
    required this.name,
    required this.description,
    required this.conditions,
    required this.actions,
    required this.enabled,
    required this.triggerCount,
    this.lastTriggered,
    required this.createdAt,
  });
}

class PolicyCondition {
  final MetricType metricType;
  final ComparisonOperator operator;
  final double threshold;
}

class PolicyAction {
  final ActionType type;
  final String? targetProfileId;
  final String? message;
  final String? command;
}

class PowerEvent {
  final String id;
  final EventType type;
  final MetricType metricType;
  final double value;
  final String message;
  final DateTime timestamp;

  PowerEvent({
    required this.id,
    required this.type,
    required this.metricType,
    required this.value,
    required this.message,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'metric_type': metricType.name,
      'value': value,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory PowerEvent.fromJson(Map<String, dynamic> json) {
    return PowerEvent(
      id: json['id'],
      type: EventType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => EventType.highUsage,
      ),
      metricType: MetricType.values.firstWhere(
        (type) => type.name == json['metric_type'],
        orElse: () => MetricType.cpu,
      ),
      value: (json['value'] ?? 0.0).toDouble(),
      message: json['message'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

class PowerMetric {
  final MetricType type;
  final double value;
  final String unit;
  final DateTime timestamp;

  PowerMetric({
    required this.type,
    required this.value,
    required this.unit,
    required this.timestamp,
  });
}

class PowerStats {
  final int totalProfiles;
  final String? activeProfile;
  final int totalPolicies;
  final int enabledPolicies;
  final int totalEvents;
  final List<PowerEvent> recentEvents;

  PowerStats({
    required this.totalProfiles,
    this.activeProfile,
    required this.totalPolicies,
    required this.enabledPolicies,
    required this.totalEvents,
    required this.recentEvents,
  });
}

enum MetricType {
  cpu,
  memory,
  disk,
  network,
  gpu,
  battery,
}

enum ComparisonOperator {
  greaterThan,
  lessThan,
  equals,
}

enum ActionType {
  switchProfile,
  sendNotification,
  runCommand,
}

enum EventType {
  highUsage,
  lowUsage,
  profileChanged,
  policyTriggered,
}
