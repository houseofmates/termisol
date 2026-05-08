import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:process_run/process_run.dart';

/// Adaptive performance tuner with real-time optimization
/// 
/// Features:
/// - Dynamic performance tuning
/// - Workload-aware optimization
/// - Thermal-aware performance management
/// - Battery-aware power management
/// - Application-specific optimization
class AdaptivePerformanceTuner {
  final StreamController<PerformanceTuningEvent> _eventController = StreamController<PerformanceTuningEvent>.broadcast();
  
  final Map<String, PerformanceProfile> _profiles = {};
  final Map<String, PerformanceMetric> _metrics = {};
  final Map<String, OptimizationRule> _rules = {};
  final List<PerformanceAdjustment> _adjustmentHistory = [];
  
  Timer? _monitoringTimer;
  Timer? _tuningTimer;
  bool _isInitialized = false;
  bool _isTuning = false;
  String _currentProfile = 'balanced';
  late SharedPreferences _prefs;
  
  Stream<PerformanceTuningEvent> get events => _eventController.stream;
  bool get isInitialized => _isInitialized;
  bool get isTuning => _isTuning;
  String get currentProfile => _currentProfile;
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      
      // Load performance data
      await _loadPerformanceData();
      
      // Initialize performance profiles
      _initializePerformanceProfiles();
      
      // Initialize optimization rules
      _initializeOptimizationRules();
      
      // Start monitoring
      _startPerformanceMonitoring();
      
      // Start adaptive tuning
      _startAdaptiveTuning();
      
      _isInitialized = true;
      
      _eventController.add(PerformanceTuningEvent(
        type: PerformanceTuningEventType.initialized,
        message: 'Adaptive performance tuner initialized',
        data: {
          'profiles': _profiles.length,
          'rules': _rules.length,
        },
      ));
      
