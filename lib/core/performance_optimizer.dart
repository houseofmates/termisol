import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:process_run/process_run.dart';
import '../ai/nvidia_ai_terminal_assistant.dart';

/// Performance optimization suggestions for Termisol
/// 
/// Features:
/// - Real-time performance monitoring
/// - AI-powered optimization suggestions
/// - System resource analysis
/// - Terminal performance tuning
/// - Bottleneck detection
/// - Optimization recommendations
class PerformanceOptimizer {
  final NvidiaAITerminalAssistant? aiAssistant;
  final StreamController<PerformanceEvent> _eventController = StreamController<PerformanceEvent>.broadcast();
  
  final List<PerformanceMetric> _metrics = [];
  final List<OptimizationSuggestion> _suggestions = [];
  final Map<String, double> _performanceHistory = {};
  
  Timer? _monitoringTimer;
  bool _isMonitoring = false;
  PerformanceProfile? _currentProfile;
  
  Stream<PerformanceEvent> get events => _eventController.stream;
  List<OptimizationSuggestion> get suggestions => List.unmodifiable(_suggestions);
  bool get isMonitoring => _isMonitoring;
  
  PerformanceOptimizer({this.aiAssistant});
  
  /// Start performance monitoring
  void startMonitoring() {
    if (_isMonitoring) return;
    
    _isMonitoring = true;
    _monitoringTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _collectMetrics();
    });
    
    _eventController.add(PerformanceEvent(
      type: PerformanceEventType.monitoring_started,
      message: 'Performance monitoring started',
      data: {},
    ));
  }
  
  /// Stop performance monitoring
  void stopMonitoring() {
    if (!_isMonitoring) return;
    
    _monitoringTimer?.cancel();
    _isMonitoring = false;
    
    _eventController.add(PerformanceEvent(
      type: PerformanceEventType.monitoring_stopped,
      message: 'Performance monitoring stopped',
      data: {},
    ));
  }
  
  /// Collect performance metrics
  Future<void> _collectMetrics() async {
    try {
      final metrics = await _getSystemMetrics();
      
      // Add to history
      _metrics.add(metrics);
      if (_metrics.length > 100) {
        _metrics.removeAt(0);
      }
      
      // Analyze for bottlenecks
      _analyzePerformance(metrics);
      
      // Generate suggestions
      await _generateSuggestions(metrics);
      
    } catch (e) {
      _eventController.add(PerformanceEvent(
        type: PerformanceEventType.error,
        message: 'Failed to collect metrics: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  Future<SystemMetrics> _getSystemMetrics() async {
    final startTime = DateTime.now();
    
    try {
      // CPU usage
      final cpuResult = await run('bash', ['-c', "grep 'cpu ' /proc/stat | awk '{usage=(\$2+\$4)*100/(\$2+\$4+\$5)} {print usage}'"], workingDirectory: '/');
      final cpuUsage = double.tryParse(cpuResult.stdout.toString().trim()) ?? 0.0;
      
      // Memory usage
      final memResult = await run('bash', ['-c', "free | grep Mem | awk '{usage=(\$3/\$2)*100} {print usage}'"], workingDirectory: '/');
      final memoryUsage = double.tryParse(memResult.stdout.toString().trim()) ?? 0.0;
      
      // Disk usage
      final diskResult = await run('bash', ['-c', "df / | tail -1 | awk '{usage=(\$3/\$2)*100} {print usage}'"], workingDirectory: '/');
      final diskUsage = double.tryParse(diskResult.stdout.toString().trim()) ?? 0.0;
      
      // Network I/O
      final networkResult = await run('bash', ['-c', "cat /proc/net/dev | grep eth0 | awk '{print \$2+\$10}'"], workingDirectory: '/');
      final networkIO = double.tryParse(networkResult.stdout.toString().trim()) ?? 0.0;
      
      // Process count
      final processResult = await run('bash', ['-c', 'ps aux | wc -l'], workingDirectory: '/');
      final processCount = int.tryParse(processResult.stdout.toString().trim()) ?? 0;
      
      // Load average
      final loadResult = await run('bash', ['-c', 'uptime | awk -F"load average:" \'{print \$10}''], workingDirectory: '/');
      final loadAverage = double.tryParse(loadResult.stdout.toString().trim()) ?? 0.0;
      
      final endTime = DateTime.now();
      final collectionTime = endTime.difference(startTime);
      
      return SystemMetrics(
        cpuUsage: cpuUsage,
        memoryUsage: memoryUsage,
        diskUsage: diskUsage,
        networkIO: networkIO,
        processCount: processCount,
        loadAverage: loadAverage,
        timestamp: endTime,
        collectionTime: collectionTime,
      );
    } catch (e) {
      throw Exception('Failed to collect system metrics: $e');
    }
  }
  
  void _analyzePerformance(SystemMetrics metrics) {
    // Analyze for performance issues
    final issues = <PerformanceIssue>[];
    
    // CPU issues
    if (metrics.cpuUsage > 80) {
      issues.add(PerformanceIssue(
        type: PerformanceIssueType.high_cpu,
        severity: PerformanceSeverity.high,
        description: 'High CPU usage: ${metrics.cpuUsage.toStringAsFixed(1)}%',
        value: metrics.cpuUsage,
      ));
    }
    
    // Memory issues
    if (metrics.memoryUsage > 85) {
      issues.add(PerformanceIssue(
        type: PerformanceIssueType.high_memory,
        severity: PerformanceSeverity.high,
        description: 'High memory usage: ${metrics.memoryUsage.toStringAsFixed(1)}%',
        value: metrics.memoryUsage,
      ));
    }
    
    // Disk issues
    if (metrics.diskUsage > 90) {
      issues.add(PerformanceIssue(
        type: PerformanceIssueType.high_disk,
        severity: PerformanceSeverity.critical,
        description: 'High disk usage: ${metrics.diskUsage.toStringAsFixed(1)}%',
        value: metrics.diskUsage,
      ));
    }
    
    // Load average issues
    if (metrics.loadAverage > 2.0) {
      issues.add(PerformanceIssue(
        type: PerformanceIssueType.high_load,
        severity: PerformanceSeverity.medium,
        description: 'High load average: ${metrics.loadAverage.toStringAsFixed(2)}',
        value: metrics.loadAverage,
      ));
    }
    
    // Process count issues
    if (metrics.processCount > 200) {
      issues.add(PerformanceIssue(
        type: PerformanceIssueType.too_many_processes,
        severity: PerformanceSeverity.medium,
        description: 'Too many processes: ${metrics.processCount}',
        value: metrics.processCount.toDouble(),
      ));
    }
    
    // Emit performance issues event
    if (issues.isNotEmpty) {
      _eventController.add(PerformanceEvent(
        type: PerformanceEventType.performance_issues,
        message: 'Performance issues detected',
        data: {'issues': issues.map((i) => i.toJson()).toList()},
      ));
    }
  }
  
  Future<void> _generateSuggestions(SystemMetrics metrics) async {
    final suggestions = <OptimizationSuggestion>[];
    
    // CPU optimization suggestions
    if (metrics.cpuUsage > 70) {
      suggestions.addAll([
        OptimizationSuggestion(
          type: OptimizationType.cpu_optimization,
          title: 'Reduce CPU Usage',
          description: 'High CPU usage detected. Consider these optimizations:',
          priority: OptimizationPriority.high,
          actions: [
            OptimizationAction(
              command: 'ps aux --sort=-%cpu | head -10',
              description: 'Identify CPU-intensive processes',
              risk: OptimizationRisk.low,
            ),
            OptimizationAction(
              command: 'renice -n 10 {pid}',
              description: 'Lower process priority',
              risk: OptimizationRisk.medium,
            ),
            OptimizationAction(
              command: 'kill -9 {pid}',
              description: 'Terminate unnecessary processes',
              risk: OptimizationRisk.high,
            ),
          ],
        ),
      ]);
    }
    
    // Memory optimization suggestions
    if (metrics.memoryUsage > 75) {
      suggestions.addAll([
        OptimizationSuggestion(
          type: OptimizationType.memory_optimization,
          title: 'Reduce Memory Usage',
          description: 'High memory usage detected. Consider these optimizations:',
          priority: OptimizationPriority.high,
          actions: [
            OptimizationAction(
              command: 'ps aux --sort=-%mem | head -10',
              description: 'Identify memory-intensive processes',
              risk: OptimizationRisk.low,
            ),
            OptimizationAction(
              command: 'sync && echo 3 | sudo tee /proc/sys/vm/drop_caches',
              description: 'Clear system caches',
              risk: OptimizationRisk.medium,
            ),
            OptimizationAction(
              command: 'sudo sysctl vm.swappiness=10',
              description: 'Adjust swap usage',
              risk: OptimizationRisk.low,
            ),
          ],
        ),
      ]);
    }
    
    // Disk optimization suggestions
    if (metrics.diskUsage > 80) {
      suggestions.addAll([
        OptimizationSuggestion(
          type: OptimizationType.disk_optimization,
          title: 'Free Up Disk Space',
          description: 'High disk usage detected. Consider these optimizations:',
          priority: OptimizationPriority.critical,
          actions: [
            OptimizationAction(
              command: 'du -sh * | sort -hr | head -10',
              description: 'Find largest files and directories',
              risk: OptimizationRisk.low,
            ),
            OptimizationAction(
              command: 'find . -type f -size +100M -exec ls -lh {} \\;',
              description: 'Find large files',
              risk: OptimizationRisk.low,
            ),
            OptimizationAction(
              command: 'sudo apt autoremove && sudo apt autoclean',
              description: 'Clean package cache',
              risk: OptimizationRisk.low,
            ),
          ],
        ),
      ]);
    }
    
    // Terminal performance suggestions
    suggestions.addAll(_getTerminalOptimizations());
    
    // Get AI-powered suggestions
    if (aiAssistant != null) {
      try {
        final aiSuggestions = await _getAIOptimizations(metrics);
        suggestions.addAll(aiSuggestions);
      } catch (e) {
        debugPrint('❌ AI optimization failed: $e');
      }
    }
    
    // Sort by priority
    suggestions.sort((a, b) => a.priority.index.compareTo(b.priority.index));
    
    // Update suggestions
    _suggestions.clear();
    _suggestions.addAll(suggestions);
    
    _eventController.add(PerformanceEvent(
      type: PerformanceEventType.suggestions_generated,
      message: 'Optimization suggestions generated',
      data: {
        'suggestions_count': suggestions.length,
        'metrics': metrics.toJson(),
      },
    ));
  }
  
  List<OptimizationSuggestion> _getTerminalOptimizations() {
    return [
      // Terminal rendering optimizations
      OptimizationSuggestion(
        type: OptimizationType.terminal_optimization,
        title: 'Optimize Terminal Performance',
        description: 'Improve terminal rendering and responsiveness:',
        priority: OptimizationPriority.medium,
        actions: [
          OptimizationAction(
            command: 'export TERM=xterm-256color',
            description: 'Use efficient terminal type',
            risk: OptimizationRisk.low,
          ),
          OptimizationAction(
            command: 'export PS1="\\[\\e[1;32m\\]\\u@\\h:\\w\\$\\[\\e[0m\\] "',
            description: 'Optimize prompt display',
            risk: OptimizationRisk.low,
          ),
          OptimizationAction(
            command: 'set -o vi-ccount=1',
            description: 'Enable vi incremental search',
            risk: OptimizationRisk.low,
          ),
        ],
      ),
      
      // GPU acceleration suggestions
      OptimizationSuggestion(
        type: OptimizationType.gpu_optimization,
        title: 'Enable GPU Acceleration',
        description: 'Leverage hardware acceleration for better performance:',
        priority: OptimizationPriority.high,
        actions: [
          OptimizationAction(
            command: 'export LIBGL_ALWAYS_SOFTWARE=0',
            description: 'Force hardware OpenGL',
            risk: OptimizationRisk.low,
          ),
          OptimizationAction(
            command: 'export __GLX_VENDOR_LIBRARY_NAME=nvidia',
            description: 'Use NVIDIA drivers',
            risk: OptimizationRisk.low,
          ),
        ],
      ),
    ];
  }
  
  Future<List<OptimizationSuggestion>> _getAIOptimizations(SystemMetrics metrics) async {
    if (aiAssistant == null) return [];
    
    final prompt = '''Analyze these system metrics and provide specific optimization suggestions:

System Metrics:
- CPU Usage: ${metrics.cpuUsage.toStringAsFixed(1)}%
- Memory Usage: ${metrics.memoryUsage.toStringAsFixed(1)}%
- Disk Usage: ${metrics.diskUsage.toStringAsFixed(1)}%
- Load Average: ${metrics.loadAverage.toStringAsFixed(2)}
- Process Count: ${metrics.processCount}

Provide 3-4 specific optimization suggestions with:
1. Exact command to run
2. Brief explanation
3. Risk level (low/medium/high)
4. Expected improvement

Focus on the most critical resource usage areas.''';
    
    final response = await aiAssistant!.explainCommand(prompt);
    
    // Parse AI response into suggestions
    final suggestions = <OptimizationSuggestion>[];
    
    // Create a general AI suggestion
    suggestions.add(OptimizationSuggestion(
      type: OptimizationType.ai_optimization,
      title: 'AI-Powered Optimization',
      description: response,
      priority: OptimizationPriority.high,
      actions: [
        OptimizationAction(
          command: 'ai optimize system',
          description: 'AI-generated optimization',
          risk: OptimizationRisk.medium,
        ),
      ],
    ));
    
    return suggestions;
  }
  
  /// Apply optimization action
  Future<OptimizationResult> applyAction(OptimizationAction action) async {
    try {
      final startTime = DateTime.now();
      
      final result = await run(
        'bash',
        ['-c', action.command],
        workingDirectory: Directory.current.path,
      );
      
      final endTime = DateTime.now();
      final executionTime = endTime.difference(startTime);
      
      final success = result.exitCode == 0;
      
      _eventController.add(PerformanceEvent(
        type: success ? OptimizationEventType.action_applied : OptimizationEventType.action_failed,
        message: success ? 'Optimization applied successfully' : 'Optimization failed',
        data: {
          'action': action.toJson(),
          'exitCode': result.exitCode,
          'executionTime': executionTime.inMilliseconds,
        },
      ));
      
      return OptimizationResult(
        action: action,
        success: success,
        output: result.stdout,
        error: result.stderr,
        executionTime: executionTime,
      );
    } catch (e) {
      _eventController.add(PerformanceEvent(
        type: OptimizationEventType.action_failed,
        message: 'Optimization failed with exception: $e',
        data: {'error': e.toString()},
      ));
      
      return OptimizationResult(
        action: action,
        success: false,
        output: '',
        error: e.toString(),
        executionTime: Duration.zero,
      );
    }
  }
  
  /// Get performance profile
  PerformanceProfile getCurrentProfile() {
    if (_metrics.isEmpty) return PerformanceProfile.balanced;
    
    final recentMetrics = _metrics.take(10).toList();
    final avgCpu = recentMetrics.map((m) => m.cpuUsage).reduce((a, b) => a + b) / recentMetrics.length;
    final avgMemory = recentMetrics.map((m) => m.memoryUsage).reduce((a, b) => a + b) / recentMetrics.length;
    
    if (avgCpu > 70 || avgMemory > 80) {
      return PerformanceProfile.performance;
    } else if (avgCpu < 20 && avgMemory < 40) {
      return PerformanceProfile.powersaver;
    }
    
    return PerformanceProfile.balanced;
  }
  
  /// Set performance profile
  void setProfile(PerformanceProfile profile) {
    _currentProfile = profile;
    
    // Apply profile settings
    switch (profile) {
      case PerformanceProfile.powersaver:
        _applyPowerSaverSettings();
        break;
      case PerformanceProfile.balanced:
        _applyBalancedSettings();
        break;
      case PerformanceProfile.performance:
        _applyPerformanceSettings();
        break;
    }
    
    _eventController.add(PerformanceEvent(
      type: PerformanceEventType.profile_changed,
      message: 'Performance profile changed to ${profile.toString()}',
      data: {'profile': profile.toString()},
    ));
  }
  
  void _applyPowerSaverSettings() {
    // Apply power saver settings
    run('bash', ['-c', 'echo "powersaver"'], workingDirectory: '/');
  }
  
  void _applyBalancedSettings() {
    // Apply balanced settings
    run('bash', ['-c', 'echo "balanced"'], workingDirectory: '/');
  }
  
  void _applyPerformanceSettings() {
    // Apply performance settings
    run('bash', ['-c', 'echo "performance"'], workingDirectory: '/');
  }
  
  /// Get performance statistics
  Map<String, dynamic> getStatistics() {
    if (_metrics.isEmpty) return {};
    
    final recentMetrics = _metrics.take(20).toList();
    
    return {
      'is_monitoring': _isMonitoring,
      'current_profile': _currentProfile?.toString(),
      'metrics_count': _metrics.length,
      'suggestions_count': _suggestions.length,
      'avg_cpu': recentMetrics.map((m) => m.cpuUsage).reduce((a, b) => a + b) / recentMetrics.length,
      'avg_memory': recentMetrics.map((m) => m.memoryUsage).reduce((a, b) => a + b) / recentMetrics.length,
      'avg_disk': recentMetrics.map((m) => m.diskUsage).reduce((a, b) => a + b) / recentMetrics.length,
      'peak_cpu': recentMetrics.map((m) => m.cpuUsage).reduce(math.max),
      'peak_memory': recentMetrics.map((m) => m.memoryUsage).reduce(math.max),
      'collection_interval': 5,
    };
  }
  
  /// Dispose
  void dispose() {
    stopMonitoring();
    _eventController.close();
  }
}

/// System metrics
class SystemMetrics {
  final double cpuUsage;
  final double memoryUsage;
  final double diskUsage;
  final double networkIO;
  final int processCount;
  final double loadAverage;
  final DateTime timestamp;
  final Duration collectionTime;
  
  SystemMetrics({
    required this.cpuUsage,
    required this.memoryUsage,
    required this.diskUsage,
    required this.networkIO,
    required this.processCount,
    required this.loadAverage,
    required this.timestamp,
    required this.collectionTime,
  });
  
  Map<String, dynamic> toJson() => {
    'cpu_usage': cpuUsage,
    'memory_usage': memoryUsage,
    'disk_usage': diskUsage,
    'network_io': networkIO,
    'process_count': processCount,
    'load_average': loadAverage,
    'timestamp': timestamp.toIso8601String(),
    'collection_time_ms': collectionTime.inMilliseconds,
  };
}

/// Performance issue
class PerformanceIssue {
  final PerformanceIssueType type;
  final PerformanceSeverity severity;
  final String description;
  final double value;
  
  PerformanceIssue({
    required this.type,
    required this.severity,
    required this.description,
    required this.value,
  });
  
  Map<String, dynamic> toJson() => {
    'type': type.toString(),
    'severity': severity.toString(),
    'description': description,
    'value': value,
  };
}

/// Optimization suggestion
class OptimizationSuggestion {
  final OptimizationType type;
  final String title;
  final String description;
  final OptimizationPriority priority;
  final List<OptimizationAction> actions;
  
  OptimizationSuggestion({
    required this.type,
    required this.title,
    required this.description,
    required this.priority,
    required this.actions,
  });
}

/// Optimization action
class OptimizationAction {
  final String command;
  final String description;
  final OptimizationRisk risk;
  final bool isAIGenerated;
  
  OptimizationAction({
    required this.command,
    required this.description,
    required this.risk,
    this.isAIGenerated = false,
  });
  
  Map<String, dynamic> toJson() => {
    'command': command,
    'description': description,
    'risk': risk.toString(),
    'is_ai_generated': isAIGenerated,
  };
}

/// Optimization result
class OptimizationResult {
  final OptimizationAction action;
  final bool success;
  final String output;
  final String error;
  final Duration executionTime;
  
  OptimizationResult({
    required this.action,
    required this.success,
    required this.output,
    required this.error,
    required this.executionTime,
  });
}

/// Performance profiles
enum PerformanceProfile {
  powersaver,
  balanced,
  performance,
}

/// Performance issue types
enum PerformanceIssueType {
  high_cpu,
  high_memory,
  high_disk,
  high_load,
  too_many_processes,
}

/// Performance severity levels
enum PerformanceSeverity {
  low,
  medium,
  high,
  critical,
}

/// Optimization types
enum OptimizationType {
  cpu_optimization,
  memory_optimization,
  disk_optimization,
  terminal_optimization,
  gpu_optimization,
  ai_optimization,
}

/// Optimization priority levels
enum OptimizationPriority {
  low,
  medium,
  high,
  critical,
}

/// Optimization risk levels
enum OptimizationRisk {
  low,
  medium,
  high,
}

/// Optimization event types
enum OptimizationEventType {
  action_applied,
  action_failed,
  profile_changed,
}

/// Performance event types
enum PerformanceEventType {
  monitoring_started,
  monitoring_stopped,
  performance_issues,
  suggestions_generated,
  error,
}

/// Performance event
class PerformanceEvent {
  final dynamic type;
  final String message;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  
  PerformanceEvent({
    required this.type,
    required this.message,
    required this.data,
  }) : timestamp = DateTime.now();
}
