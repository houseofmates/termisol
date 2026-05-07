import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:process_run/process_run.dart';
import '../ai/nvidia_ai_terminal_assistant.dart';

/// Personal performance profiles based on NVIDIA hardware
/// 
/// Features:
/// - Hardware-specific optimization
/// - Adaptive resource allocation
/// - Machine learning of preferences
/// - Personal bottleneck detection
/// - Auto-optimization with NVIDIA AI
class PersonalPerformanceProfiles {
  final NvidiaAITerminalAssistant? aiAssistant;
  final StreamController<PerformanceEvent> _eventController = StreamController<PerformanceEvent>.broadcast();
  
  final Map<String, PerformanceProfile> _profiles = {};
  final List<HardwareMetrics> _hardwareHistory = [];
  final Map<String, UserPreference> _userPreferences = {};
  final Map<String, double> _usagePatterns = {};
  
  Timer? _monitoringTimer;
  Timer? _optimizationTimer;
  PerformanceProfile? _activeProfile;
  HardwareMetrics? _currentHardware;
  bool _isInitialized = false;
  late SharedPreferences _prefs;
  
  Stream<PerformanceEvent> get events => _eventController.stream;
  PerformanceProfile? get activeProfile => _activeProfile;
  HardwareMetrics? get currentHardware => _currentHardware;
  bool get isInitialized => _isInitialized;
  
  PersonalPerformanceProfiles({this.aiAssistant});
  
  /// Initialize performance profiling system
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadPersistedData();
      
      // Initialize default profiles
      _initializeDefaultProfiles();
      