      debugPrint('⚡ Adaptive Performance Tuner initialized');
    } catch (e) {
      debugPrint('Failed to initialize adaptive performance tuner: $e');
    }
  }
  
  Future<void> _loadPerformanceData() async {
    try {
      final profilesJson = _prefs.getString('performance_profiles');
      if (profilesJson != null) {
        final profilesMap = jsonDecode(profilesJson);
        _profiles = profilesMap.map((key, value) => 
          MapEntry(key, PerformanceProfile.fromJson(value)));
      }
      
      final rulesJson = _prefs.getString('optimization_rules');
      if (rulesJson != null) {
        final rulesMap = jsonDecode(rulesJson);
        _rules = rulesMap.map((key, value) => 
          MapEntry(key, OptimizationRule.fromJson(value)));
      }
      
      _currentProfile = _prefs.getString('current_profile') ?? 'balanced';
      
      final historyJson = _prefs.getString('adjustment_history');
      if (historyJson != null) {
        final historyList = jsonDecode(historyJson);
        _adjustmentHistory = historyList.map((item) => 
          PerformanceAdjustment.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint('Failed to load performance data: $e');
    }
  }
  
  void _initializePerformanceProfiles() {
    // Power saving profile
    _profiles['power_saving'] = PerformanceProfile(
      name: 'power_saving',
      displayName: 'Power Saving',
      description: 'Optimize for maximum battery life',
      cpuGovernor: 'powersave',
      cpuFrequency: 800.0,
      maxCpuUsage: 50.0,
      maxMemoryUsage: 60.0,
      diskScheduler: 'cfq',
      swappiness: 10,
      thermalThrottling: 70.0,
      networkLatency: 'high',
      graphicsPerformance: 'low',
    );
    
    // Balanced profile
    _profiles['balanced'] = PerformanceProfile(
      name: 'balanced',
      displayName: 'Balanced',
      description: 'Optimize for balanced performance and power',
      cpuGovernor: 'ondemand',
      cpuFrequency: 1600.0,
      maxCpuUsage: 75.0,
      maxMemoryUsage: 75.0,
      diskScheduler: 'deadline',
      swappiness: 60,
      thermalThrottling: 80.0,
      networkLatency: 'medium',
      graphicsPerformance: 'medium',
    );
    
    // High performance profile
    _profiles['high_performance'] = PerformanceProfile(
      name: 'high_performance',
      displayName: 'High Performance',
      description: 'Optimize for maximum performance',
      cpuGovernor: 'performance',
      cpuFrequency: 2400.0,
      maxCpuUsage: 90.0,
      maxMemoryUsage: 85.0,
      diskScheduler: 'noop',
      swappiness: 1,
      thermalThrottling: 85.0,
      networkLatency: 'low',
      graphicsPerformance: 'high',
    );
    
    // Gaming profile
    _profiles['gaming'] = PerformanceProfile(
      name: 'gaming',
      displayName: 'Gaming',
      description: 'Optimize for gaming performance',
      cpuGovernor: 'performance',
      cpuFrequency: 2800.0,
      maxCpuUsage: 95.0,
      maxMemoryUsage: 90.0,
      diskScheduler: 'deadline',
      swappiness: 1,
      thermalThrottling: 90.0,
      networkLatency: 'low',
      graphicsPerformance: 'ultra',
    );
    
    // Development profile
    _profiles['development'] = PerformanceProfile(
      name: 'development',
      displayName: 'Development',
      description: 'Optimize for development workloads',
      cpuGovernor: 'ondemand',
      cpuFrequency: 2000.0,
      maxCpuUsage: 80.0,
      maxMemoryUsage: 80.0,
      diskScheduler: 'deadline',
      swappiness: 10,
      thermalThrottling: 75.0,
      networkLatency: 'medium',
      graphicsPerformance: 'medium',
    );
  }
  
  void _initializeOptimizationRules() {
    // Thermal management rules
    _rules['thermal_throttling'] = OptimizationRule(
      id: 'thermal_throttling',
      name: 'Thermal Throttling',
      description: 'Reduce performance when temperature is high',
      condition: 'temperature > 80',
      action: 'switch_to_power_saving',
      priority: RulePriority.critical,
      enabled: true,
    );
    
    // Battery management rules
    _rules['battery_saver'] = OptimizationRule(
      id: 'battery_saver',
      name: 'Battery Saver',
      description: 'Switch to power saving when battery is low',
      condition: 'battery_level < 20',
      action: 'switch_to_power_saving',
      priority: RulePriority.high,
      enabled: true,
    );
    
    // High load rules
    _rules['high_load_optimization'] = OptimizationRule(
      id: 'high_load_optimization',
      name: 'High Load Optimization',
      description: 'Optimize for high system load',
      condition: 'cpu_usage > 85 OR memory_usage > 85',
      action: 'optimize_resources',
      priority: RulePriority.medium,
      enabled: true,
    );
    
    // Idle optimization rules
    _rules['idle_optimization'] = OptimizationRule(
      id: 'idle_optimization',
      name: 'Idle Optimization',
      description: 'Optimize for idle system',
      condition: 'cpu_usage < 10 AND memory_usage < 30',
      action: 'switch_to_power_saving',
      priority: RulePriority.low,
      enabled: true,
    );
  }
  
  void _startPerformanceMonitoring() {
    _monitoringTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _collectPerformanceMetrics();
    });
  }
  
  void _startAdaptiveTuning() {
    _tuningTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _performAdaptiveTuning();
    });
  }
  
  Future<void> _collectPerformanceMetrics() async {
    try {
      final timestamp = DateTime.now();
      
      // CPU metrics
      final cpuUsage = await _getCPUUsage();
      final cpuFrequency = await _getCPUFrequency();
      final cpuTemperature = await _getCPUTemperature();
      
      _metrics['cpu_usage_${timestamp.millisecondsSinceEpoch}'] = PerformanceMetric(
        name: 'cpu_usage',
        value: cpuUsage,
        timestamp: timestamp,
        unit: 'percent',
      );
      
      _metrics['cpu_frequency_${timestamp.millisecondsSinceEpoch}'] = PerformanceMetric(
        name: 'cpu_frequency',
        value: cpuFrequency,
        timestamp: timestamp,
        unit: 'mhz',
      );
      
      _metrics['cpu_temperature_${timestamp.millisecondsSinceEpoch}'] = PerformanceMetric(
        name: 'cpu_temperature',
        value: cpuTemperature,
        timestamp: timestamp,
        unit: 'celsius',
      );
      
      // Memory metrics
      final memoryUsage = await _getMemoryUsage();
      _metrics['memory_usage_${timestamp.millisecondsSinceEpoch}'] = PerformanceMetric(
        name: 'memory_usage',
        value: memoryUsage,
        timestamp: timestamp,
        unit: 'percent',
      );
      
      // Disk metrics
      final diskIO = await _getDiskIO();
      _metrics['disk_io_${timestamp.millisecondsSinceEpoch}'] = PerformanceMetric(
        name: 'disk_io',
        value: diskIO,
        timestamp: timestamp,
        unit: 'mbps',
      );
      
      // Battery metrics
      final batteryLevel = await _getBatteryLevel();
      _metrics['battery_level_${timestamp.millisecondsSinceEpoch}'] = PerformanceMetric(
        name: 'battery_level',
        value: batteryLevel,
        timestamp: timestamp,
        unit: 'percent',
      );
      
      // Keep only last 500 metrics
      if (_metrics.length > 500) {
        final keys = _metrics.keys.toList()..sort();
        final toRemove = keys.take(_metrics.length - 500);
        for (final key in toRemove) {
          _metrics.remove(key);
        }
      }
      
    } catch (e) {
      debugPrint('Failed to collect performance metrics: $e');
    }
  }
  
  Future<void> _performAdaptiveTuning() async {
    if (_isTuning) return;
    
    try {
      _isTuning = true;
      
      // Check optimization rules
      await _checkOptimizationRules();
      
      // Analyze performance trends
      await _analyzePerformanceTrends();
      
      // Apply profile adjustments
      await _applyProfileAdjustments();
      
    } catch (e) {
      debugPrint('Failed to perform adaptive tuning: $e');
    } finally {
      _isTuning = false;
    }
  }
  
  Future<void> _checkOptimizationRules() async {
    try {
      final now = DateTime.now();
      final recentMetrics = _metrics.values.where((m) => 
          now.difference(m.timestamp).inMinutes < 5).toList();
      
      for (final rule in _rules.values) {
        if (!rule.enabled) continue;
        
        if (await _evaluateRuleCondition(rule.condition, recentMetrics)) {
          await _executeRuleAction(rule);
        }
      }
    } catch (e) {
      debugPrint('Failed to check optimization rules: $e');
    }
  }
  
  Future<bool> _evaluateRuleCondition(String condition, List<PerformanceMetric> metrics) async {
    try {
      // Simple condition evaluation
      if (condition.contains('temperature >')) {
        final tempValue = double.tryParse(condition.split('>')[1]) ?? 0.0;
        final currentTemp = await _getCPUTemperature();
        return currentTemp > tempValue;
      }
      
      if (condition.contains('battery_level <')) {
        final batteryValue = double.tryParse(condition.split('<')[1]) ?? 0.0;
        final currentBattery = await _getBatteryLevel();
        return currentBattery < batteryValue;
      }
      
      if (condition.contains('cpu_usage >')) {
        final cpuValue = double.tryParse(condition.split('>')[1]) ?? 0.0;
        final currentCpu = await _getCPUUsage();
        return currentCpu > cpuValue;
      }
      
      if (condition.contains('memory_usage >')) {
        final memValue = double.tryParse(condition.split('>')[1]) ?? 0.0;
        final currentMem = await _getMemoryUsage();
        return currentMem > memValue;
      }
      
      if (condition.contains('cpu_usage <')) {
        final cpuValue = double.tryParse(condition.split('<')[1]) ?? 0.0;
        final currentCpu = await _getCPUUsage();
        return currentCpu < cpuValue;
      }
      
      if (condition.contains('memory_usage <')) {
        final memValue = double.tryParse(condition.split('<')[1]) ?? 0.0;
        final currentMem = await _getMemoryUsage();
        return currentMem < memValue;
      }
      
      return false;
    } catch (e) {
      debugPrint('Failed to evaluate rule condition: $e');
      return false;
    }
  }
  
  Future<void> _executeRuleAction(OptimizationRule rule) async {
    try {
      switch (rule.action) {
        case 'switch_to_power_saving':
          await switchProfile('power_saving');
          break;
        case 'optimize_resources':
          await _optimizeSystemResources();
          break;
        default:
          debugPrint('Unknown rule action: ${rule.action}');
      }
      
      _eventController.add(PerformanceTuningEvent(
        type: PerformanceTuningEventType.rule_triggered,
        message: 'Optimization rule triggered: ${rule.name}',
        data: {
          'ruleId': rule.id,
          'action': rule.action,
        },
      ));
      
    } catch (e) {
      debugPrint('Failed to execute rule action: $e');
    }
  }
  
  Future<void> _analyzePerformanceTrends() async {
    try {
      final now = DateTime.now();
      final recentMetrics = _metrics.values.where((m) => 
          now.difference(m.timestamp).inMinutes < 30).toList();
      
      if (recentMetrics.length < 10) return;
      
      // Analyze CPU usage trend
      final cpuMetrics = recentMetrics.where((m) => m.name == 'cpu_usage').toList();
      if (cpuMetrics.isNotEmpty) {
        final cpuTrend = _calculateTrend(cpuMetrics);
        if (cpuTrend > 0.1) {
          // CPU usage increasing
          await _adjustCPUSettings(true);
        } else if (cpuTrend < -0.1) {
          // CPU usage decreasing
          await _adjustCPUSettings(false);
        }
      }
      
      // Analyze memory usage trend
      final memoryMetrics = recentMetrics.where((m) => m.name == 'memory_usage').toList();
      if (memoryMetrics.isNotEmpty) {
        final memoryTrend = _calculateTrend(memoryMetrics);
        if (memoryTrend > 0.1) {
          // Memory usage increasing
          await _adjustMemorySettings(true);
        } else if (memoryTrend < -0.1) {
          // Memory usage decreasing
          await _adjustMemorySettings(false);
        }
      }
      
    } catch (e) {
      debugPrint('Failed to analyze performance trends: $e');
    }
  }
  
  double _calculateTrend(List<PerformanceMetric> metrics) {
    if (metrics.length < 2) return 0.0;
    
    final values = metrics.map((m) => m.value).toList();
    double sum = 0.0;
    
    for (int i = 1; i < values.length; i++) {
      sum += values[i] - values[i-1];
    }
    
    return sum / (values.length - 1);
  }
  
  Future<void> _applyProfileAdjustments() async {
    try {
      final profile = _profiles[_currentProfile];
      if (profile == null) return;
      
      // Get current system state
      final currentCpuUsage = await _getCPUUsage();
      final currentMemoryUsage = await _getMemoryUsage();
      final currentTemperature = await _getCPUTemperature();
      
      // Check if profile adjustments are needed
      bool needsAdjustment = false;
      
      if (currentCpuUsage > profile.maxCpuUsage) {
        needsAdjustment = true;
      }
      
      if (currentMemoryUsage > profile.maxMemoryUsage) {
        needsAdjustment = true;
      }
      
      if (currentTemperature > profile.thermalThrottling) {
        needsAdjustment = true;
      }
      
      if (needsAdjustment) {
        await _applyPerformanceProfile(profile);
      }
      
    } catch (e) {
      debugPrint('Failed to apply profile adjustments: $e');
    }
  }
  
  Future<void> switchProfile(String profileName) async {
    final profile = _profiles[profileName];
    if (profile == null) return;
    
    try {
      _currentProfile = profileName;
      await _applyPerformanceProfile(profile);
      
      await _prefs.setString('current_profile', profileName);
      
      _eventController.add(PerformanceTuningEvent(
        type: PerformanceTuningEventType.profile_switched,
        message: 'Switched to performance profile: ${profile.displayName}',
        data: {
          'profileName': profileName,
          'displayName': profile.displayName,
        },
      ));
      
    } catch (e) {
      debugPrint('Failed to switch profile: $e');
    }
  }
  
  Future<void> _applyPerformanceProfile(PerformanceProfile profile) async {
    try {
      // Apply CPU governor
      await run('echo', [profile.cpuGovernor, '>', '/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor']);
      
      // Apply CPU frequency
      await run('echo', ['${profile.cpuFrequency.toInt()}', '>', '/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq']);
      
      // Apply disk scheduler
      await run('echo', [profile.diskScheduler, '>', '/sys/block/sda/queue/scheduler']);
      
      // Apply swappiness
      await run('sysctl', ['-w', 'vm.swappiness=${profile.swappiness}']);
      
      // Apply network latency settings
      if (profile.networkLatency == 'low') {
        await run('sysctl', ['-w', 'net.core.rmem_max=16777216']);
        await run('sysctl', ['-w', 'net.core.wmem_max=16777216']);
      }
      
      _eventController.add(PerformanceTuningEvent(
        type: PerformanceTuningEventType.profile_applied,
        message: 'Applied performance profile: ${profile.displayName}',
        data: {
          'profileName': profile.name,
          'settings': profile.toJson(),
        },
      ));
      
    } catch (e) {
      debugPrint('Failed to apply performance profile: $e');
    }
  }
  
  Future<void> _adjustCPUSettings(bool increaseLoad) async {
    try {
      if (increaseLoad) {
        // Increase CPU performance
        await run('echo', 'performance', '>', '/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor');
      } else {
        // Decrease CPU performance
        await run('echo', 'ondemand', '>', '/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor');
      }
      
    } catch (e) {
      debugPrint('Failed to adjust CPU settings: $e');
    }
  }
  
  Future<void> _adjustMemorySettings(bool increaseLoad) async {
    try {
      if (increaseLoad) {
        // Optimize for higher memory usage
        await run('sysctl', ['-w', 'vm.swappiness=10']);
      } else {
        // Optimize for lower memory usage
        await run('sysctl', ['-w', 'vm.swappiness=60']);
      }
      
    } catch (e) {
      debugPrint('Failed to adjust memory settings: $e');
    }
  }
  
  Future<void> _optimizeSystemResources() async {
    try {
      // Clear system caches
      await run('sync', []);
      await run('sysctl', ['-w', 'vm.drop_caches=3']);
      
      // Optimize process priorities
      await run('renice', ['+5', '-p', '$pid']);
      
      // Adjust I/O priorities
      await run('ionice', ['-c', '3', '-p', '$pid']);
      
      _eventController.add(PerformanceTuningEvent(
        type: PerformanceTuningEventType.resources_optimized,
        message: 'System resources optimized',
      ));
      
    } catch (e) {
      debugPrint('Failed to optimize system resources: $e');
    }
  }
  
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
  
  Future<double> _getDiskIO() async {
    try {
      final result = await run('iostat', ['-x', '1', '1']);
      return 25.0; // Simplified implementation
    } catch (e) {
      return 0.0;
    }
  }
  
  Future<double> _getBatteryLevel() async {
    try {
      final result = await run('upower', ['-i', '/org/freedesktop.UPower/devices/battery_BAT0']);
      final lines = result.stdout.split('\n');
      for (final line in lines) {
        if (line.contains('percentage:')) {
          final match = RegExp(r'percentage:\s+(\d+)').firstMatch(line);
          if (match != null) {
            return double.tryParse(match.group(1)!) ?? 0.0;
          }
        }
      }
      return 100.0; // Assume full battery if not detected
    } catch (e) {
      return 100.0;
    }
  }
  
  Future<void> savePerformanceData() async {
    try {
      final profilesMap = _profiles.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('performance_profiles', jsonEncode(profilesMap));
      
      final rulesMap = _rules.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('optimization_rules', jsonEncode(rulesMap));
      
      final historyList = _adjustmentHistory.take(50).map((item) => item.toJson()).toList();
      await _prefs.setString('adjustment_history', jsonEncode(historyList));
      
    } catch (e) {
      debugPrint('Failed to save performance data: $e');
    }
  }
  
  Map<String, dynamic> getStatistics() {
    return {
      'isInitialized': _isInitialized,
      'isTuning': _isTuning,
      'currentProfile': _currentProfile,
      'totalProfiles': _profiles.length,
      'totalRules': _rules.length,
      'metricsCount': _metrics.length,
      'adjustmentHistory': _adjustmentHistory.length,
    };
  }
  
  Future<void> dispose() async {
    _monitoringTimer?.cancel();
    _tuningTimer?.cancel();
    
    await savePerformanceData();
    
    _eventController.close();
    debugPrint('⚡ Adaptive Performance Tuner disposed');
  }
}

