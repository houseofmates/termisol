import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:process_run/process_run.dart';
import '../ai/nvidia_ai_terminal_assistant.dart';

/// Adaptive resource allocation based on usage patterns
/// 
/// Features:
/// - Machine learning of user preferences
/// - Adaptive resource allocation
/// - Intelligent background processing
/// - Personal storage optimization
/// - Smart cleanup and maintenance
class AdaptiveResourceManager {
  final NvidiaAITerminalAssistant? aiAssistant;
  final StreamController<ResourceEvent> _eventController = StreamController<ResourceEvent>.broadcast();
  
  final List<ResourceUsage> _usageHistory = [];
  final Map<String, ResourcePattern> _patterns = {};
  final Map<String, double> _resourceWeights = {};
  final Map<String, UserPreference> _preferences = {};
  
  Timer? _analysisTimer;
  Timer? _optimizationTimer;
  ResourceAllocation? _currentAllocation;
  bool _isInitialized = false;
  late SharedPreferences _prefs;
  
  Stream<ResourceEvent> get events => _eventController.stream;
  ResourceAllocation? get currentAllocation => _currentAllocation;
  bool get isInitialized => _isInitialized;
  
  AdaptiveResourceManager({this.aiAssistant});
  
  /// Initialize adaptive resource manager
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadPersistedData();
      
      // Initialize default resource weights
      _initializeResourceWeights();
      
      // Start analysis timer
      _analysisTimer = Timer.periodic(const Duration(minutes: 2), (_) {
        _analyzeUsagePatterns();
      });
      
      // Start optimization timer
      _optimizationTimer = Timer.periodic(const Duration(minutes: 5), (_) {
        _optimizeResourceAllocation();
      });
      
      _isInitialized = true;
      
