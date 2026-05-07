import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:process_run/process_run.dart';

/// Intelligent power manager with adaptive energy optimization
/// 
/// Features:
/// - Adaptive power profile management
/// - Battery health monitoring
/// - Energy usage optimization
/// - Thermal-aware power management
/// - Predictive power saving
class IntelligentPowerManager {
  final StreamController<PowerEvent> _eventController = StreamController<PowerEvent>.broadcast();
  
  final Map<String, PowerProfile> _profiles = {};
  final Map<String, PowerMetric> _metrics = {};
  final Map<String, BatteryInfo> _batteryHistory = [];
  final List<PowerOptimization> _optimizations = [];
  final Map<String, PowerPolicy> _policies = {};
  
  Timer? _monitoringTimer;
  Timer? _optimizationTimer;
  Timer? _batteryCheckTimer;
  bool _isInitialized = false;
  bool _isOptimizing = false;
  String _currentProfile = 'balanced';
  late SharedPreferences _prefs;
  
  Stream<PowerEvent> get events => _eventController.stream;
  bool get isInitialized => _isInitialized;
  bool get isOptimizing => _isOptimizing;
  String get currentProfile => _currentProfile;
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      
      // Load power data
      await _loadPowerData();
      
      // Initialize power profiles
      _initializePowerProfiles();
      
      // Initialize power policies
      _initializePowerPolicies();
      
      // Start monitoring
      _startPowerMonitoring();
      
      // Start optimization
      _startPowerOptimization();
      
      // Start battery monitoring
      _startBatteryMonitoring();
      
      _isInitialized = true;
      
      _eventController.add(PowerEvent(
        type: PowerEventType.initialized,
        message: 'Intelligent power manager initialized',
        data: {
          'profiles': _profiles.length,
          'policies': _policies.length,
        },
      ));
      