// Data models
class PerformanceProfile {
  final String name;
  final String displayName;
  final String description;
  final String cpuGovernor;
  final double cpuFrequency;
  final double maxCpuUsage;
  final double maxMemoryUsage;
  final String diskScheduler;
  final int swappiness;
  final double thermalThrottling;
  final String networkLatency;
  final String graphicsPerformance;
  
  PerformanceProfile({
    required this.name,
    required this.displayName,
    required this.description,
    required this.cpuGovernor,
    required this.cpuFrequency,
    required this.maxCpuUsage,
    required this.maxMemoryUsage,
    required this.diskScheduler,
    required this.swappiness,
    required this.thermalThrottling,
    required this.networkLatency,
    required this.graphicsPerformance,
  });
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'displayName': displayName,
    'description': description,
    'cpuGovernor': cpuGovernor,
    'cpuFrequency': cpuFrequency,
    'maxCpuUsage': maxCpuUsage,
    'maxMemoryUsage': maxMemoryUsage,
    'diskScheduler': diskScheduler,
    'swappiness': swappiness,
    'thermalThrottling': thermalThrottling,
    'networkLatency': networkLatency,
    'graphicsPerformance': graphicsPerformance,
  };
  
  factory PerformanceProfile.fromJson(Map<String, dynamic> json) => PerformanceProfile(
    name: json['name'],
    displayName: json['displayName'],
    description: json['description'],
    cpuGovernor: json['cpuGovernor'],
    cpuFrequency: json['cpuFrequency']?.toDouble() ?? 0.0,
    maxCpuUsage: json['maxCpuUsage']?.toDouble() ?? 0.0,
    maxMemoryUsage: json['maxMemoryUsage']?.toDouble() ?? 0.0,
    diskScheduler: json['diskScheduler'],
    swappiness: json['swappiness'] ?? 60,
    thermalThrottling: json['thermalThrottling']?.toDouble() ?? 80.0,
    networkLatency: json['networkLatency'],
    graphicsPerformance: json['graphicsPerformance'],
  );
}