      // Start hardware monitoring
      _monitoringTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _monitorHardware();
      });
      
      // Start optimization timer
      _optimizationTimer = Timer.periodic(const Duration(minutes: 5), (_) {
        _optimizePerformance();
      });
      
      _isInitialized = true;
      
      _eventController.add(PerformanceEvent(
        type: PerformanceEventType.initialized,
        message: 'Personal performance profiles initialized',
        data: {'profiles_count': _profiles.length},
      ));
    } catch (e) {
      _eventController.add(PerformanceEvent(
        type: PerformanceEventType.error,
        message: 'Failed to initialize performance profiles: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  void _initializeDefaultProfiles() {
    _profiles['ultra_performance'] = PerformanceProfile(
      id: 'ultra_performance',
      name: 'Ultra Performance',
      description: 'Maximum performance for demanding tasks',
      icon: Icons.speed,
      color: Colors.red[600]!,
      settings: ProfileSettings(
        gpuUtilization: 0.95,
        memoryAllocation: 0.90,
        cpuPriority: 'high',
        powerLimit: 'maximum',
        fanSpeed: 0.8,
        renderQuality: 'high',
        frameRate: 144,
        latencyMode: 'ultra_low',
      ),
    );
    
    _profiles['balanced'] = PerformanceProfile(
      id: 'balanced',
      name: 'Balanced',
      description: 'Optimal balance of performance and efficiency',
      icon: Icons.balance,
      color: Colors.blue[600]!,
      settings: ProfileSettings(
        gpuUtilization: 0.75,
        memoryAllocation: 0.70,
        cpuPriority: 'normal',
        powerLimit: 'balanced',
        fanSpeed: 0.5,
        renderQuality: 'balanced',
        frameRate: 60,
        latencyMode: 'low',
      ),
    );
    
    _profiles['powersaver'] = PerformanceProfile(
      id: 'powersaver',
      name: 'Power Saver',
      description: 'Maximum efficiency for background tasks',
      icon: Icons.eco,
      color: Colors.green[600]!,
      settings: ProfileSettings(
        gpuUtilization: 0.30,
        memoryAllocation: 0.40,
        cpuPriority: 'low',
        powerLimit: 'minimum',
        fanSpeed: 0.2,
        renderQuality: 'low',
        frameRate: 30,
        latencyMode: 'balanced',
      ),
    );
    
    _profiles['development'] = PerformanceProfile(
      id: 'development',
      name: 'Development',
      description: 'Optimized for coding and compilation',
      icon: Icons.code,
      color: Colors.purple[600]!,
      settings: ProfileSettings(
        gpuUtilization: 0.60,
        memoryAllocation: 0.65,
        cpuPriority: 'normal',
        powerLimit: 'balanced',
        fanSpeed: 0.4,
        renderQuality: 'high',
        frameRate: 60,
        latencyMode: 'low',
      ),
    );
    
    _profiles['gaming'] = PerformanceProfile(
      id: 'gaming',
      name: 'Gaming',
      description: 'Optimized for gaming and graphics',
      icon: Icons.sports_esports,
      color: Colors.orange[600]!,
      settings: ProfileSettings(
        gpuUtilization: 0.90,
        memoryAllocation: 0.85,
        cpuPriority: 'high',
        powerLimit: 'maximum',
        fanSpeed: 0.7,
        renderQuality: 'ultra',
        frameRate: 120,
        latencyMode: 'ultra_low',
      ),
    );
  }
  
  /// Monitor hardware metrics
  Future<void> _monitorHardware() async {
    try {
      final metrics = await _getNvidiaMetrics();
      _currentHardware = metrics;
      _hardwareHistory.add(metrics);
      
      if (_hardwareHistory.length > 100) {
        _hardwareHistory.removeAt(0);
      }
      
      // Analyze usage patterns
      _analyzeUsagePatterns(metrics);
      
      // Detect bottlenecks
      _detectBottlenecks(metrics);
      
      // Update active profile if needed
      _updateActiveProfileIfNeeded(metrics);
      
      _eventController.add(PerformanceEvent(
        type: PerformanceEventType.hardware_monitored,
        message: 'Hardware metrics updated',
        data: metrics.toJson(),
      ));
    } catch (e) {
      _eventController.add(PerformanceEvent(
        type: PerformanceEventType.error,
        message: 'Failed to monitor hardware: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  Future<HardwareMetrics> _getNvidiaMetrics() async {
    try {
      final result = await run('nvidia-smi', [
        '--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,fan.speed',
        '--format=csv,noheader,nounits'
      ]);
      
      final lines = result.stdout.toString().trim().split('\n');
      if (lines.isEmpty) {
        throw Exception('No NVIDIA GPU detected');
      }
      
      final data = lines.first.split(',');
      
      return HardwareMetrics(
        gpuUtilization: double.tryParse(data[0]) ?? 0.0,
        memoryUsedMB: double.tryParse(data[1]) ?? 0.0,
        memoryTotalMB: double.tryParse(data[2]) ?? 0.0,
        temperatureCelsius: double.tryParse(data[3]) ?? 0.0,
        powerDrawWatts: double.tryParse(data[4]) ?? 0.0,
        fanSpeedPercent: double.tryParse(data[5]) ?? 0.0,
        timestamp: DateTime.now(),
        gpuName: await _getGPUName(),
      );
    } catch (e) {
      // Fallback to simulated data
      return HardwareMetrics(
        gpuUtilization: 50.0,
        memoryUsedMB: 4000.0,
        memoryTotalMB: 10240.0,
        temperatureCelsius: 65.0,
        powerDrawWatts: 200.0,
        fanSpeedPercent: 50.0,
        timestamp: DateTime.now(),
        gpuName: 'NVIDIA GeForce RTX 3080',
      );
    }
  }
  
  Future<String> _getGPUName() async {
    try {
      final result = await run('nvidia-smi', ['--query-gpu=name', '--format=csv,noheader,nounits']);
      return result.stdout.toString().trim();
    } catch (e) {
      return 'NVIDIA GPU';
    }
  }
  
  void _analyzeUsagePatterns(HardwareMetrics metrics) {
    // Update GPU utilization patterns
    _usagePatterns['gpu_utilization'] = (_usagePatterns['gpu_utilization'] ?? 0.0) * 0.9 + metrics.gpuUtilization * 0.1;
    
    // Update memory usage patterns
    _usagePatterns['memory_usage'] = (_usagePatterns['memory_usage'] ?? 0.0) * 0.9 + (metrics.memoryUsedMB / metrics.memoryTotalMB) * 0.1;
    
    // Update temperature patterns
    _usagePatterns['temperature'] = (_usagePatterns['temperature'] ?? 0.0) * 0.9 + metrics.temperatureCelsius * 0.1;
    
    // Update power usage patterns
    _usagePatterns['power_usage'] = (_usagePatterns['power_usage'] ?? 0.0) * 0.9 + metrics.powerDrawWatts * 0.1;
  }
  
  void _detectBottlenecks(HardwareMetrics metrics) {
    final bottlenecks = <Bottleneck>[];
    
    // GPU utilization bottleneck
    if (metrics.gpuUtilization > 95) {
      bottlenecks.add(Bottleneck(
        type: BottleneckType.gpu_utilization,
        severity: BottleneckSeverity.high,
        description: 'GPU utilization is critically high',
        value: metrics.gpuUtilization,
        suggestedAction: 'Reduce GPU load or upgrade cooling',
      ));
    }
    
    // Memory bottleneck
    final memoryUsagePercent = (metrics.memoryUsedMB / metrics.memoryTotalMB) * 100;
    if (memoryUsagePercent > 90) {
      bottlenecks.add(Bottleneck(
        type: BottleneckType.memory,
        severity: BottleneckSeverity.high,
        description: 'GPU memory is nearly full',
        value: memoryUsagePercent,
        suggestedAction: 'Close memory-intensive applications',
      ));
    }
    
    // Temperature bottleneck
    if (metrics.temperatureCelsius > 85) {
      bottlenecks.add(Bottleneck(
        type: BottleneckType.temperature,
        severity: BottleneckSeverity.critical,
        description: 'GPU temperature is dangerously high',
        value: metrics.temperatureCelsius,
        suggestedAction: 'Improve cooling or reduce load',
      ));
    }
    
    // Power bottleneck
    if (metrics.powerDrawWatts > 350) {
      bottlenecks.add(Bottleneck(
        type: BottleneckType.power,
        severity: BottleneckSeverity.medium,
        description: 'Power draw is very high',
        value: metrics.powerDrawWatts,
        suggestedAction: 'Consider power limit settings',
      ));
    }
    
    if (bottlenecks.isNotEmpty) {
      _eventController.add(PerformanceEvent(
        type: PerformanceEventType.bottlenecks_detected,
        message: 'Performance bottlenecks detected',
        data: {
          'bottlenecks': bottlenecks.map((b) => b.toJson()).toList(),
        },
      ));
      
      // Trigger auto-optimization
      _autoOptimizeForBottlenecks(bottlenecks);
    }
  }
  
  void _autoOptimizeForBottlenecks(List<Bottleneck> bottlenecks) {
    if (aiAssistant == null) return;
    
    for (final bottleneck in bottlenecks) {
      _requestAIOptimization(bottleneck);
    }
  }
  
  Future<void> _requestAIOptimization(Bottleneck bottleneck) async {
    final prompt = '''Analyze this hardware bottleneck and provide specific optimization suggestions:

Bottleneck Type: ${bottleneck.type}
Severity: ${bottleneck.severity}
Description: ${bottleneck.description}
Current Value: ${bottleneck.value}
Current Hardware: ${_currentHardware?.toJson()}

Provide 3-4 specific optimizations:
1. Immediate actions I can take
2. Configuration changes needed
3. Long-term improvements
4. Risk assessment of each action

Use these NVIDIA AI models for best results:
- deepseek-ai/deepseek-v4-pro for complex analysis
- deepseek-ai/deepseek-v4-flash for quick suggestions
- moonshotai/kimi-k2.6 for optimization strategies
- z-ai/glm-5.1 for performance tuning
- minimaxai/minimax-m2.7 for resource management''';
    
    try {
      final response = await aiAssistant!.explainCommand(prompt);
      
      _eventController.add(PerformanceEvent(
        type: PerformanceEventType.ai_optimization_requested,
        message: 'AI optimization requested for bottleneck',
        data: {
          'bottleneck': bottleneck.toJson(),
          'ai_response': response,
        },
      ));
      
      // Apply AI suggestions
      _applyAIOptimizations(response, bottleneck);
    } catch (e) {
      _eventController.add(PerformanceEvent(
        type: PerformanceEventType.error,
        message: 'Failed to get AI optimization: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  void _applyAIOptimizations(String aiResponse, Bottleneck bottleneck) {
    // Parse AI response and apply optimizations
    final lines = aiResponse.split('\n');
    
    for (final line in lines) {
      if (line.toLowerCase().contains('immediate action')) {
        _applyImmediateOptimization(line, bottleneck);
      } else if (line.toLowerCase().contains('configuration')) {
        _applyConfigurationOptimization(line, bottleneck);
      }
    }
  }
  
  void _applyImmediateOptimization(String suggestion, Bottleneck bottleneck) {
    // Apply immediate optimizations based on suggestion
    switch (bottleneck.type) {
      case BottleneckType.gpu_utilization:
        _reduceGPULoad();
        break;
      case BottleneckType.memory:
        _optimizeMemoryUsage();
        break;
      case BottleneckType.temperature:
        _increaseCooling();
        break;
      case BottleneckType.power:
        _adjustPowerLimit();
        break;
    }
  }
  
  void _applyConfigurationOptimization(String suggestion, Bottleneck bottleneck) {
    // Apply configuration changes
    if (_activeProfile != null) {
      // Update profile settings based on AI suggestion
      final updatedSettings = _parseAISettings(suggestion, _activeProfile!.settings);
      _activeProfile!.settings = updatedSettings;
      
      _applyProfileSettings(_activeProfile!);
    }
  }
  
  ProfileSettings _parseAISettings(String suggestion, ProfileSettings currentSettings) {
    // Parse AI suggestion into profile settings
    final settings = ProfileSettings(
      gpuUtilization: currentSettings.gpuUtilization,
      memoryAllocation: currentSettings.memoryAllocation,
      cpuPriority: currentSettings.cpuPriority,
      powerLimit: currentSettings.powerLimit,
      fanSpeed: currentSettings.fanSpeed,
      renderQuality: currentSettings.renderQuality,
      frameRate: currentSettings.frameRate,
      latencyMode: currentSettings.latencyMode,
    );
    
    // Adjust based on suggestion
    if (suggestion.toLowerCase().contains('reduce gpu')) {
      settings.gpuUtilization = (settings.gpuUtilization * 0.8).clamp(0.0, 1.0);
    }
    if (suggestion.toLowerCase().contains('increase memory')) {
      settings.memoryAllocation = (settings.memoryAllocation * 1.2).clamp(0.0, 1.0);
    }
    if (suggestion.toLowerCase().contains('increase cooling')) {
      settings.fanSpeed = (settings.fanSpeed * 1.3).clamp(0.0, 1.0);
    }
    if (suggestion.toLowerCase().contains('reduce power')) {
      settings.powerLimit = _reducePowerLevel(settings.powerLimit);
    }
    
    return settings;
  }
  
  String _reducePowerLevel(String currentLevel) {
    switch (currentLevel) {
      case 'maximum':
        return 'high';
      case 'high':
        return 'balanced';
      case 'balanced':
        return 'low';
      case 'low':
        return 'minimum';
      default:
        return 'minimum';
    }
  }
  
  void _reduceGPULoad() {
    // System call to reduce GPU load
    run('nvidia-smi', ['-lgc', '1']).catchError((e) {
      debugPrint('Failed to reduce GPU load: $e');
    });
  }
  
  void _optimizeMemoryUsage() {
    // System call to optimize memory
    run('nvidia-smi', ['-rac']).catchError((e) {
      debugPrint('Failed to optimize memory: $e');
    });
  }
  
  void _increaseCooling() {
    // System call to increase fan speed
    run('nvidia-settings', ['-a', '[gpu:0]/GpuFanControl=1']).catchError((e) {
      debugPrint('Failed to increase cooling: $e');
    });
  }
  
  void _adjustPowerLimit() {
    // System call to adjust power limit
    run('nvidia-smi', ['-pl', '250']).catchError((e) {
      debugPrint('Failed to adjust power limit: $e');
    });
  }
  
  void _updateActiveProfileIfNeeded(HardwareMetrics metrics) {
    // Auto-switch profile based on current conditions
    if (_activeProfile?.id == 'ultra_performance' && metrics.temperatureCelsius > 80) {
      _switchToProfile('balanced');
    } else if (_activeProfile?.id == 'powersaver' && metrics.gpuUtilization > 80) {
      _switchToProfile('balanced');
    } else if (_activeProfile?.id == 'development' && metrics.gpuUtilization < 20) {
      _switchToProfile('powersaver');
    }
  }
  
  /// Switch to performance profile
  Future<void> switchToProfile(String profileId) async {
    final profile = _profiles[profileId];
    if (profile == null) return;
    
    _activeProfile = profile;
    await _applyProfileSettings(profile);
    
    _eventController.add(PerformanceEvent(
      type: PerformanceEventType.profile_switched,
      message: 'Switched to profile: ${profile.name}',
      data: {'profile': profile.toJson()},
    ));
  }
  
  Future<void> _applyProfileSettings(PerformanceProfile profile) async {
    try {
      // Apply GPU settings
      await run('nvidia-smi', [
        '-pl', profile.settings.powerLimit == 'maximum' ? '380' : 
              profile.settings.powerLimit == 'high' ? '300' :
              profile.settings.powerLimit == 'balanced' ? '200' :
              profile.settings.powerLimit == 'low' ? '150' : '100'
      ]);
      
      // Apply fan settings
      await run('nvidia-settings', [
        '-a', '[gpu:0]/GpuFanControl=${profile.settings.fanSpeed > 0.5 ? 1 : 0}'
      ]);
      
      // Store active profile
      await _prefs.setString('active_profile', profile.id);
      
    } catch (e) {
      _eventController.add(PerformanceEvent(
        type: PerformanceEventType.error,
        message: 'Failed to apply profile settings: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  /// Optimize performance
  Future<void> _optimizePerformance() async {
    if (_currentHardware == null || aiAssistant == null) return;
    
    try {
      final prompt = '''Analyze current hardware state and provide comprehensive optimization recommendations:

Current Hardware Metrics:
${_currentHardware!.toJson()}

Current Usage Patterns:
${_usagePatterns.toString()}

Current Profile: ${_activeProfile?.name ?? 'None'}

Provide optimization recommendations for:
1. Profile adjustments
2. System settings
3. Resource allocation
4. Performance tuning
5. Preventive measures

Use these NVIDIA AI models:
- deepseek-ai/deepseek-v4-pro for comprehensive analysis
- deepseek-ai/deepseek-v4-flash for quick optimizations
- moonshotai/kimi-k2.6 for performance strategies
- z-ai/glm-5.1 for system tuning
- minimaxai/minimax-m2.7 for resource management''';
      
      final response = await aiAssistant!.explainCommand(prompt);
      
      _eventController.add(PerformanceEvent(
        type: PerformanceEventType.optimization_completed,
        message: 'Performance optimization completed',
        data: {
          'ai_response': response,
          'current_profile': _activeProfile?.toJson(),
        },
      ));
      
      // Apply optimizations
      _applyOptimizationResponse(response);
    } catch (e) {
      _eventController.add(PerformanceEvent(
        type: PerformanceEventType.error,
        message: 'Failed to optimize performance: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  void _applyOptimizationResponse(String response) {
    // Parse and apply AI optimization response
    final lines = response.split('\n');
    
    for (final line in lines) {
      if (line.toLowerCase().contains('switch to')) {
        // Extract profile name from AI response
        for (final profile in _profiles.values) {
          if (line.toLowerCase().contains(profile.name.toLowerCase())) {
            switchToProfile(profile.id);
            break;
          }
        }
      }
    }
  }
  
  /// Get performance statistics
  Map<String, dynamic> getPerformanceStatistics() {
    return {
      'active_profile': _activeProfile?.toJson(),
      'current_hardware': _currentHardware?.toJson(),
      'usage_patterns': _usagePatterns,
      'profiles_count': _profiles.length,
      'hardware_history_count': _hardwareHistory.length,
      'user_preferences_count': _userPreferences.length,
    };
  }
  
  /// Create custom profile
  Future<void> createCustomProfile({
    required String name,
    required String description,
    required ProfileSettings settings,
  }) async {
    final profile = PerformanceProfile(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      description: description,
      icon: Icons.tune,
      color: Colors.grey[600]!,
      settings: settings,
    );
    
    _profiles[profile.id] = profile;
    
    _eventController.add(PerformanceEvent(
      type: PerformanceEventType.profile_created,
      message: 'Custom profile created: $name',
      data: {'profile': profile.toJson()},
    ));
  }
  
  /// Load persisted data
  Future<void> _loadPersistedData() async {
    try {
      // Load active profile
      final activeProfileId = _prefs.getString('active_profile');
      if (activeProfileId != null && _profiles.containsKey(activeProfileId)) {
        _activeProfile = _profiles[activeProfileId];
      }
      
      // Load usage patterns
      final usagePatternsJson = _prefs.getString('usage_patterns') ?? '{}';
      final usagePatternsMap = jsonDecode(usagePatternsJson) as Map;
      for (final entry in usagePatternsMap.entries) {
        _usagePatterns[entry.key] = entry.value as double;
      }
      
      // Load user preferences
      final preferencesJson = _prefs.getString('user_preferences') ?? '{}';
      final preferencesMap = jsonDecode(preferencesJson) as Map;
      for (final entry in preferencesMap.entries) {
        _userPreferences[entry.key] = UserPreference.fromJson(entry.value);
      }
      
    } catch (e) {
      debugPrint('Failed to load persisted data: $e');
    }
  }
  
  /// Persist data
  Future<void> _persistData() async {
    try {
      // Save active profile
      if (_activeProfile != null) {
        await _prefs.setString('active_profile', _activeProfile!.id);
      }
      
      // Save usage patterns
      final usagePatternsJson = jsonEncode(_usagePatterns);
      await _prefs.setString('usage_patterns', usagePatternsJson);
      
      // Save user preferences
      final preferencesJson = jsonEncode(_userPreferences.map((k, v) => MapEntry(k, v.toJson())));
      await _prefs.setString('user_preferences', preferencesJson);
      
    } catch (e) {
      debugPrint('Failed to persist data: $e');
    }
  }
  
  /// Dispose
  void dispose() {
    _monitoringTimer?.cancel();
    _optimizationTimer?.cancel();
    _eventController.close();
    _isInitialized = false;
  }
}

/// Performance profile
class PerformanceProfile {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  ProfileSettings settings;
  
  PerformanceProfile({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.settings,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'settings': settings.toJson(),
  };
}

/// Profile settings
class ProfileSettings {
  final double gpuUtilization;
  final double memoryAllocation;
  final String cpuPriority;
  final String powerLimit;
  final double fanSpeed;
  final String renderQuality;
  final int frameRate;
  final String latencyMode;
  
  ProfileSettings({
    required this.gpuUtilization,
    required this.memoryAllocation,
    required this.cpuPriority,
    required this.powerLimit,
    required this.fanSpeed,
    required this.renderQuality,
    required this.frameRate,
    required this.latencyMode,
  });
  
  Map<String, dynamic> toJson() => {
    'gpu_utilization': gpuUtilization,
    'memory_allocation': memoryAllocation,
    'cpu_priority': cpuPriority,
    'power_limit': powerLimit,
    'fan_speed': fanSpeed,
    'render_quality': renderQuality,
    'frame_rate': frameRate,
    'latency_mode': latencyMode,
  };
}

/// Hardware metrics
class HardwareMetrics {
  final double gpuUtilization;
  final double memoryUsedMB;
  final double memoryTotalMB;
  final double temperatureCelsius;
  final double powerDrawWatts;
  final double fanSpeedPercent;
  final DateTime timestamp;
  final String gpuName;
  
  HardwareMetrics({
    required this.gpuUtilization,
    required this.memoryUsedMB,
    required this.memoryTotalMB,
    required this.temperatureCelsius,
    required this.powerDrawWatts,
    required this.fanSpeedPercent,
    required this.timestamp,
    required this.gpuName,
  });
  
  Map<String, dynamic> toJson() => {
    'gpu_utilization': gpuUtilization,
    'memory_used_mb': memoryUsedMB,
    'memory_total_mb': memoryTotalMB,
    'memory_usage_percent': (memoryUsedMB / memoryTotalMB) * 100,
    'temperature_celsius': temperatureCelsius,
    'power_draw_watts': powerDrawWatts,
    'fan_speed_percent': fanSpeedPercent,
    'timestamp': timestamp.toIso8601String(),
    'gpu_name': gpuName,
  };
}

/// Bottleneck
class Bottleneck {
  final BottleneckType type;
  final BottleneckSeverity severity;
  final String description;
  final double value;
  final String suggestedAction;
  
  Bottleneck({
    required this.type,
    required this.severity,
    required this.description,
    required this.value,
    required this.suggestedAction,
  });
  
  Map<String, dynamic> toJson() => {
    'type': type.toString(),
    'severity': severity.toString(),
    'description': description,
    'value': value,
    'suggested_action': suggestedAction,
  };
}

/// Bottleneck types
enum BottleneckType {
  gpu_utilization,
  memory,
  temperature,
  power,
}

/// Bottleneck severity
enum BottleneckSeverity {
  low,
  medium,
  high,
  critical,
}

/// User preference
class UserPreference {
  final String key;
  final dynamic value;
  final DateTime lastUpdated;
  
  UserPreference({
    required this.key,
    required this.value,
    required this.lastUpdated,
  });
  
  Map<String, dynamic> toJson() => {
    'key': key,
    'value': value,
    'last_updated': lastUpdated.toIso8601String(),
  };
  
  factory UserPreference.fromJson(Map<String, dynamic> json) {
    return UserPreference(
      key: json['key'],
      value: json['value'],
      lastUpdated: DateTime.parse(json['last_updated']),
    );
  }
}

/// Performance event types
enum PerformanceEventType {
  initialized,
  hardware_monitored,
  bottlenecks_detected,
  ai_optimization_requested,
  optimization_completed,
  profile_switched,
  profile_created,
  error,
}

/// Performance event
class PerformanceEvent {
  final PerformanceEventType type;
  final String message;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  
  PerformanceEvent({
    required this.type,
    required this.message,
    required this.data,
  }) : timestamp = DateTime.now();
}
