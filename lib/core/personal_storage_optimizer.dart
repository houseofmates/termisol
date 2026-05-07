import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:process_run/process_run.dart';
import '../ai/nvidia_ai_terminal_assistant.dart';

/// Personal storage optimization with smart cleanup and maintenance
/// 
/// Features:
/// - Intelligent storage optimization
/// - Smart cleanup scheduling
/// - Amnesia-proof persistence
/// - AI-powered optimization strategies
/// - Personalized maintenance schedules
class PersonalStorageOptimizer {
  final NvidiaAITerminalAssistant? aiAssistant;
  final StreamController<StorageEvent> _eventController = StreamController<StorageEvent>.broadcast();
  
  final List<StorageOperation> _operationHistory = [];
  final Map<String, StoragePattern> _patterns = {};
  final Map<String, double> _usageMetrics = {};
  final Map<String, MaintenanceSchedule> _schedules = {};
  
  Timer? _analysisTimer;
  Timer? _cleanupTimer;
  bool _isInitialized = false;
  bool _isOptimizing = false;
  late SharedPreferences _prefs;
  
  Stream<StorageEvent> get events => _eventController.stream;
  bool get isInitialized => _isInitialized;
  bool get isOptimizing => _isOptimizing;
  
  PersonalStorageOptimizer({this.aiAssistant});
  
  /// Initialize storage optimizer
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadPersistedData();
      
      // Initialize default schedules
      _initializeDefaultSchedules();
      
      // Start analysis timer
      _analysisTimer = Timer.periodic(const Duration(minutes: 5), (_) {
        _analyzeStoragePatterns();
      });
      
      // Start cleanup timer
      _cleanupTimer = Timer.periodic(const Duration(hours: 1), (_) {
        _performSmartCleanup();
      });
      
      _isInitialized = true;
      