class PerformanceMetric {
  final String name;
  final double value;
  final DateTime timestamp;
  final String unit;
  
  PerformanceMetric({
    required this.name,
    required this.value,
    required this.timestamp,
    required this.unit,
  });
}

class OptimizationRule {
  final String id;
  final String name;
  final String description;
  final String condition;
  final String action;
  final RulePriority priority;
  final bool enabled;
  
  OptimizationRule({
    required this.id,
    required this.name,
    required this.description,
    required this.condition,
    required this.action,
    required this.priority,
    required this.enabled,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'condition': condition,
    'action': action,
    'priority': priority.name,
    'enabled': enabled,
  };
  
  factory OptimizationRule.fromJson(Map<String, dynamic> json) => OptimizationRule(
    id: json['id'],
    name: json['name'],
    description: json['description'],
    condition: json['condition'],
    action: json['action'],
    priority: RulePriority.values.firstWhere((p) => p.name == json['priority'], orElse: () => RulePriority.medium),
    enabled: json['enabled'] ?? true,
  );
}

class PerformanceAdjustment {
  final String id;
  final String type;
  final String description;
  final DateTime timestamp;
  final Map<String, dynamic> before;
  final Map<String, dynamic> after;
  final bool success;
  
  PerformanceAdjustment({
    required this.id,
    required this.type,
    required this.description,
    required this.timestamp,
    required this.before,
    required this.after,
    required this.success,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'description': description,
    'timestamp': timestamp.toIso8601String(),
    'before': before,
    'after': after,
    'success': success,
  };
  
  factory PerformanceAdjustment.fromJson(Map<String, dynamic> json) => PerformanceAdjustment(
    id: json['id'],
    type: json['type'],
    description: json['description'],
    timestamp: DateTime.parse(json['timestamp']),
    before: json['before'] ?? {},
    after: json['after'] ?? {},
    success: json['success'] ?? false,
  );
}

enum RulePriority {
  low,
  medium,
  high,
  critical,
}

enum PerformanceTuningEventType {
  initialized,
  profile_switched,
  profile_applied,
  rule_triggered,
  resources_optimized,
  error,
}

class PerformanceTuningEvent {
  final PerformanceTuningEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  
  PerformanceTuningEvent({
    required this.type,
    required this.message,
    this.data,
  }) : timestamp = DateTime.now();
}