      debugPrint('🔋 Intelligent Power Manager initialized');
    } catch (e) {
      debugPrint('Failed to initialize intelligent power manager: $e');
    }
  }
  
  Future<void> _loadPowerData() async {
    try {
      final profilesJson = _prefs.getString('power_profiles');
      if (profilesJson != null) {
        final profilesMap = jsonDecode(profilesJson);
        _profiles = profilesMap.map((key, value) => 
          MapEntry(key, PowerProfile.fromJson(value)));
      }
      
      final policiesJson = _prefs.getString('power_policies');
      if (policiesJson != null) {
        final policiesMap = jsonDecode(policiesJson);
        _policies = policiesMap.map((key, value) => 
          MapEntry(key, PowerPolicy.fromJson(value)));
      }
      
      final batteryJson = _prefs.getString('battery_history');
      if (batteryJson != null) {
        final batteryList = jsonDecode(batteryJson);
        _batteryHistory = batteryList.map((item) => 
          BatteryInfo.fromJson(item)).toList();
      }
      
      final optimizationsJson = _prefs.getString('power_optimizations');
      if (optimizationsJson != null) {
        final optimizationsList = jsonDecode(optimizationsJson);
        _optimizations = optimizationsList.map((item) => 
          PowerOptimization.fromJson(item)).toList();
      }
      
      _currentProfile = _prefs.getString('current_power_profile') ?? 'balanced';
    } catch (e) {
      debugPrint('Failed to load power data: $e');
    }
  }
  
  void _initializePowerProfiles() {
    // Power saving profile
    _profiles['power_saving'] = PowerProfile(
      name: 'power_saving',
      displayName: 'Power Saving',
      description: 'Maximum battery life with reduced performance',
      cpuGovernor: 'powersave',
      cpuFrequency: 800.0,
      maxCpuUsage: 50.0,
      screenBrightness: 30.0,
      wifiEnabled: true,
      bluetoothEnabled: false,
      thermalThrottling: 60.0,
      diskWriteCache: 'writeback',
      suspendTimeout: 300, // 5 minutes
      hibernateThreshold: 5.0, // 5% battery
    );
    
    // Balanced profile
    _profiles['balanced'] = PowerProfile(
      name: 'balanced',
      displayName: 'Balanced',
      description: 'Balance between performance and battery life',
      cpuGovernor: 'ondemand',
      cpuFrequency: 1600.0,
      maxCpuUsage: 75.0,
      screenBrightness: 70.0,
      wifiEnabled: true,
      bluetoothEnabled: true,
      thermalThrottling: 75.0,
      diskWriteCache: 'writeback',
      suspendTimeout: 600, // 10 minutes
      hibernateThreshold: 10.0, // 10% battery
    );
    
    // High performance profile
    _profiles['high_performance'] = PowerProfile(
      name: 'high_performance',
      displayName: 'High Performance',
      description: 'Maximum performance with higher power consumption',
      cpuGovernor: 'performance',
      cpuFrequency: 2400.0,
      maxCpuUsage: 90.0,
      screenBrightness: 100.0,
      wifiEnabled: true,
      bluetoothEnabled: true,
      thermalThrottling: 85.0,
      diskWriteCache: 'writeback',
      suspendTimeout: 0, // Never suspend
      hibernateThreshold: 5.0, // 5% battery
    );
    
    // Gaming profile
    _profiles['gaming'] = PowerProfile(
      name: 'gaming',
      displayName: 'Gaming',
      description: 'Optimized for gaming with performance priority',
      cpuGovernor: 'performance',
      cpuFrequency: 2800.0,
      maxCpuUsage: 95.0,
      screenBrightness: 100.0,
      wifiEnabled: true,
      bluetoothEnabled: false,
      thermalThrottling: 90.0,
      diskWriteCache: 'writeback',
      suspendTimeout: 0, // Never suspend
      hibernateThreshold: 10.0, // 10% battery
    );
    
    // Presentation profile
    _profiles['presentation'] = PowerProfile(
      name: 'presentation',
      displayName: 'Presentation',
      description: 'Optimized for presentations with no interruptions',
      cpuGovernor: 'ondemand',
      cpuFrequency: 2000.0,
      maxCpuUsage: 80.0,
      screenBrightness: 100.0,
      wifiEnabled: true,
      bluetoothEnabled: false,
      thermalThrottling: 70.0,
      diskWriteCache: 'writeback',
      suspendTimeout: 0, // Never suspend
      hibernateThreshold: 15.0, // 15% battery
    );
  }
  
  void _initializePowerPolicies() {
    // Battery conservation policy
    _policies['battery_conservation'] = PowerPolicy(
      id: 'battery_conservation',
      name: 'Battery Conservation',
      description: 'Conserve battery when running low',
      enabled: true,
      rules: [
        PowerRule(
          id: 'low_battery_power_save',
          description: 'Switch to power saving when battery is low',
          condition: 'battery_level < 20',
          action: 'switch_profile_power_saving',
          enabled: true,
        ),
        PowerRule(
          id: 'critical_battery_hibernate',
          description: 'Hibernate when battery is critical',
          condition: 'battery_level < 5',
          action: 'hibernate',
          enabled: true,
        ),
      ],
    );
    
    // Thermal management policy
    _policies['thermal_management'] = PowerPolicy(
      id: 'thermal_management',
      name: 'Thermal Management',
      description: 'Manage system temperature',
      enabled: true,
      rules: [
        PowerRule(
          id: 'high_temp_throttle',
          description: 'Throttle performance when temperature is high',
          condition: 'temperature > 80',
          action: 'switch_profile_power_saving',
          enabled: true,
        ),
        PowerRule(
          id: 'critical_temp_shutdown',
          description: 'Shutdown when temperature is critical',
          condition: 'temperature > 95',
          action: 'shutdown',
          enabled: true,
        ),
      ],
    );
    
    // Idle management policy
    _policies['idle_management'] = PowerPolicy(
      id: 'idle_management',
      name: 'Idle Management',
      description: 'Manage power during idle periods',
      enabled: true,
      rules: [
        PowerRule(
          id: 'idle_suspend',
          description: 'Suspend when idle for extended period',
          condition: 'idle_time > 1800', // 30 minutes
          action: 'suspend',
          enabled: true,
        ),
      ],
    );
  }
  
  void _startPowerMonitoring() {
    _monitoringTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _collectPowerMetrics();
    });
  }
  
  void _startPowerOptimization() {
    _optimizationTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _performPowerOptimization();
    });
  }
  
  void _startBatteryMonitoring() {
    _batteryCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _monitorBatteryStatus();
    });
  }
  
  Future<void> _collectPowerMetrics() async {
    try {
      final timestamp = DateTime.now();
      
      // CPU metrics
      final cpuUsage = await _getCpuUsage();
      final cpuFrequency = await _getCpuFrequency();
      final cpuTemperature = await _getCpuTemperature();
      
      _metrics['cpu_usage_${timestamp.millisecondsSinceEpoch}'] = PowerMetric(
        name: 'cpu_usage',
        value: cpuUsage,
        timestamp: timestamp,
        unit: 'percent',
        category: PowerCategory.cpu,
      );
      
      _metrics['cpu_frequency_${timestamp.millisecondsSinceEpoch}'] = PowerMetric(
        name: 'cpu_frequency',
        value: cpuFrequency,
        timestamp: timestamp,
        unit: 'mhz',
        category: PowerCategory.cpu,
      );
      
      _metrics['cpu_temperature_${timestamp.millisecondsSinceEpoch}'] = PowerMetric(
        name: 'cpu_temperature',
        value: cpuTemperature,
        timestamp: timestamp,
        unit: 'celsius',
        category: PowerCategory.thermal,
      );
      
      // Power consumption metrics
      final powerUsage = await _getPowerUsage();
      _metrics['power_usage_${timestamp.millisecondsSinceEpoch}'] = PowerMetric(
        name: 'power_usage',
        value: powerUsage,
        timestamp: timestamp,
        unit: 'watts',
        category: PowerCategory.consumption,
      );
      
      // Keep only last 300 metrics
      if (_metrics.length > 300) {
        final keys = _metrics.keys.toList()..sort();
        final toRemove = keys.take(_metrics.length - 300);
        for (final key in toRemove) {
          _metrics.remove(key);
        }
      }
      
    } catch (e) {
      debugPrint('Failed to collect power metrics: $e');
    }
  }
  
  Future<void> _performPowerOptimization() async {
    if (_isOptimizing) return;
    
    try {
      _isOptimizing = true;
      
      // Check power policies
      await _checkPowerPolicies();
      
      // Optimize based on current profile
      await _optimizeForProfile();
      
      // Predictive power management
      await _performPredictiveOptimization();
      
    } catch (e) {
      debugPrint('Failed to perform power optimization: $e');
    } finally {
      _isOptimizing = false;
    }
  }
  
  Future<void> _checkPowerPolicies() async {
    try {
      for (final policy in _policies.values) {
        if (!policy.enabled) continue;
        
        for (final rule in policy.rules) {
          if (!rule.enabled) continue;
          
          if (await _evaluatePowerRule(rule)) {
            await _executePowerRule(rule);
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to check power policies: $e');
    }
  }
  
  Future<bool> _evaluatePowerRule(PowerRule rule) async {
    try {
      final condition = rule.condition;
      
      if (condition.contains('battery_level')) {
        final batteryLevel = await _getBatteryLevel();
        final operator = condition.contains('<') ? '<' : '>';
        final threshold = double.tryParse(condition.split(operator)[1]) ?? 0.0;
        
        return operator == '<' ? batteryLevel < threshold : batteryLevel > threshold;
      }
      
      if (condition.contains('temperature')) {
        final temperature = await _getCpuTemperature();
        final operator = condition.contains('>') ? '>' : '<';
        final threshold = double.tryParse(condition.split(operator)[1]) ?? 0.0;
        
        return operator == '>' ? temperature > threshold : temperature < threshold;
      }
      
      if (condition.contains('idle_time')) {
        final idleTime = await _getIdleTime();
        final operator = condition.contains('>') ? '>' : '<';
        final threshold = double.tryParse(condition.split(operator)[1]) ?? 0.0;
        
        return operator == '>' ? idleTime > threshold : idleTime < threshold;
      }
      
      return false;
    } catch (e) {
      debugPrint('Failed to evaluate power rule: $e');
      return false;
    }
  }
  
  Future<void> _executePowerRule(PowerRule rule) async {
    try {
      switch (rule.action) {
        case 'switch_profile_power_saving':
          await switchProfile('power_saving');
          break;
        case 'hibernate':
          await _hibernate();
          break;
        case 'shutdown':
          await _shutdown();
          break;
        case 'suspend':
          await _suspend();
          break;
      }
      
      _eventController.add(PowerEvent(
        type: PowerEventType.policy_triggered,
        message: 'Power policy triggered: ${rule.description}',
        data: {
          'ruleId': rule.id,
          'action': rule.action,
        },
      ));
      
    } catch (e) {
      debugPrint('Failed to execute power rule: $e');
    }
  }
  
  Future<void> _optimizeForProfile() async {
    try {
      final profile = _profiles[_currentProfile];
      if (profile == null) return;
      
      // Apply CPU settings
      await _setCpuGovernor(profile.cpuGovernor);
      await _setCpuFrequency(profile.cpuFrequency);
      
      // Apply thermal settings
      await _setThermalThrottling(profile.thermalThrottling);
      
      // Apply disk settings
      await _setDiskWriteCache(profile.diskWriteCache);
      
      // Apply network settings
      await _setNetworkSettings(profile);
      
      // Apply display settings
      await _setDisplaySettings(profile);
      
    } catch (e) {
      debugPrint('Failed to optimize for profile: $e');
    }
  }
  
  Future<void> _performPredictiveOptimization() async {
    try {
      // Analyze usage patterns
      final usagePattern = await _analyzeUsagePattern();
      
      // Predict battery drain
      final batteryPrediction = await _predictBatteryDrain();
      
      // Adjust settings based on predictions
      if (usagePattern == UsagePattern.idle && batteryPrediction.timeToEmpty < 3600) { // Less than 1 hour
        await switchProfile('power_saving');
      }
      
      if (usagePattern == UsagePattern.heavy && batteryPrediction.timeToEmpty < 1800) { // Less than 30 minutes
        await _enableAggressivePowerSaving();
      }
      
    } catch (e) {
      debugPrint('Failed to perform predictive optimization: $e');
    }
  }
  
  Future<void> _monitorBatteryStatus() async {
    try {
      final batteryInfo = await _getBatteryInfo();
      _batteryHistory.add(batteryInfo);
      
      // Keep only last 100 battery readings
      if (_batteryHistory.length > 100) {
        _batteryHistory.removeRange(0, _batteryHistory.length - 100);
      }
      
      // Check for battery alerts
      if (batteryInfo.level < 10) {
        _eventController.add(PowerEvent(
          type: PowerEventType.battery_low,
          message: 'Battery level is critically low: ${batteryInfo.level.toStringAsFixed(1)}%',
          data: {
            'level': batteryInfo.level,
            'timeToEmpty': batteryInfo.timeToEmpty,
          },
        ));
      } else if (batteryInfo.level < 20) {
        _eventController.add(PowerEvent(
          type: PowerEventType.battery_warning,
          message: 'Battery level is low: ${batteryInfo.level.toStringAsFixed(1)}%',
          data: {
            'level': batteryInfo.level,
            'timeToEmpty': batteryInfo.timeToEmpty,
          },
        ));
      }
      
      // Save battery history
      await _savePowerData();
      
    } catch (e) {
      debugPrint('Failed to monitor battery status: $e');
    }
  }
  
  Future<void> switchProfile(String profileName) async {
    final profile = _profiles[profileName];
    if (profile == null) return;
    
    try {
      _currentProfile = profileName;
      await _applyPowerProfile(profile);
      
      await _prefs.setString('current_power_profile', profileName);
      
      _eventController.add(PowerEvent(
        type: PowerEventType.profile_switched,
        message: 'Switched to power profile: ${profile.displayName}',
        data: {
          'profileName': profileName,
          'displayName': profile.displayName,
        },
      ));
      
    } catch (e) {
      debugPrint('Failed to switch profile: $e');
    }
  }
  
  Future<void> _applyPowerProfile(PowerProfile profile) async {
    try {
      // Apply CPU settings
      await _setCpuGovernor(profile.cpuGovernor);
      await _setCpuFrequency(profile.cpuFrequency);
      
      // Apply thermal settings
      await _setThermalThrottling(profile.thermalThrottling);
      
      // Apply disk settings
      await _setDiskWriteCache(profile.diskWriteCache);
      
      // Apply network settings
      await _setNetworkSettings(profile);
      
      // Apply display settings
      await _setDisplaySettings(profile);
      
    } catch (e) {
      debugPrint('Failed to apply power profile: $e');
    }
  }
  
  Future<void> _setCpuGovernor(String governor) async {
    try {
      await run('echo', [governor, '>', '/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor']);
    } catch (e) {
      debugPrint('Failed to set CPU governor: $e');
    }
  }
  
  Future<void> _setCpuFrequency(double frequency) async {
    try {
      await run('echo', ['${frequency.toInt()}', '>', '/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq']);
    } catch (e) {
      debugPrint('Failed to set CPU frequency: $e');
    }
  }
  
  Future<void> _setThermalThrottling(double temperature) async {
    try {
      // Set thermal throttling threshold
      await run('sysctl', ['-w', 'vm.thermal_throttle=${temperature}']);
    } catch (e) {
      debugPrint('Failed to set thermal throttling: $e');
    }
  }
  
  Future<void> _setDiskWriteCache(String mode) async {
    try {
      await run('sysctl', ['-w', 'vm.dirty_writeback_centisecs=500']);
      await run('sysctl', ['-w', 'vm.dirty_expire_centisecs=3000']);
    } catch (e) {
      debugPrint('Failed to set disk write cache: $e');
    }
  }
  
  Future<void> _setNetworkSettings(PowerProfile profile) async {
    try {
      // Enable/disable WiFi
      if (!profile.wifiEnabled) {
        await run('nmcli', ['radio', 'wifi', 'off']);
      } else {
        await run('nmcli', ['radio', 'wifi', 'on']);
      }
      
      // Enable/disable Bluetooth
      if (!profile.bluetoothEnabled) {
        await run('bluetoothctl', ['power', 'off']);
      } else {
        await run('bluetoothctl', ['power', 'on']);
      }
    } catch (e) {
      debugPrint('Failed to set network settings: $e');
    }
  }
  
  Future<void> _setDisplaySettings(PowerProfile profile) async {
    try {
      // Set screen brightness
      await run('brightnessctl', ['set', '${profile.screenBrightness.toInt()}%']);
    } catch (e) {
      debugPrint('Failed to set display settings: $e');
    }
  }
  
  Future<void> _enableAggressivePowerSaving() async {
    try {
      // Disable unnecessary services
      await run('systemctl', ['stop', 'bluetooth.service']);
      await run('systemctl', ['stop', 'cups.service']);
      
      // Reduce CPU frequency further
      await _setCpuFrequency(600.0);
      
      // Set aggressive power saving
      await run('sysctl', ['-w', 'vm.laptop_mode=5']);
      await run('sysctl', ['-w', 'vm.dirty_ratio=15']);
      
    } catch (e) {
      debugPrint('Failed to enable aggressive power saving: $e');
    }
  }
  
  Future<void> _hibernate() async {
    try {
      await run('systemctl', ['hibernate']);
    } catch (e) {
      debugPrint('Failed to hibernate: $e');
    }
  }
  
  Future<void> _suspend() async {
    try {
      await run('systemctl', ['suspend']);
    } catch (e) {
      debugPrint('Failed to suspend: $e');
    }
  }
  
  Future<void> _shutdown() async {
    try {
      await run('systemctl', ['poweroff']);
    } catch (e) {
      debugPrint('Failed to shutdown: $e');
    }
  }
  
  // Helper methods for getting system information
  Future<double> _getCpuUsage() async {
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
  
  Future<double> _getCpuFrequency() async {
    try {
      final result = await run('cat', ['/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq']);
      final frequencyHz = double.tryParse(result.stdout.trim()) ?? 0.0;
      return frequencyHz / 1000000; // Convert to MHz
    } catch (e) {
      return 0.0;
    }
  }
  
  Future<double> _getCpuTemperature() async {
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
  
  Future<double> _getPowerUsage() async {
    try {
      final result = await run('cat', ['/sys/class/power_supply/BAT0/power_now']);
      final powerMicrowatts = double.tryParse(result.stdout.trim()) ?? 0.0;
      return powerMicrowatts / 1000000; // Convert to watts
    } catch (e) {
      return 0.0;
    }
  }
  
  Future<double> _getBatteryLevel() async {
    try {
      final result = await run('cat', ['/sys/class/power_supply/BAT0/capacity']);
      return double.tryParse(result.stdout.trim()) ?? 0.0;
    } catch (e) {
      return 100.0;
    }
  }
  
  Future<BatteryInfo> _getBatteryInfo() async {
    try {
      final level = await _getBatteryLevel();
      final powerUsage = await _getPowerUsage();
      final result = await run('cat', ['/sys/class/power_supply/BAT0/status']);
      final status = result.stdout.trim();
      
      // Calculate time to empty (simplified)
      final timeToEmpty = powerUsage > 0 ? (level / 100.0) / powerUsage * 60 : 0.0; // in minutes
      
      return BatteryInfo(
        level: level,
        status: status,
        powerUsage: powerUsage,
        timeToEmpty: timeToEmpty,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      return BatteryInfo(
        level: 100.0,
        status: 'Unknown',
        powerUsage: 0.0,
        timeToEmpty: 0.0,
        timestamp: DateTime.now(),
      );
    }
  }
  
  Future<double> _getIdleTime() async {
    try {
      final result = await run('xprintidle');
      final idleSeconds = double.tryParse(result.stdout.trim()) ?? 0.0;
      return idleSeconds;
    } catch (e) {
      return 0.0;
    }
  }
  
  Future<UsagePattern> _analyzeUsagePattern() async {
    try {
      final cpuUsage = await _getCpuUsage();
      final idleTime = await _getIdleTime();
      
      if (cpuUsage < 10 && idleTime > 300) {
        return UsagePattern.idle;
      } else if (cpuUsage > 70) {
        return UsagePattern.heavy;
      } else {
        return UsagePattern.moderate;
      }
    } catch (e) {
      return UsagePattern.moderate;
    }
  }
  
  Future<BatteryPrediction> _predictBatteryDrain() async {
    try {
      if (_batteryHistory.length < 5) {
        return BatteryPrediction(
          timeToEmpty: 0.0,
          drainRate: 0.0,
          confidence: 0.0,
        );
      }
      
      // Calculate recent drain rate
      final recentReadings = _batteryHistory.take(5).toList();
      double totalDrain = 0.0;
      
      for (int i = 1; i < recentReadings.length; i++) {
        final drain = recentReadings[i - 1].level - recentReadings[i].level;
        totalDrain += drain;
      }
      
      final drainRate = totalDrain / (recentReadings.length - 1);
      final currentLevel = _batteryHistory.first.level;
      final timeToEmpty = drainRate > 0 ? currentLevel / drainRate : 0.0;
      
      return BatteryPrediction(
        timeToEmpty: timeToEmpty * 60, // Convert to minutes
        drainRate: drainRate,
        confidence: 0.8,
      );
    } catch (e) {
      return BatteryPrediction(
        timeToEmpty: 0.0,
        drainRate: 0.0,
        confidence: 0.0,
      );
    }
  }
  
  Future<void> _savePowerData() async {
    try {
      final profilesMap = _profiles.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('power_profiles', jsonEncode(profilesMap));
      
      final policiesMap = _policies.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('power_policies', jsonEncode(policiesMap));
      
      final batteryList = _batteryHistory.map((item) => item.toJson()).toList();
      await _prefs.setString('battery_history', jsonEncode(batteryList));
      
      final optimizationsList = _optimizations.take(50).map((item) => item.toJson()).toList();
      await _prefs.setString('power_optimizations', jsonEncode(optimizationsList));
    } catch (e) {
      debugPrint('Failed to save power data: $e');
    }
  }
  
  Future<void> addCustomProfile({
    required String name,
    required String displayName,
    required String description,
    required String cpuGovernor,
    required double cpuFrequency,
    required double maxCpuUsage,
    required double screenBrightness,
    required bool wifiEnabled,
    required bool bluetoothEnabled,
    required double thermalThrottling,
    required String diskWriteCache,
    required int suspendTimeout,
    required double hibernateThreshold,
  }) async {
    final profile = PowerProfile(
      name: name,
      displayName: displayName,
      description: description,
      cpuGovernor: cpuGovernor,
      cpuFrequency: cpuFrequency,
      maxCpuUsage: maxCpuUsage,
      screenBrightness: screenBrightness,
      wifiEnabled: wifiEnabled,
      bluetoothEnabled: bluetoothEnabled,
      thermalThrottling: thermalThrottling,
      diskWriteCache: diskWriteCache,
      suspendTimeout: suspendTimeout,
      hibernateThreshold: hibernateThreshold,
    );
    
    _profiles[name] = profile;
    await _savePowerData();
    
    _eventController.add(PowerEvent(
      type: PowerEventType.profile_added,
      message: 'Custom power profile added: $displayName',
      data: {'profileName': name},
    ));
  }
  
  Map<String, dynamic> getStatistics() {
    return {
      'isInitialized': _isInitialized,
      'isOptimizing': _isOptimizing,
      'currentProfile': _currentProfile,
      'totalProfiles': _profiles.length,
      'totalPolicies': _policies.length,
      'enabledPolicies': _policies.values.where((p) => p.enabled).length,
      'batteryHistory': _batteryHistory.length,
      'metricsCount': _metrics.length,
    };
  }
  
  Future<void> dispose() async {
    _monitoringTimer?.cancel();
    _optimizationTimer?.cancel();
    _batteryCheckTimer?.cancel();
    
    await _savePowerData();
    
    _eventController.close();
    debugPrint('🔋 Intelligent Power Manager disposed');
  }
}

// Data models
class PowerProfile {
  final String name;
  final String displayName;
  final String description;
  final String cpuGovernor;
  final double cpuFrequency;
  final double maxCpuUsage;
  final double screenBrightness;
  final bool wifiEnabled;
  final bool bluetoothEnabled;
  final double thermalThrottling;
  final String diskWriteCache;
  final int suspendTimeout;
  final double hibernateThreshold;
  
  PowerProfile({
    required this.name,
    required this.displayName,
    required this.description,
    required this.cpuGovernor,
    required this.cpuFrequency,
    required this.maxCpuUsage,
    required this.screenBrightness,
    required this.wifiEnabled,
    required this.bluetoothEnabled,
    required this.thermalThrottling,
    required this.diskWriteCache,
    required this.suspendTimeout,
    required this.hibernateThreshold,
  });
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'displayName': displayName,
    'description': description,
    'cpuGovernor': cpuGovernor,
    'cpuFrequency': cpuFrequency,
    'maxCpuUsage': maxCpuUsage,
    'screenBrightness': screenBrightness,
    'wifiEnabled': wifiEnabled,
    'bluetoothEnabled': bluetoothEnabled,
    'thermalThrottling': thermalThrottling,
    'diskWriteCache': diskWriteCache,
    'suspendTimeout': suspendTimeout,
    'hibernateThreshold': hibernateThreshold,
  };
  
  factory PowerProfile.fromJson(Map<String, dynamic> json) => PowerProfile(
    name: json['name'],
    displayName: json['displayName'],
    description: json['description'],
    cpuGovernor: json['cpuGovernor'],
    cpuFrequency: json['cpuFrequency']?.toDouble() ?? 0.0,
    maxCpuUsage: json['maxCpuUsage']?.toDouble() ?? 0.0,
    screenBrightness: json['screenBrightness']?.toDouble() ?? 0.0,
    wifiEnabled: json['wifiEnabled'] ?? true,
    bluetoothEnabled: json['bluetoothEnabled'] ?? true,
    thermalThrottling: json['thermalThrottling']?.toDouble() ?? 0.0,
    diskWriteCache: json['diskWriteCache'],
    suspendTimeout: json['suspendTimeout'] ?? 0,
    hibernateThreshold: json['hibernateThreshold']?.toDouble() ?? 0.0,
  );
}

class PowerPolicy {
  final String id;
  final String name;
  final String description;
  final bool enabled;
  final List<PowerRule> rules;
  
  PowerPolicy({
    required this.id,
    required this.name,
    required this.description,
    required this.enabled,
    required this.rules,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'enabled': enabled,
    'rules': rules.map((r) => r.toJson()).toList(),
  };
  
  factory PowerPolicy.fromJson(Map<String, dynamic> json) => PowerPolicy(
    id: json['id'],
    name: json['name'],
    description: json['description'],
    enabled: json['enabled'] ?? true,
    rules: (json['rules'] as List<dynamic>?)
        ?.map((r) => PowerRule.fromJson(r))
        .toList() ?? [],
  );
}

class PowerRule {
  final String id;
  final String description;
  final String condition;
  final String action;
  final bool enabled;
  
  PowerRule({
    required this.id,
    required this.description,
    required this.condition,
    required this.action,
    required this.enabled,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'description': description,
    'condition': condition,
    'action': action,
    'enabled': enabled,
  };
  
  factory PowerRule.fromJson(Map<String, dynamic> json) => PowerRule(
    id: json['id'],
    description: json['description'],
    condition: json['condition'],
    action: json['action'],
    enabled: json['enabled'] ?? true,
  );
}

class PowerMetric {
  final String name;
  final double value;
  final DateTime timestamp;
  final String unit;
  final PowerCategory category;
  
  PowerMetric({
    required this.name,
    required this.value,
    required this.timestamp,
    required this.unit,
    required this.category,
  });
}

class BatteryInfo {
  final double level;
  final String status;
  final double powerUsage;
  final double timeToEmpty;
  final DateTime timestamp;
  
  BatteryInfo({
    required this.level,
    required this.status,
    required this.powerUsage,
    required this.timeToEmpty,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() => {
    'level': level,
    'status': status,
    'powerUsage': powerUsage,
    'timeToEmpty': timeToEmpty,
    'timestamp': timestamp.toIso8601String(),
  };
  
  factory BatteryInfo.fromJson(Map<String, dynamic> json) => BatteryInfo(
    level: json['level']?.toDouble() ?? 0.0,
    status: json['status'],
    powerUsage: json['powerUsage']?.toDouble() ?? 0.0,
    timeToEmpty: json['timeToEmpty']?.toDouble() ?? 0.0,
    timestamp: DateTime.parse(json['timestamp']),
  );
}

class PowerOptimization {
  final String id;
  final String type;
  final String description;
  final DateTime timestamp;
  final Map<String, dynamic> details;
  
  PowerOptimization({
    required this.id,
    required this.type,
    required this.description,
    required this.timestamp,
    required this.details,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'description': description,
    'timestamp': timestamp.toIso8601String(),
    'details': details,
  };
  
  factory PowerOptimization.fromJson(Map<String, dynamic> json) => PowerOptimization(
    id: json['id'],
    type: json['type'],
    description: json['description'],
    timestamp: DateTime.parse(json['timestamp']),
    details: json['details'] ?? {},
  );
}

class BatteryPrediction {
  final double timeToEmpty;
  final double drainRate;
  final double confidence;
  
  BatteryPrediction({
    required this.timeToEmpty,
    required this.drainRate,
    required this.confidence,
  });
}

enum PowerCategory {
  cpu,
  thermal,
  consumption,
  battery,
}

enum UsagePattern {
  idle,
  moderate,
  heavy,
}

enum PowerEventType {
  initialized,
  profile_switched,
  profile_added,
  policy_triggered,
  battery_low,
  battery_warning,
  error,
}

class PowerEvent {
  final PowerEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  
  PowerEvent({
    required this.type,
    required this.message,
    this.data,
  }) : timestamp = DateTime.now();
}