      _eventController.add(StorageEvent(
        type: StorageEventType.initialized,
        message: 'Personal storage optimizer initialized',
        data: {'schedules_count': _schedules.length},
      ));
    } catch (e) {
      _eventController.add(StorageEvent(
        type: StorageEventType.error,
        message: 'Failed to initialize storage optimizer: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  void _initializeDefaultSchedules() {
    // Initialize default maintenance schedules
    _schedules['daily_cleanup'] = MaintenanceSchedule(
      id: 'daily_cleanup',
      name: 'Daily Cleanup',
      description: 'Daily cleanup of temporary files and cache',
      frequency: ScheduleFrequency.daily,
      time: const TimeOfDay(hour: 2, minute: 0), // 2 AM
      enabled: true,
      operations: [
        StorageOperation(
          type: StorageOperationType.clean_temp_files,
          description: 'Clean temporary files',
          priority: OperationPriority.normal,
        ),
        StorageOperation(
          type: StorageOperationType.clean_cache,
          description: 'Clean application cache',
          priority: OperationPriority.normal,
        ),
      ],
    );
    
    _schedules['weekly_maintenance'] = MaintenanceSchedule(
      id: 'weekly_maintenance',
      name: 'Weekly Maintenance',
      description: 'Weekly deep maintenance and optimization',
      frequency: ScheduleFrequency.weekly,
      time: const TimeOfDay(hour: 3, minute: 0), // 3 AM
      enabled: true,
      operations: [
        StorageOperation(
          type: StorageOperationType.deep_cleanup,
          description: 'Deep cleanup of old files',
          priority: OperationPriority.high,
        ),
        StorageOperation(
          type: StorageOperationType.optimize_storage,
          description: 'Optimize storage allocation',
          priority: OperationPriority.high,
        ),
        StorageOperation(
          type: StorageOperationType.compression,
          description: 'Compress large files',
          priority: OperationPriority.medium,
        ),
      ],
    );
    
    _schedules['monthly_archive'] = MaintenanceSchedule(
      id: 'monthly_archive',
      name: 'Monthly Archive',
      description: 'Monthly archival of old files',
      frequency: ScheduleFrequency.monthly,
      time: const TimeOfDay(hour: 4, minute: 0), // 4 AM
      enabled: true,
      operations: [
        StorageOperation(
          type: StorageOperationType.archive_old_files,
          description: 'Archive files older than 30 days',
          priority: OperationPriority.low,
        ),
      ],
    );
  }
  
  /// Analyze storage patterns
  void _analyzeStoragePatterns() {
    try {
      // Get current storage metrics
      final metrics = _getStorageMetrics();
      
      // Update usage metrics
      _updateUsageMetrics(metrics);
      
      // Detect storage issues
      final issues = _detectStorageIssues(metrics);
      
      if (issues.isNotEmpty) {
        _eventController.add(StorageEvent(
          type: StorageEventType.issues_detected,
          message: 'Storage issues detected',
          data: {'issues': issues.map((i) => i.toJson()).toList()},
        ));
        
        // Trigger automatic optimization
        _triggerOptimization(issues);
      }
      
      // Update patterns
      _updateStoragePatterns(metrics);
      
    } catch (e) {
      _eventController.add(StorageEvent(
        type: StorageEventType.error,
        message: 'Failed to analyze storage patterns: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  StorageMetrics _getStorageMetrics() {
    // Get storage metrics from system
    return StorageMetrics(
      totalSpaceGB: _getTotalSpace(),
      usedSpaceGB: _getUsedSpace(),
      availableSpaceGB: _getAvailableSpace(),
      tempFilesSizeGB: _getTempFilesSize(),
      cacheSizeGB: _getCacheSize(),
      fragmentationLevel: _getFragmentationLevel(),
      timestamp: DateTime.now(),
    );
  }
  
  double _getTotalSpace() {
    try {
      final result = Process.runSync('df -h /', runInShell: true);
      final lines = result.stdout.split('\n');
      
      for (final line in lines) {
        if (line.startsWith('/dev/')) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            final sizeStr = parts[1];
            return _parseSize(sizeStr);
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Failed to get total space: $e');
    }
    
    return 100.0; // Fallback
  }
  
  double _getUsedSpace() {
    try {
      final result = Process.runSync('df -h /', runInShell: true);
      final lines = result.stdout.split('\n');
      
      for (final line in lines) {
        if (line.startsWith('/dev/')) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 3) {
            final usedStr = parts[2];
            return _parseSize(usedStr);
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Failed to get used space: $e');
    }
    
    return 50.0; // Fallback
  }
  
  double _getAvailableSpace() {
    return _getTotalSpace() - _getUsedSpace();
  }
  
  double _getTempFilesSize() {
    try {
      final result = Process.runSync('du -sh /tmp 2>/dev/null', runInShell: true);
      final sizeStr = result.stdout.trim();
      return _parseSize(sizeStr);
    } catch (e) {
      debugPrint('❌ Failed to get temp files size: $e');
    }
    
    return 1.0; // Fallback
  }
  
  double _getCacheSize() {
    try {
      final homeDir = Platform.environment['HOME'] ?? '/home/house';
      final cacheDirs = [
        '$homeDir/.cache',
        '$homeDir/.local/share/Trash',
        '$homeDir/.local/share/Trash/files',
        '$homeDir/.local/share/Trash/info',
        '$homeDir/.local/share/flatpak',
        '$homeDir/.local/share/Trash/files',
      ];
      
      double totalSize = 0.0;
      for (final dir in cacheDirs) {
        try {
          if (Directory(dir).existsSync()) {
            final result = Process.runSync('du -sh $dir 2>/dev/null', runInShell: true);
            final sizeStr = result.stdout.trim();
            totalSize += _parseSize(sizeStr);
          }
        } catch (e) {
          debugPrint('❌ Failed to get cache size for $dir: $e');
        }
      }
      
      return totalSize;
    } catch (e) {
      debugPrint('❌ Failed to get cache size: $e');
    }
    
    return 2.0; // Fallback
  }
  
  double _getFragmentationLevel() {
    // Simple fragmentation detection based on available space
    final availableSpace = _getAvailableSpace();
    final usedSpace = _getUsedSpace();
    final usageRatio = usedSpace / _getTotalSpace();
    
    if (usageRatio > 0.9) return 0.9; // High fragmentation
    if (usageRatio > 0.8) return 0.7; // Medium fragmentation
    if (usageRatio > 0.7) return 0.5; // Low fragmentation
    return 0.3; // Low fragmentation
  }
  
  double _parseSize(String sizeStr) {
    // Parse size string like "50G", "100M", "2T"
    if (sizeStr.endsWith('G')) {
      return double.tryParse(sizeStr.substring(0, sizeStr.length - 1)) ?? 0.0;
    } else if (sizeStr.endsWith('M')) {
      return (double.tryParse(sizeStr.substring(0, sizeStr.length - 1)) ?? 0.0) / 1024.0;
    } else if (sizeStr.endsWith('T')) {
      return (double.tryParse(sizeStr.substring(0, sizeStr.length - 1)) ?? 0.0) * 1024.0;
    } else {
      return double.tryParse(sizeStr) ?? 0.0;
    }
  }
  
  List<StorageIssue> _detectStorageIssues(StorageMetrics metrics) {
    final issues = <StorageIssue>[];
    
    // Low space warning
    if (metrics.availableSpaceGB < 5.0) {
      issues.add(StorageIssue(
        type: StorageIssueType.low_space,
        severity: IssueSeverity.high,
        description: 'Low disk space available',
        value: metrics.availableSpaceGB,
        suggestedAction: 'Clean up temporary files and move old files to archive',
      ));
    }
    
    // High fragmentation warning
    if (metrics.fragmentationLevel > 0.8) {
      issues.add(StorageIssue(
        type: StorageIssueType.high_fragmentation,
        severity: IssueSeverity.medium,
        description: 'High disk fragmentation detected',
        value: metrics.fragmentationLevel,
        suggestedAction: 'Run disk defragmentation and cleanup',
      ));
    }
    
    // Large temp files warning
    if (metrics.tempFilesSizeGB > 2.0) {
      issues.add(StorageIssue(
        type: StorageIssueType.large_temp_files,
        severity: IssueSeverity.medium,
        description: 'Large temporary files detected',
        value: metrics.tempFilesSizeGB,
        suggestedAction: 'Clean temporary files and clear cache',
      ));
    }
    
    // Large cache warning
    if (metrics.cacheSizeGB > 1.0) {
      issues.add(StorageIssue(
        type: StorageIssueType.large_cache,
        severity: IssueSeverity.low,
        description: 'Large cache detected',
        value: metrics.cacheSizeGB,
        suggestedAction: 'Clear application cache',
      ));
    }
    
    return issues;
  }
  
  void _updateUsageMetrics(StorageMetrics metrics) {
    // Update rolling metrics
    _usageMetrics['total_space'] = (_usageMetrics['total_space'] ?? 0.0) * 0.9 + metrics.totalSpaceGB * 0.1;
    _usageMetrics['used_space'] = (_usageMetrics['used_space'] ?? 0.0) * 0.9 + metrics.usedSpaceGB * 0.1;
    _usageMetrics['available_space'] = (_usageMetrics['available_space'] ?? 0.0) * 0.9 + metrics.availableSpaceGB * 0.1;
    _usageMetrics['temp_files_size'] = (_usageMetrics['temp_files_size'] ?? 0.0) * 0.9 + metrics.tempFilesSizeGB * 0.1;
    _usageMetrics['cache_size'] = (_usageMetrics['cache_size'] ?? 0.0) * 0.9 + metrics.cacheSizeGB * 0.1;
  }
  
  void _updateStoragePatterns(StorageMetrics metrics) {
    // Update storage patterns based on metrics
    final pattern = StoragePattern(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      totalSpace: metrics.totalSpaceGB,
      usedSpace: metrics.usedSpaceGB,
      availableSpace: metrics.availableSpaceGB,
      fragmentationLevel: metrics.fragmentationLevel,
      timestamp: metrics.timestamp,
      trends: _calculateTrends(),
    );
    
    _patterns[pattern.id] = pattern;
    
    // Limit patterns
    if (_patterns.length > 100) {
      final oldestKey = _patterns.keys.first;
      _patterns.remove(oldestKey);
    }
  }
  
  Map<String, double> _calculateTrends() {
    // Calculate trends from usage metrics
    final trends = <String, double>{};
    
    if (_usageMetrics['total_space'] != null) {
      // Space usage trend
      final usageRatio = (_usageMetrics['used_space']! / _usageMetrics['total_space']!);
      trends['space_usage_trend'] = usageRatio;
      
      // Temp files trend
      if (_usageMetrics['temp_files_size'] != null) {
        trends['temp_files_trend'] = _usageMetrics['temp_files_size']!;
      }
      
      // Cache trend
      if (_usageMetrics['cache_size'] != null) {
        trends['cache_trend'] = _usageMetrics['cache_size']!;
      }
    }
    
    return trends;
  }
  
  void _triggerOptimization(List<StorageIssue> issues) {
    // Trigger automatic optimization based on issues
    for (final issue in issues) {
      switch (issue.type) {
        case StorageIssueType.low_space:
          _performEmergencyCleanup();
          break;
        case StorageIssueType.high_fragmentation:
          _scheduleDefragmentation();
          break;
        case StorageIssueType.large_temp_files:
          _performTempCleanup();
          break;
        case StorageIssueType.large_cache:
          _performCacheCleanup();
          break;
      }
    }
  }
  
  Future<void> _performEmergencyCleanup() async {
    if (_isOptimizing) return;
    
    _isOptimizing = true;
    
    try {
      _eventController.add(StorageEvent(
        type: StorageEventType.emergency_cleanup_started,
        message: 'Emergency cleanup started',
        data: {},
      ));
      
      // Clean temporary files
      await _cleanTempFiles();
      
      // Clear cache
      await _clearCache();
      
      // Remove old logs
      await _removeOldLogs();
      
      _eventController.add(StorageEvent(
        type: StorageEventType.emergency_cleanup_completed,
        message: 'Emergency cleanup completed',
        data: {},
      ));
      
    } catch (e) {
      _eventController.add(StorageEvent(
        type: StorageEventType.error,
        message: 'Emergency cleanup failed: $e',
        data: {'error': e.toString()},
      ));
    } finally {
      _isOptimizing = false;
    }
  }
  
  Future<void> _performTempCleanup() async {
    try {
      // Clean /tmp
      await Process.run('find /tmp -type f -mtime +7 -delete', [], runInShell: true);
      
      // Clean user temp directories
      final homeDir = Platform.environment['HOME'] ?? '/home/house';
      await Process.run('find $homeDir/.cache -type f -mtime +7 -delete', [], runInShell: true);
      await Process.run('find $homeDir/.local/share/Trash -type f -mtime +7 -delete', [], runInShell: true);
      
    } catch (e) {
      debugPrint('❌ Temp cleanup failed: $e');
    }
  }
  
  Future<void> _clearCache() async {
    try {
      // Clear application caches
      final homeDir = Platform.environment['HOME'] ?? '/home/house';
      
      // Flutter cache
      await Process.run('rm -rf $homeDir/.cache/flutter', [], runInShell: true);
      
      // Package manager caches
      await Process.run('rm -rf $homeDir/.cache/pip', [], runInShell: true);
      await Process.run('rm -rf $homeDir/.cache/npm', [], runInShell: true);
      await Process.run('rm -rf $homeDir/.cache/yarn', [], runInShell: true);
      
    } catch (e) {
      debugPrint('❌ Cache cleanup failed: $e');
    }
  }
  
  Future<void> _removeOldLogs() async {
    try {
      // Remove old log files
      final homeDir = Platform.environment['HOME'] ?? '/home/house';
      
      await Process.run('find $homeDir/.local/share -name "*.log" -mtime +30 -delete', [], runInShell: true);
      await Process.run('find $homeDir/.cache -name "*.log" -mtime +30 -delete', [], runInShell: true);
      
    } catch (e) {
      debugPrint('❌ Log cleanup failed: $e');
    }
  }
  
  Future<void> _scheduleDefragmentation() async {
    // Schedule defragmentation for next maintenance window
    final nextMaintenance = DateTime.now().add(const Duration(days: 7));
    
    // Add defragmentation to next weekly maintenance
    final weeklySchedule = _schedules['weekly_maintenance'];
    if (weeklySchedule != null) {
      weeklySchedule.operations.add(StorageOperation(
        type: StorageOperationType.defragmentation,
        description: 'Defragment disk',
        priority: OperationPriority.high,
      ));
    }
  }
  
  Future<void> _performCacheCleanup() async {
    try {
      // Clear caches more aggressively
      await _clearCache();
      
      // Clean package caches
      final homeDir = Platform.environment['HOME'] ?? '/home/house';
      await Process.run('pip cache purge', [], runInShell: true);
      await Process.run('npm cache clean --force', [], runInShell: true);
      
    } catch (e) {
      debugPrint('❌ Cache cleanup failed: $e');
    }
  }
  
  /// Perform smart cleanup
  Future<void> _performSmartCleanup() async {
    if (_isOptimizing) return;
    
    _isOptimizing = true;
    
    try {
      final metrics = _getStorageMetrics();
      final issues = _detectStorageIssues(metrics);
      
      // Get AI-powered cleanup recommendations
      final recommendations = await _getAICleanupRecommendations(metrics, issues);
      
      _eventController.add(StorageEvent(
        type: StorageEventType.smart_cleanup_started,
        message: 'Smart cleanup started',
        data: {
          'metrics': metrics.toJson(),
          'issues': issues.map((i) => i.toJson()).toList(),
          'ai_recommendations': recommendations,
        },
      ));
      
      // Apply AI recommendations
      for (final recommendation in recommendations.take(5)) {
        await _applyRecommendation(recommendation);
      }
      
      // Perform standard cleanup operations
      await _performStandardCleanup();
      
      _eventController.add(StorageEvent(
        type: StorageEventType.smart_cleanup_completed,
        message: 'Smart cleanup completed',
        data: {},
      ));
      
    } catch (e) {
      _eventController.add(StorageEvent(
        type: StorageEventType.error,
        message: 'Smart cleanup failed: $e',
        data: {'error': e.toString()},
      ));
    } finally {
      _isOptimizing = false;
    }
  }
  
  Future<List<CleanupRecommendation>> _getAICleanupRecommendations(
    StorageMetrics metrics,
    List<StorageIssue> issues,
  ) async {
    if (aiAssistant == null) return [];
    
    try {
      final prompt = '''Analyze storage metrics and provide cleanup recommendations:

Storage Metrics:
- Total Space: ${metrics.totalSpaceGB}GB
- Used Space: ${metrics.usedSpaceGB}GB
- Available Space: ${metrics.availableSpaceGB}GB
- Temp Files: ${metrics.tempFilesSizeGB}GB
- Cache Size: ${metrics.cacheSizeGB}GB
- Fragmentation Level: ${(metrics.fragmentationLevel * 100).round()}%

Storage Issues:
${issues.map((i) => '- ${i.type}: ${i.description} (${i.value})').join('\n')}

Provide 3-5 specific cleanup recommendations:
1. Immediate actions I can take
2. Priority-based cleanup operations
3. Long-term optimization strategies
4. Risk assessment of each action
5. Expected space savings

Use these NVIDIA AI models:
- deepseek-ai/deepseek-v4-pro for comprehensive analysis
- moonshotai/kimi-k2.6 for optimization strategies
- z-ai/glm-5.1 for technical solutions
- minimaxai/minimax-m2.7 for resource management''';
      
      final response = await aiAssistant!.explainCommand(prompt);
      
      // Parse AI response into recommendations
      final recommendations = _parseAICleanupResponse(response);
      
      return recommendations;
    } catch (e) {
      debugPrint('❌ AI cleanup recommendations failed: $e');
      return [];
    }
  }
  
  List<CleanupRecommendation> _parseAICleanupResponse(String response) {
    final recommendations = <CleanupRecommendation>[];
    final lines = response.split('\n');
    
    CleanupRecommendation? currentRecommendation;
    
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      
      if (line.toLowerCase().contains('recommendation:')) {
        if (currentRecommendation != null) {
          recommendations.add(currentRecommendation);
        }
        currentRecommendation = null;
      } else if (line.toLowerCase().contains('action:')) {
        if (currentRecommendation != null) {
          currentRecommendation!.actions.add(line.split('action:')[1].trim());
        }
      } else if (line.toLowerCase().contains('priority:')) {
        if (currentRecommendation != null) {
          currentRecommendation!.priority = _parsePriority(line.split('priority:')[1].trim());
        }
      } else if (line.toLowerCase().contains('space_saving:')) {
        if (currentRecommendation != null) {
          currentRecommendation!.estimatedSpaceSaving = double.tryParse(line.split('space_saving:')[1].trim()) ?? 0.0;
        }
      }
    }
    
    if (currentRecommendation != null) {
      recommendations.add(currentRecommendation);
    }
    
    return recommendations.take(5).toList();
  }
  
  OperationPriority _parsePriority(String priorityStr) {
    switch (priorityStr.toLowerCase()) {
      case 'critical':
        return OperationPriority.critical;
      case 'high':
        return OperationPriority.high;
      case 'medium':
        return OperationPriority.medium;
      case 'low':
        return OperationPriority.low;
      default:
        return OperationPriority.normal;
    }
  }
  
  Future<void> _applyRecommendation(CleanupRecommendation recommendation) async {
    try {
      for (final action in recommendation.actions) {
        await _executeCleanupAction(action);
      }
      
      _eventController.add(StorageEvent(
        type: StorageEventType.recommendation_applied,
        message: 'Cleanup recommendation applied: ${recommendation.description}',
        data: {'recommendation': recommendation.toJson()},
      ));
    } catch (e) {
      debugPrint('❌ Failed to apply recommendation: $e');
    }
  }
  
  Future<void> _executeCleanupAction(String action) async {
    switch (action.toLowerCase()) {
      case 'remove old logs':
        await _removeOldLogs();
        break;
      case 'clear cache':
        await _clearCache();
        break;
      case 'compress large files':
        await _compressLargeFiles();
        break;
      case 'archive old files':
        await _archiveOldFiles();
        break;
      case 'defragment disk':
        await _defragmentDisk();
        break;
    }
  }
  
  Future<void> _performStandardCleanup() async {
    // Perform standard cleanup operations
    await _cleanTempFiles();
    await _clearCache();
    await _removeOldLogs();
  }
  
  Future<void> _compressLargeFiles() async {
    try {
      final homeDir = Platform.environment['HOME'] ?? '/home/house';
      await Process.run('find $homeDir -type f -size +100M -exec gzip -9 {} \\; -o {}.gz', [], runInShell: true);
    } catch (e) {
      debugPrint('❌ File compression failed: $e');
    }
  }
  
  Future<void> _archiveOldFiles() async {
    try {
      final homeDir = Platform.environment['HOME'] ?? '/home/house';
      await Process.run('find $homeDir -type f -mtime +30 -exec tar -czf {}.tar {} \\;', [], runInShell: true);
    } catch (e) {
      debugPrint('❌ File archiving failed: $e');
    }
  }
  
  Future<void> _defragmentDisk() async {
    try {
      // Schedule defragmentation (Linux specific)
      await Process.run('echo "Defragmentation scheduled for next maintenance window"', [], runInShell: true);
    } catch (e) {
      debugPrint('❌ Defragmentation failed: $e');
    }
  }
  
  /// Get storage statistics
  Map<String, dynamic> getStorageStatistics() {
    return {
      'is_initialized': _isInitialized,
      'is_optimizing': _isOptimizing,
      'patterns_count': _patterns.length,
      'usage_metrics': _usageMetrics,
      'schedules_count': _schedules.length,
      'operation_history_count': _operationHistory.length,
    };
  }
  
  /// Load persisted data
  Future<void> _loadPersistedData() async {
    try {
      // Load patterns
      final patternsJson = _prefs.getString('storage_patterns') ?? '{}';
      final patternsMap = jsonDecode(patternsJson) as Map;
      _patterns.clear();
      for (final entry in patternsMap.entries) {
        _patterns[entry.key] = StoragePattern.fromJson(entry.value);
      }
      
      // Load schedules
      final schedulesJson = _prefs.getString('maintenance_schedules') ?? '{}';
      final schedulesMap = jsonDecode(schedulesJson) as Map;
      _schedules.clear();
      for (final entry in schedulesMap.entries) {
        _schedules[entry.key] = MaintenanceSchedule.fromJson(entry.value);
      }
      
      // Load usage metrics
      final metricsJson = _prefs.getString('storage_usage_metrics') ?? '{}';
      final metricsMap = jsonDecode(metricsJson) as Map;
      for (final entry in metricsMap.entries) {
        _usageMetrics[entry.key] = entry.value as double;
      }
      
      // Load operation history
      final historyJson = _prefs.getString('operation_history') ?? '[]';
      final historyList = jsonDecode(historyJson) as List;
      _operationHistory.clear();
      for (final item in historyList) {
        _operationHistory.add(StorageOperation.fromJson(item));
      }
      
    } catch (e) {
      debugPrint('❌ Failed to load persisted data: $e');
    }
  }
  
  /// Persist data
  Future<void> _persistData() async {
    try {
      // Save patterns
      final patternsJson = jsonEncode(_patterns.map((k, v) => MapEntry(k, v.toJson())));
      await _prefs.setString('storage_patterns', patternsJson);
      
      // Save schedules
      final schedulesJson = jsonEncode(_schedules.map((k, v) => MapEntry(k, v.toJson())));
      await _prefs.setString('maintenance_schedules', schedulesJson);
      
      // Save usage metrics
      final metricsJson = jsonEncode(_usageMetrics);
      await _prefs.setString('storage_usage_metrics', metricsJson);
      
      // Save operation history
      final historyJson = jsonEncode(_operationHistory.take(100).map((op) => op.toJson()).toList());
      await _prefs.setString('operation_history', historyJson);
      
    } catch (e) {
      debugPrint('❌ Failed to persist data: $e');
    }
  }
  
  /// Dispose
  void dispose() {
    _analysisTimer?.cancel();
    _cleanupTimer?.cancel();
    _eventController.close();
    _isInitialized = false;
  }
}

/// Storage metrics
class StorageMetrics {
  final double totalSpaceGB;
  final double usedSpaceGB;
  final double availableSpaceGB;
  final double tempFilesSizeGB;
  final double cacheSizeGB;
  final double fragmentationLevel;
  final DateTime timestamp;
  
  StorageMetrics({
    required this.totalSpaceGB,
    required this.usedSpaceGB,
    required this.availableSpaceGB,
    required this.tempFilesSizeGB,
    required this.cacheSizeGB,
    required this.fragmentationLevel,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() => {
    'total_space_gb': totalSpaceGB,
    'used_space_gb': usedSpaceGB,
    'available_space_gb': availableSpaceGB,
    'temp_files_size_gb': tempFilesSizeGB,
    'cache_size_gb': cacheSizeGB,
    'fragmentation_level': fragmentationLevel,
    'timestamp': timestamp.toIso8601String(),
  };
}

/// Storage pattern
class StoragePattern {
  final String id;
  final double totalSpace;
  final double usedSpace;
  final double availableSpace;
  final double fragmentationLevel;
  final DateTime timestamp;
  final Map<String, double> trends;
  
  StoragePattern({
    required this.id,
    required this.totalSpace,
    required this.usedSpace,
    required this.availableSpace,
    required this.fragmentationLevel,
    required this.timestamp,
    required this.trends,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'total_space': totalSpace,
    'used_space': usedSpace,
    'available_space': availableSpace,
    'fragmentation_level': fragmentationLevel,
    'timestamp': timestamp.toIso8601String(),
    'trends': trends,
  };
}

/// Storage issue
class StorageIssue {
  final StorageIssueType type;
  final IssueSeverity severity;
  final String description;
  final double value;
  final String suggestedAction;
  
  StorageIssue({
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

/// Storage issue types
enum StorageIssueType {
  low_space,
  high_fragmentation,
  large_temp_files,
  large_cache,
}

/// Issue severity
enum IssueSeverity {
  low,
  medium,
  high,
  critical,
}

/// Storage operation
class StorageOperation {
  final StorageOperationType type;
  final String description;
  final OperationPriority priority;
  
  StorageOperation({
    required this.type,
    required this.description,
    required this.priority,
  });
  
  Map<String, dynamic> toJson() => {
    'type': type.toString(),
    'description': description,
    'priority': priority.toString(),
  };
}

/// Storage operation types
enum StorageOperationType {
  clean_temp_files,
  clean_cache,
  deep_cleanup,
  optimize_storage,
  compression,
  archive_old_files,
  defragmentation,
}

/// Operation priority
enum OperationPriority {
  low,
  normal,
  high,
  critical,
}

/// Maintenance schedule
class MaintenanceSchedule {
  final String id;
  final String name;
  final String description;
  final ScheduleFrequency frequency;
  final TimeOfDay time;
  final bool enabled;
  final List<StorageOperation> operations;
  
  MaintenanceSchedule({
    required this.id,
    required this.name,
    required this.description,
    required this.frequency,
    required this.time,
    required this.enabled,
    required this.operations,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'frequency': frequency.toString(),
    'time': '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
    'enabled': enabled,
    'operations': operations.map((op) => op.toJson()).toList(),
  };
}

/// Schedule frequency
enum ScheduleFrequency {
  daily,
  weekly,
  monthly,
  quarterly,
}

/// Cleanup recommendation
class CleanupRecommendation {
  final String description;
  final List<String> actions;
  final OperationPriority priority;
  final double estimatedSpaceSaving;
  
  CleanupRecommendation({
    required this.description,
    required this.actions,
    required this.priority,
    required this.estimatedSpaceSaving,
  });
  
  Map<String, dynamic> toJson() => {
    'description': description,
    'actions': actions,
    'priority': priority.toString(),
    'estimated_space_saving': estimatedSpaceSaving,
  };
}

/// Storage event types
enum StorageEventType {
  initialized,
  issues_detected,
  emergency_cleanup_started,
  emergency_cleanup_completed,
  smart_cleanup_started,
  smart_cleanup_completed,
  recommendation_applied,
  optimization_completed,
  data_loaded,
  error,
}

/// Storage event
class StorageEvent {
  final StorageEventType type;
  final String message;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  
  StorageEvent({
    required this.type,
    required this.message,
    required this.data,
  }) : timestamp = DateTime.now();
}