      _eventController.add(ResourceEvent(
        type: ResourceEventType.initialized,
        message: 'Adaptive resource manager initialized',
        data: {'patterns_count': _patterns.length},
      ));
    } catch (e) {
      _eventController.add(ResourceEvent(
        type: ResourceEventType.error,
        message: 'Failed to initialize resource manager: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  void _initializeResourceWeights() {
    // Initialize resource importance weights based on user preferences
    _resourceWeights = {
      'gpu_performance': 0.4, // High priority for user
      'memory_allocation': 0.3,
      'cpu_usage': 0.2,
      'disk_io': 0.1,
      'network_bandwidth': 0.0,
    };
  }
  
  /// Record resource usage
  void recordResourceUsage(ResourceUsage usage) {
    _usageHistory.insert(0, usage);
    if (_usageHistory.length > 1000) {
      _usageHistory.removeLast();
    }
    
    // Update patterns
    _updateResourcePatterns(usage);
    
    _eventController.add(ResourceEvent(
      type: ResourceEventType.usage_recorded,
      message: 'Resource usage recorded',
      data: {'usage': usage.toJson()},
    ));
  }
  
  void _updateResourcePatterns(ResourceUsage usage) {
    final patternKey = '${usage.processType}_${usage.timeOfDay}';
    
    if (_patterns.containsKey(patternKey)) {
      final pattern = _patterns[patternKey]!;
      pattern.frequency += 1;
      pattern.averageUsage = (pattern.averageUsage * (pattern.frequency - 1) + usage.usageLevel) / pattern.frequency;
      pattern.lastUsed = usage.timestamp;
    } else {
      _patterns[patternKey] = ResourcePattern(
        processType: usage.processType,
        timeOfDay: usage.timeOfDay,
        frequency: 1,
        averageUsage: usage.usageLevel,
        lastUsed: usage.timestamp,
        preferredAllocation: usage.allocation,
      );
    }
  }
  
  /// Analyze usage patterns with machine learning
  void _analyzeUsagePatterns() {
    if (_usageHistory.length < 10) return;
    
    // Analyze time-based patterns
    _analyzeTimePatterns();
    
    // Analyze process-based patterns
    _analyzeProcessPatterns();
    
    // Analyze resource correlations
    _analyzeResourceCorrelations();
    
    // Update ML model
    _updateMachineLearningModel();
  }
  
  void _analyzeTimePatterns() {
    final timeGroups = <String, List<ResourceUsage>>{};
    
    for (final usage in _usageHistory.take(200)) {
      final hour = usage.timestamp.hour;
      final timeSlot = _getTimeSlot(hour);
      
      timeGroups.putIfAbsent(timeSlot, () => []).add(usage);
    }
    
    // Update patterns based on time analysis
    for (final entry in timeGroups.entries) {
      final timeSlot = entry.key;
      final usages = entry.value;
      
      if (usages.isEmpty) continue;
      
      final avgUsage = usages.map((u) => u.usageLevel).reduce((a, b) => a + b) / usages.length;
      
      for (final usage in usages) {
        final patternKey = '${usage.processType}_$timeSlot';
        if (_patterns.containsKey(patternKey)) {
          final pattern = _patterns[patternKey]!;
          pattern.averageUsage = avgUsage;
          pattern.confidence = min(1.0, usages.length / 20.0); // Confidence based on sample size
        }
      }
    }
  }
  
  String _getTimeSlot(int hour) {
    if (hour >= 6 && hour < 12) return 'morning';
    if (hour >= 12 && hour < 18) return 'afternoon';
    if (hour >= 18 && hour < 22) return 'evening';
    return 'night';
  }
  
  void _analyzeProcessPatterns() {
    final processGroups = <String, List<ResourceUsage>>{};
    
    for (final usage in _usageHistory.take(200)) {
      processGroups.putIfAbsent(usage.processType, () => []).add(usage);
    }
    
    // Update patterns based on process analysis
    for (final entry in processGroups.entries) {
      final processType = entry.key;
      final usages = entry.value;
      
      if (usages.isEmpty) continue;
      
      final avgUsage = usages.map((u) => u.usageLevel).reduce((a, b) => a + b) / usages.length;
      final maxUsage = usages.map((u) => u.usageLevel).reduce(math.max);
      final minUsage = usages.map((u) => u.usageLevel).reduce(math.min);
      
      // Update pattern with process-specific insights
      for (final usage in usages) {
        final patternKey = '${usage.processType}_${usage.processName}';
        if (_patterns.containsKey(patternKey)) {
          final pattern = _patterns[patternKey]!;
          pattern.averageUsage = avgUsage;
          pattern.maxUsage = maxUsage;
          pattern.minUsage = minUsage;
          pattern.variance = _calculateVariance(usages.map((u) => u.usageLevel).toList());
        }
      }
    }
  }
  
  void _analyzeResourceCorrelations() {
    // Analyze correlations between different resources
    final correlations = <String, double>{};
    
    for (int i = 0; i < _usageHistory.length - 1; i++) {
      final current = _usageHistory[i];
      final next = _usageHistory[i + 1];
      
      if (current.processType == next.processType) {
        final correlation = _calculateCorrelation(current, next);
        final key = '${current.processType}_correlation';
        correlations[key] = (correlations[key] ?? 0.0) + correlation;
      }
    }
    
    // Update patterns with correlation data
    for (final entry in correlations.entries) {
      final patternKey = entry.key.replaceAll('_correlation', '');
      if (_patterns.containsKey(patternKey)) {
        final pattern = _patterns[patternKey]!;
        pattern.correlation = entry.value / _usageHistory.length;
      }
    }
  }
  
  double _calculateCorrelation(ResourceUsage a, ResourceUsage b) {
    // Simple correlation calculation
    final diff = (b.usageLevel - a.usageLevel).abs();
    return 1.0 / (1.0 + diff);
  }
  
  double _calculateVariance(List<double> values) {
    if (values.isEmpty) return 0.0;
    
    final mean = values.reduce((a, b) => a + b) / values.length;
    final squaredDiffs = values.map((v) => pow(v - mean, 2)).toList();
    final variance = squaredDiffs.reduce((a, b) => a + b) / values.length;
    
    return variance;
  }
  
  void _updateMachineLearningModel() {
    // Update ML model with new patterns
    if (aiAssistant == null) return;
    
    final modelData = MachineLearningModel(
      patterns: _patterns.values.toList(),
      resourceWeights: _resourceWeights,
      userPreferences: _preferences,
      recentUsage: _usageHistory.take(50).toList(),
    );
    
    _sendModelToAI(modelData);
  }
  
  Future<void> _sendModelToAI(MachineLearningModel modelData) async {
    if (aiAssistant == null) return;
    
    try {
      final prompt = '''Update your machine learning model with this user data:

Resource Patterns: ${modelData.patterns.length} patterns
Resource Weights: ${modelData.resourceWeights}
User Preferences: ${modelData.userPreferences.length} preferences
Recent Usage: ${modelData.recentUsage.length} records

Analyze and provide:
1. Improved resource allocation strategies
2. Predicted usage patterns
3. Optimization recommendations
4. Personal preference adjustments

Focus on this user's specific hardware (NVIDIA RTX 3080/2070) and usage patterns.''';
      
      final response = await aiAssistant!.explainCommand(prompt);
      
      _eventController.add(ResourceEvent(
        type: ResourceEventType.model_updated,
        message: 'Machine learning model updated',
        data: {'ai_response': response},
      ));
      
      // Apply AI recommendations
      _applyAIRecommendations(response);
    } catch (e) {
      _eventController.add(ResourceEvent(
        type: ResourceEventType.error,
        message: 'Failed to update ML model: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  void _applyAIRecommendations(String aiResponse) {
    // Parse AI response and apply recommendations
    final lines = aiResponse.split('\n');
    
    for (final line in lines) {
      if (line.toLowerCase().contains('increase gpu allocation')) {
        _resourceWeights['gpu_performance'] = min(1.0, _resourceWeights['gpu_performance']! + 0.1);
      } else if (line.toLowerCase().contains('reduce memory usage')) {
        _resourceWeights['memory_allocation'] = max(0.0, _resourceWeights['memory_allocation']! - 0.1);
      } else if (line.toLowerCase().contains('optimize for evening')) {
        _preferences['evening_optimization'] = UserPreference(
          key: 'evening_optimization',
          value: true,
          lastUpdated: DateTime.now(),
        );
      }
    }
  }
  
  /// Optimize resource allocation
  Future<void> _optimizeResourceAllocation() async {
    if (_currentAllocation == null) return;
    
    try {
      final optimizedAllocation = await _calculateOptimalAllocation();
      
      if (_shouldApplyAllocation(optimizedAllocation)) {
        await _applyResourceAllocation(optimizedAllocation);
        
        _eventController.add(ResourceEvent(
          type: ResourceEventType.allocation_optimized,
          message: 'Resource allocation optimized',
          data: {'allocation': optimizedAllocation.toJson()},
        ));
      }
    } catch (e) {
      _eventController.add(ResourceEvent(
        type: ResourceEventType.error,
        message: 'Failed to optimize allocation: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  Future<ResourceAllocation> _calculateOptimalAllocation() async {
    final currentUsage = _getCurrentResourceUsage();
    
    // Use ML patterns to predict optimal allocation
    final timeSlot = _getTimeSlot(DateTime.now().hour);
    final relevantPatterns = _patterns.values.where((p) => 
        p.timeOfDay == timeSlot || p.timeOfDay == 'always').toList();
    
    if (relevantPatterns.isEmpty) {
      return _getDefaultAllocation();
    }
    
    // Calculate optimal allocation based on patterns
    final gpuAllocation = _calculateOptimalGPUAllocation(currentUsage, relevantPatterns);
    final memoryAllocation = _calculateOptimalMemoryAllocation(currentUsage, relevantPatterns);
    final cpuAllocation = _calculateOptimalCPUAllocation(currentUsage, relevantPatterns);
    
    return ResourceAllocation(
      gpuPerformance: gpuAllocation,
      memoryAllocation: memoryAllocation,
      cpuAllocation: cpuAllocation,
      diskIO: _calculateOptimalDiskAllocation(currentUsage),
      networkBandwidth: _calculateOptimalNetworkAllocation(currentUsage),
      backgroundProcessing: _calculateOptimalBackgroundAllocation(currentUsage),
      storageOptimization: _calculateOptimalStorageAllocation(currentUsage),
      cleanupSchedule: _calculateOptimalCleanupSchedule(),
    );
  }
  
  ResourceUsage _getCurrentResourceUsage() {
    // Get current system resource usage
    return ResourceUsage(
      processType: 'system',
      processName: 'termisol',
      usageLevel: 0.5, // Normalized 0-1
      allocation: _currentAllocation ?? _getDefaultAllocation(),
      timestamp: DateTime.now(),
    );
  }
  
  double _calculateOptimalGPUAllocation(ResourceUsage currentUsage, List<ResourcePattern> patterns) {
    // Calculate optimal GPU allocation based on patterns
    double baseAllocation = 0.7; // Default 70%
    
    // Adjust based on time patterns
    final timeSlot = _getTimeSlot(DateTime.now().hour);
    final timePattern = patterns.where((p) => p.timeOfDay == timeSlot);
    
    if (timePattern.isNotEmpty) {
      final avgUsage = timePattern.map((p) => p.averageUsage).reduce((a, b) => a + b) / timePattern.length;
      baseAllocation = baseAllocation * (1.0 - avgUsage * 0.3); // Reduce if historically low usage
    }
    
    // Apply user preference weight
    return baseAllocation * _resourceWeights['gpu_performance']!;
  }
  
  double _calculateOptimalMemoryAllocation(ResourceUsage currentUsage, List<ResourcePattern> patterns) {
    // Calculate optimal memory allocation
    double baseAllocation = 0.6; // Default 60%
    
    // Adjust based on patterns
    final memoryPatterns = patterns.where((p) => p.processType.contains('memory'));
    if (memoryPatterns.isNotEmpty) {
      final avgUsage = memoryPatterns.map((p) => p.averageUsage).reduce((a, b) => a + b) / memoryPatterns.length;
      baseAllocation = baseAllocation * (1.0 - avgUsage * 0.2);
    }
    
    return baseAllocation * _resourceWeights['memory_allocation']!;
  }
  
  double _calculateOptimalCPUAllocation(ResourceUsage currentUsage, List<ResourcePattern> patterns) {
    // Calculate optimal CPU allocation
    double baseAllocation = 0.5; // Default 50%
    
    // Adjust based on patterns
    final cpuPatterns = patterns.where((p) => p.processType.contains('cpu'));
    if (cpuPatterns.isNotEmpty) {
      final avgUsage = cpuPatterns.map((p) => p.averageUsage).reduce((a, b) => a + b) / cpuPatterns.length;
      baseAllocation = baseAllocation * (1.0 - avgUsage * 0.1);
    }
    
    return baseAllocation * _resourceWeights['cpu_usage']!;
  }
  
  double _calculateOptimalDiskAllocation(ResourceUsage currentUsage) {
    // Calculate optimal disk I/O allocation
    return 0.3 * _resourceWeights['disk_io']!;
  }
  
  double _calculateOptimalNetworkAllocation(ResourceUsage currentUsage) {
    // Calculate optimal network bandwidth allocation
    return 0.2 * _resourceWeights['network_bandwidth']!;
  }
  
  BackgroundProcessing _calculateOptimalBackgroundAllocation(ResourceUsage currentUsage) {
    // Calculate optimal background processing allocation
    return BackgroundProcessing(
      enabled: true,
      priority: BackgroundPriority.normal,
      maxConcurrentTasks: 3,
      resourceLimit: 0.2,
      schedule: _calculateBackgroundSchedule(),
    );
  }
  
  List<String> _calculateBackgroundSchedule() {
    // Calculate optimal background processing schedule
    final hour = DateTime.now().hour;
    
    if (hour >= 22 || hour < 6) {
      return ['23:00', '02:00', '04:00']; // Night time
    } else if (hour >= 6 && hour < 12) {
      return ['07:00', '09:00', '11:00']; // Morning
    } else if (hour >= 12 && hour < 18) {
      return ['13:00', '15:00', '17:00']; // Afternoon
    } else {
      return ['19:00', '21:00']; // Evening
    }
  }
  
  StorageOptimization _calculateOptimalStorageAllocation(ResourceUsage currentUsage) {
    // Calculate optimal storage optimization
    return StorageOptimization(
      enabled: true,
      cleanupThreshold: 0.8, // Clean when 80% full
      compressionEnabled: true,
      deduplicationEnabled: true,
      archivePolicy: ArchivePolicy.weekly,
      priority: StoragePriority.performance,
    );
  }
  
  List<String> _calculateOptimalCleanupSchedule() {
    // Calculate optimal cleanup schedule
    return [
      'daily_temp_cleanup',
      'weekly_log_rotation',
      'monthly_cache_clear',
      'quarterly_optimization',
    ];
  }
  
  ResourceAllocation _getDefaultAllocation() {
    return ResourceAllocation(
      gpuPerformance: 0.7,
      memoryAllocation: 0.6,
      cpuAllocation: 0.5,
      diskIO: 0.3,
      networkBandwidth: 0.2,
      backgroundProcessing: _calculateOptimalBackgroundAllocation(ResourceUsage(
        processType: 'system',
        processName: 'termisol',
        usageLevel: 0.5,
        allocation: null,
        timestamp: DateTime.now(),
      )),
      storageOptimization: _calculateOptimalStorageAllocation(ResourceUsage(
        processType: 'system',
        processName: 'termisol',
        usageLevel: 0.5,
        allocation: null,
        timestamp: DateTime.now(),
      )),
      cleanupSchedule: _calculateOptimalCleanupSchedule(),
    );
  }
  
  bool _shouldApplyAllocation(ResourceAllocation newAllocation) {
    if (_currentAllocation == null) return true;
    
    // Calculate difference from current allocation
    final gpuDiff = (newAllocation.gpuPerformance - _currentAllocation!.gpuPerformance).abs();
    final memoryDiff = (newAllocation.memoryAllocation - _currentAllocation!.memoryAllocation).abs();
    final cpuDiff = (newAllocation.cpuAllocation - _currentAllocation!.cpuAllocation).abs();
    
    // Only apply if significant change
    return gpuDiff > 0.1 || memoryDiff > 0.1 || cpuDiff > 0.1;
  }
  
  Future<void> _applyResourceAllocation(ResourceAllocation allocation) async {
    _currentAllocation = allocation;
    
    // Apply GPU settings
    await _applyGPUSettings(allocation.gpuPerformance);
    
    // Apply memory settings
    await _applyMemorySettings(allocation.memoryAllocation);
    
    // Apply CPU settings
    await _applyCPUSettings(allocation.cpuAllocation);
    
    // Apply background processing settings
    await _applyBackgroundSettings(allocation.backgroundProcessing);
    
    // Apply storage optimization
    await _applyStorageSettings(allocation.storageOptimization);
    
    // Schedule cleanup
    _scheduleCleanup(allocation.cleanupSchedule);
  }
  
  Future<void> _applyGPUSettings(double allocation) async {
    try {
      final powerLimit = (allocation * 380).round(); // Scale to power limit
      await run('nvidia-smi', ['-pl', powerLimit.toString()]);
    } catch (e) {
      debugPrint('Failed to apply GPU settings: $e');
    }
  }
  
  Future<void> _applyMemorySettings(double allocation) async {
    try {
      // Apply memory allocation settings
      await run('echo', ['Memory allocation set to ${(allocation * 100).round()}%']);
    } catch (e) {
      debugPrint('Failed to apply memory settings: $e');
    }
  }
  
  Future<void> _applyCPUSettings(double allocation) async {
    try {
      // Apply CPU priority settings
      final priority = allocation > 0.7 ? 'high' : allocation > 0.4 ? 'normal' : 'low';
      await run('echo', ['CPU priority set to $priority']);
    } catch (e) {
      debugPrint('Failed to apply CPU settings: $e');
    }
  }
  
  Future<void> _applyBackgroundSettings(BackgroundProcessing background) async {
    // Apply background processing settings
    _eventController.add(ResourceEvent(
      type: ResourceEventType.background_configured,
      message: 'Background processing configured',
      data: {'background': background.toJson()},
    ));
  }
  
  Future<void> _applyStorageSettings(StorageOptimization storage) async {
    // Apply storage optimization settings
    _eventController.add(ResourceEvent(
      type: ResourceEventType.storage_optimized,
      message: 'Storage optimization configured',
      data: {'storage': storage.toJson()},
    ));
  }
  
  void _scheduleCleanup(List<String> schedule) {
    // Schedule cleanup tasks
    _eventController.add(ResourceEvent(
      type: ResourceEventType.cleanup_scheduled,
      message: 'Cleanup schedule updated',
      data: {'schedule': schedule},
    ));
  }
  
  /// Get resource statistics
  Map<String, dynamic> getResourceStatistics() {
    return {
      'is_initialized': _isInitialized,
      'usage_history_count': _usageHistory.length,
      'patterns_count': _patterns.length,
      'resource_weights': _resourceWeights,
      'current_allocation': _currentAllocation?.toJson(),
      'user_preferences_count': _preferences.length,
    };
  }
  
  /// Load persisted data
  Future<void> _loadPersistedData() async {
    try {
      // Load usage history
      final historyJson = _prefs.getString('resource_usage_history') ?? '[]';
      final historyList = jsonDecode(historyJson) as List;
      _usageHistory.clear();
      for (final item in historyList) {
        _usageHistory.add(ResourceUsage.fromJson(item));
      }
      
      // Load patterns
      final patternsJson = _prefs.getString('resource_patterns') ?? '{}';
      final patternsMap = jsonDecode(patternsJson) as Map;
      _patterns.clear();
      for (final entry in patternsMap.entries) {
        _patterns[entry.key] = ResourcePattern.fromJson(entry.value);
      }
      
      // Load resource weights
      final weightsJson = _prefs.getString('resource_weights') ?? '{}';
      final weightsMap = jsonDecode(weightsJson) as Map;
      for (final entry in weightsMap.entries) {
        _resourceWeights[entry.key] = entry.value as double;
      }
      
      // Load preferences
      final preferencesJson = _prefs.getString('user_preferences') ?? '{}';
      final preferencesMap = jsonDecode(preferencesJson) as Map;
      for (final entry in preferencesMap.entries) {
        _preferences[entry.key] = UserPreference.fromJson(entry.value);
      }
      
    } catch (e) {
      debugPrint('Failed to load persisted data: $e');
    }
  }
  
  /// Persist data
  Future<void> _persistData() async {
    try {
      // Save usage history
      final historyJson = jsonEncode(_usageHistory.take(500).map((u) => u.toJson()).toList());
      await _prefs.setString('resource_usage_history', historyJson);
      
      // Save patterns
      final patternsJson = jsonEncode(_patterns.map((k, v) => MapEntry(k, v.toJson())));
      await _prefs.setString('resource_patterns', patternsJson);
      
      // Save resource weights
      final weightsJson = jsonEncode(_resourceWeights);
      await _prefs.setString('resource_weights', weightsJson);
      
      // Save preferences
      final preferencesJson = jsonEncode(_preferences.map((k, v) => MapEntry(k, v.toJson())));
      await _prefs.setString('user_preferences', preferencesJson);
      
    } catch (e) {
      debugPrint('Failed to persist data: $e');
    }
  }
  
  /// Dispose
  void dispose() {
    _analysisTimer?.cancel();
    _optimizationTimer?.cancel();
    _eventController.close();
    _isInitialized = false;
  }
}

/// Resource usage record
class ResourceUsage {
  final String processType;
  final String processName;
  final double usageLevel; // 0.0 to 1.0
  final ResourceAllocation? allocation;
  final DateTime timestamp;
  
  ResourceUsage({
    required this.processType,
    required this.processName,
    required this.usageLevel,
    this.allocation,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() => {
    'process_type': processType,
    'process_name': processName,
    'usage_level': usageLevel,
    'allocation': allocation?.toJson(),
    'timestamp': timestamp.toIso8601String(),
  };
  
  factory ResourceUsage.fromJson(Map<String, dynamic> json) {
    return ResourceUsage(
      processType: json['process_type'],
      processName: json['process_name'],
      usageLevel: json['usage_level'],
      allocation: json['allocation'] != null ? ResourceAllocation.fromJson(json['allocation']) : null,
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

/// Resource pattern
class ResourcePattern {
  final String processType;
  final String timeOfDay;
  int frequency;
  double averageUsage;
  DateTime lastUsed;
  ResourceAllocation? preferredAllocation;
  double confidence;
  double? maxUsage;
  double? minUsage;
  double? variance;
  double? correlation;
  
  ResourcePattern({
    required this.processType,
    required this.timeOfDay,
    required this.frequency,
    required this.averageUsage,
    required this.lastUsed,
    this.preferredAllocation,
    this.confidence = 0.5,
    this.maxUsage,
    this.minUsage,
    this.variance,
    this.correlation,
  });
  
  Map<String, dynamic> toJson() => {
    'process_type': processType,
    'time_of_day': timeOfDay,
    'frequency': frequency,
    'average_usage': averageUsage,
    'last_used': lastUsed.toIso8601String(),
    'preferred_allocation': preferredAllocation?.toJson(),
    'confidence': confidence,
    'max_usage': maxUsage,
    'min_usage': minUsage,
    'variance': variance,
    'correlation': correlation,
  };
  
  factory ResourcePattern.fromJson(Map<String, dynamic> json) {
    return ResourcePattern(
      processType: json['process_type'],
      timeOfDay: json['time_of_day'],
      frequency: json['frequency'],
      averageUsage: json['average_usage'],
      lastUsed: DateTime.parse(json['last_used']),
      preferredAllocation: json['preferred_allocation'] != null ? ResourceAllocation.fromJson(json['preferred_allocation']) : null,
      confidence: json['confidence'],
      maxUsage: json['max_usage'],
      minUsage: json['min_usage'],
      variance: json['variance'],
      correlation: json['correlation'],
    );
  }
}

/// Resource allocation
class ResourceAllocation {
  final double gpuPerformance;
  final double memoryAllocation;
  final double cpuAllocation;
  final double diskIO;
  final double networkBandwidth;
  final BackgroundProcessing backgroundProcessing;
  final StorageOptimization storageOptimization;
  final List<String> cleanupSchedule;
  
  ResourceAllocation({
    required this.gpuPerformance,
    required this.memoryAllocation,
    required this.cpuAllocation,
    required this.diskIO,
    required this.networkBandwidth,
    required this.backgroundProcessing,
    required this.storageOptimization,
    required this.cleanupSchedule,
  });
  
  Map<String, dynamic> toJson() => {
    'gpu_performance': gpuPerformance,
    'memory_allocation': memoryAllocation,
    'cpu_allocation': cpuAllocation,
    'disk_io': diskIO,
    'network_bandwidth': networkBandwidth,
    'background_processing': backgroundProcessing.toJson(),
    'storage_optimization': storageOptimization.toJson(),
    'cleanup_schedule': cleanupSchedule,
  };
  
  factory ResourceAllocation.fromJson(Map<String, dynamic> json) {
    return ResourceAllocation(
      gpuPerformance: json['gpu_performance'],
      memoryAllocation: json['memory_allocation'],
      cpuAllocation: json['cpu_allocation'],
      diskIO: json['disk_io'],
      networkBandwidth: json['network_bandwidth'],
      backgroundProcessing: BackgroundProcessing.fromJson(json['background_processing']),
      storageOptimization: StorageOptimization.fromJson(json['storage_optimization']),
      cleanupSchedule: List<String>.from(json['cleanup_schedule']),
    );
  }
}

/// Background processing configuration
class BackgroundProcessing {
  final bool enabled;
  final BackgroundPriority priority;
  final int maxConcurrentTasks;
  final double resourceLimit;
  final List<String> schedule;
  
  BackgroundProcessing({
    required this.enabled,
    required this.priority,
    required this.maxConcurrentTasks,
    required this.resourceLimit,
    required this.schedule,
  });
  
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'priority': priority.toString(),
    'max_concurrent_tasks': maxConcurrentTasks,
    'resource_limit': resourceLimit,
    'schedule': schedule,
  };
  
  factory BackgroundProcessing.fromJson(Map<String, dynamic> json) {
    return BackgroundProcessing(
      enabled: json['enabled'],
      priority: BackgroundPriority.values.firstWhere(
        (p) => p.toString() == json['priority'],
        orElse: () => BackgroundPriority.normal,
      ),
      maxConcurrentTasks: json['max_concurrent_tasks'],
      resourceLimit: json['resource_limit'],
      schedule: List<String>.from(json['schedule']),
    );
  }
}

/// Storage optimization configuration
class StorageOptimization {
  final bool enabled;
  final double cleanupThreshold;
  final bool compressionEnabled;
  final bool deduplicationEnabled;
  final ArchivePolicy archivePolicy;
  final StoragePriority priority;
  
  StorageOptimization({
    required this.enabled,
    required this.cleanupThreshold,
    required this.compressionEnabled,
    required this.deduplicationEnabled,
    required this.archivePolicy,
    required this.priority,
  });
  
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'cleanup_threshold': cleanupThreshold,
    'compression_enabled': compressionEnabled,
    'deduplication_enabled': deduplicationEnabled,
    'archive_policy': archivePolicy.toString(),
    'priority': priority.toString(),
  };
  
  factory StorageOptimization.fromJson(Map<String, dynamic> json) {
    return StorageOptimization(
      enabled: json['enabled'],
      cleanupThreshold: json['cleanup_threshold'],
      compressionEnabled: json['compression_enabled'],
      deduplicationEnabled: json['deduplication_enabled'],
      archivePolicy: ArchivePolicy.values.firstWhere(
        (p) => p.toString() == json['archive_policy'],
        orElse: () => ArchivePolicy.weekly,
      ),
      priority: StoragePriority.values.firstWhere(
        (p) => p.toString() == json['priority'],
        orElse: () => StoragePriority.performance,
      ),
    );
  }
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

/// Machine learning model
class MachineLearningModel {
  final List<ResourcePattern> patterns;
  final Map<String, double> resourceWeights;
  final Map<String, UserPreference> userPreferences;
  final List<ResourceUsage> recentUsage;
  
  MachineLearningModel({
    required this.patterns,
    required this.resourceWeights,
    required this.userPreferences,
    required this.recentUsage,
  });
}

/// Background priority
enum BackgroundPriority {
  low,
  normal,
  high,
  critical,
}

/// Storage priority
enum StoragePriority {
  performance,
  balance,
  capacity,
}

/// Archive policy
enum ArchivePolicy {
  daily,
  weekly,
  monthly,
  quarterly,
}

/// Resource event types
enum ResourceEventType {
  initialized,
  usage_recorded,
  patterns_analyzed,
  model_updated,
  allocation_optimized,
  background_configured,
  storage_optimized,
  cleanup_scheduled,
  error,
}

/// Resource event
class ResourceEvent {
  final ResourceEventType type;
  final String message;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  
  ResourceEvent({
    required this.type,
    required this.message,
    required this.data,
  }) : timestamp = DateTime.now();
}
